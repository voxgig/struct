// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
//
// Voxgig Struct — RE2-subset regex engine, pure Rust, no runtime deps.
//
// Direct port of c/src/regex.c (Thompson NFA via two state sets).
// Provides an API surface compatible with the subset of the `regex`
// crate that the Voxgig Struct port uses:
//
//   - Regex::new(pattern)               -> Result<Regex, RegexError>
//   - re.is_match(input)                -> bool
//   - re.captures(input)                -> Option<Captures<'_>>
//   - re.captures_iter(input)           -> CapturesIter<'_>
//   - re.replace_all(input, &str)       -> Cow<'_, str>     ($&, $0..$9)
//   - re.replace_all(input, |c| String) -> Cow<'_, str>     (closure)
//   - Captures::get(i) -> Option<Match<'_>>; iter(); index by usize
//
// Dialect mirrors c/src/regex.h:
//   . anchors ^ $ . groups (...) (?:...) (?P<name>...) (names ignored)
//   . classes [abc] [^abc] [a-z]    predefined \d \D \s \S \w \W
//   . quantifiers * + ? {n} {n,} {n,m} and lazy *? +? ?? {..}?
//   . word boundary \b \B   . alternation a|b
//   . NOT supported: backref, lookaround, possessive, atomic.

use std::borrow::Cow;

const MAX_GROUPS: usize = 16;

// ---------- instructions ----------

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Op {
    Char(u8),
    Any,
    Class,
    Match,
    Jmp(i32),
    Split(i32, i32),
    Save(usize),
    Bol,
    Eol,
    Wb,
    Nwb,
}

#[derive(Clone, Copy)]
struct CharClass {
    bits: [u8; 32],
}

impl CharClass {
    fn zero() -> Self {
        Self { bits: [0; 32] }
    }
    fn set(&mut self, c: u8) {
        self.bits[(c >> 3) as usize] |= 1u8 << (c & 7);
    }
    fn set_range(&mut self, lo: u8, hi: u8) {
        let (lo, hi) = if lo > hi { (hi, lo) } else { (lo, hi) };
        for c in lo..=hi {
            self.set(c);
        }
    }
    fn has(&self, c: u8) -> bool {
        (self.bits[(c >> 3) as usize] >> (c & 7)) & 1 == 1
    }
    fn negate(&mut self) {
        for b in self.bits.iter_mut() {
            *b = !*b;
        }
    }
    fn predef(&mut self, c: u8) {
        match c {
            b'd' => self.set_range(b'0', b'9'),
            b'D' => {
                self.set_range(0, 255);
                for x in b'0'..=b'9' {
                    self.bits[(x >> 3) as usize] &= !(1u8 << (x & 7));
                }
            }
            b's' => {
                for c in [b' ', b'\t', b'\n', b'\r', 0x0C, 0x0B].iter() {
                    self.set(*c);
                }
            }
            b'S' => {
                self.set_range(0, 255);
                for c in [b' ', b'\t', b'\n', b'\r', 0x0C, 0x0B].iter() {
                    self.bits[(*c >> 3) as usize] &= !(1u8 << (c & 7));
                }
            }
            b'w' => {
                self.set_range(b'0', b'9');
                self.set_range(b'A', b'Z');
                self.set_range(b'a', b'z');
                self.set(b'_');
            }
            b'W' => {
                self.set_range(0, 255);
                for x in b'0'..=b'9' {
                    self.bits[(x >> 3) as usize] &= !(1u8 << (x & 7));
                }
                for x in b'A'..=b'Z' {
                    self.bits[(x >> 3) as usize] &= !(1u8 << (x & 7));
                }
                for x in b'a'..=b'z' {
                    self.bits[(x >> 3) as usize] &= !(1u8 << (x & 7));
                }
                self.bits[(b'_' >> 3) as usize] &= !(1u8 << (b'_' & 7));
            }
            _ => {}
        }
    }
}

#[derive(Clone, Copy)]
struct Insn {
    op: Op,
    cc: CharClass, // only used for Op::Class
}

impl Insn {
    fn new(op: Op) -> Self {
        Self {
            op,
            cc: CharClass::zero(),
        }
    }
}

// ---------- compiled regex ----------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RegexError(pub String);

impl std::fmt::Display for RegexError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "regex: {}", self.0)
    }
}

impl std::error::Error for RegexError {}

pub struct Regex {
    code: Vec<Insn>,
    ngroups: usize, // including group 0
    anchored_start: bool,
}

// ---------- parser ----------

struct Parser<'a> {
    src: &'a [u8],
    pos: usize,
    next_group: usize,
    err: Option<String>,
    code: Vec<Insn>,
}

fn hexval(c: u8) -> i32 {
    match c {
        b'0'..=b'9' => (c - b'0') as i32,
        b'a'..=b'f' => (c - b'a') as i32 + 10,
        b'A'..=b'F' => (c - b'A') as i32 + 10,
        _ => -1,
    }
}

impl<'a> Parser<'a> {
    fn perr(&mut self, msg: &str) {
        if self.err.is_none() {
            self.err = Some(format!("regex parse error at {}: {}", self.pos, msg));
        }
    }

    // Returns (byte, predef_letter, kind):
    //   kind 0 = byte, kind 1 = predef class (predef_letter set), kind 2 = \b/\B (predef_letter set)
    fn parse_escape(&mut self) -> (u8, u8, u8) {
        if self.pos >= self.src.len() {
            self.perr("trailing backslash");
            return (0, 0, 0);
        }
        let c = self.src[self.pos];
        self.pos += 1;
        match c {
            b'n' => (b'\n', 0, 0),
            b't' => (b'\t', 0, 0),
            b'r' => (b'\r', 0, 0),
            b'f' => (0x0C, 0, 0),
            b'v' => (0x0B, 0, 0),
            b'0' => (0, 0, 0),
            b'a' => (0x07, 0, 0),
            b'e' => (27, 0, 0),
            b'x' => {
                if self.pos + 1 >= self.src.len() {
                    self.perr("bad \\xNN");
                    return (0, 0, 0);
                }
                let h1 = hexval(self.src[self.pos]);
                let h2 = hexval(self.src[self.pos + 1]);
                if h1 < 0 || h2 < 0 {
                    self.perr("bad \\xNN");
                    return (0, 0, 0);
                }
                self.pos += 2;
                (((h1 << 4) | h2) as u8, 0, 0)
            }
            b'd' | b'D' | b's' | b'S' | b'w' | b'W' => (0, c, 1),
            b'b' | b'B' => (0, c, 2),
            _ => (c, 0, 0),
        }
    }

    fn parse_class(&mut self) -> CharClass {
        let mut out = CharClass::zero();
        let mut neg = false;
        if self.pos < self.src.len() && self.src[self.pos] == b'^' {
            neg = true;
            self.pos += 1;
        }
        let mut first = true;
        while self.pos < self.src.len() && (first || self.src[self.pos] != b']') {
            first = false;
            let c;
            if self.src[self.pos] == b'\\' {
                self.pos += 1;
                let (b, p, k) = self.parse_escape();
                if k == 1 {
                    let mut sub = CharClass::zero();
                    sub.predef(p);
                    for i in 0..32 {
                        out.bits[i] |= sub.bits[i];
                    }
                    continue;
                }
                c = if k == 2 { 8 } else { b };
            } else {
                c = self.src[self.pos];
                self.pos += 1;
            }
            if self.pos + 1 < self.src.len()
                && self.src[self.pos] == b'-'
                && self.src[self.pos + 1] != b']'
            {
                self.pos += 1;
                let hi;
                if self.src[self.pos] == b'\\' {
                    self.pos += 1;
                    let (b, _p, k) = self.parse_escape();
                    hi = if k == 0 { b } else { b'-' };
                } else {
                    hi = self.src[self.pos];
                    self.pos += 1;
                }
                out.set_range(c, hi);
            } else {
                out.set(c);
            }
        }
        if self.pos >= self.src.len() || self.src[self.pos] != b']' {
            self.perr("unclosed [");
            return out;
        }
        self.pos += 1;
        if neg {
            out.negate();
        }
        out
    }

    fn emit(&mut self, op: Op) -> usize {
        let ix = self.code.len();
        self.code.push(Insn::new(op));
        ix
    }

    // Returns the index of the first emitted instruction for this atom.
    fn parse_atom(&mut self) -> usize {
        if self.pos >= self.src.len() {
            return self.code.len();
        }
        let start = self.code.len();
        let c = self.src[self.pos];
        if c == b'(' {
            self.pos += 1;
            let mut capture = true;
            if self.pos + 1 < self.src.len()
                && self.src[self.pos] == b'?'
                && self.src[self.pos + 1] == b':'
            {
                capture = false;
                self.pos += 2;
            } else if self.pos + 2 < self.src.len()
                && self.src[self.pos] == b'?'
                && self.src[self.pos + 1] == b'P'
                && self.src[self.pos + 2] == b'<'
            {
                // Named group — consume name; we don't expose names but still capture.
                self.pos += 3;
                while self.pos < self.src.len() && self.src[self.pos] != b'>' {
                    self.pos += 1;
                }
                if self.pos < self.src.len() {
                    self.pos += 1;
                }
            }
            let group = if capture {
                let g = self.next_group;
                self.next_group += 1;
                self.emit(Op::Save(g * 2));
                g
            } else {
                0
            };
            self.parse_alt();
            if self.pos >= self.src.len() || self.src[self.pos] != b')' {
                self.perr("unclosed (");
                return start;
            }
            self.pos += 1;
            if capture {
                self.emit(Op::Save(group * 2 + 1));
            }
        } else if c == b'[' {
            self.pos += 1;
            let cc = self.parse_class();
            let ix = self.emit(Op::Class);
            self.code[ix].cc = cc;
        } else if c == b'.' {
            self.pos += 1;
            self.emit(Op::Any);
        } else if c == b'^' {
            self.pos += 1;
            self.emit(Op::Bol);
        } else if c == b'$' {
            self.pos += 1;
            self.emit(Op::Eol);
        } else if c == b'\\' {
            self.pos += 1;
            let (b, p, k) = self.parse_escape();
            match k {
                1 => {
                    let mut cc = CharClass::zero();
                    cc.predef(p);
                    let ix = self.emit(Op::Class);
                    self.code[ix].cc = cc;
                }
                2 => {
                    self.emit(if p == b'b' { Op::Wb } else { Op::Nwb });
                }
                _ => {
                    self.emit(Op::Char(b));
                }
            }
        } else if c == b')' || c == b'|' {
            return start;
        } else {
            self.pos += 1;
            self.emit(Op::Char(c));
        }
        start
    }

    fn code_clone(&mut self, from: usize, to: usize) -> usize {
        let delta = self.code.len() as i32 - from as i32;
        let start = self.code.len();
        for i in from..to {
            let mut insn = self.code[i];
            match insn.op {
                Op::Jmp(t) if (t as usize) >= from && (t as usize) < to => {
                    insn.op = Op::Jmp(t + delta);
                }
                Op::Split(x, y) => {
                    let nx = if (x as usize) >= from && (x as usize) < to {
                        x + delta
                    } else {
                        x
                    };
                    let ny = if (y as usize) >= from && (y as usize) < to {
                        y + delta
                    } else {
                        y
                    };
                    insn.op = Op::Split(nx, ny);
                }
                _ => {}
            }
            self.code.push(insn);
        }
        start
    }

    fn shift_targets_after(&mut self, from: usize, by: i32) {
        for i in (from + 1)..self.code.len() {
            match &mut self.code[i].op {
                Op::Jmp(t) if *t as usize >= from => {
                    *t += by;
                }
                Op::Split(x, y) => {
                    if *x as usize >= from {
                        *x += by;
                    }
                    if *y as usize >= from {
                        *y += by;
                    }
                }
                _ => {}
            }
        }
    }

    fn apply_quant(&mut self, start: usize, q: u8, n_lo: i32, n_hi: i32, lazy: bool) {
        let end = self.code.len();
        let alen = end - start;
        if alen == 0 {
            return;
        }

        match q {
            b'?' => {
                // SPLIT before atom, falling through after.
                self.code.insert(start, Insn::new(Op::Split(0, 0)));
                let after = self.code.len() as i32;
                let to_atom = (start + 1) as i32;
                self.code[start].op = Op::Split(
                    if lazy { after } else { to_atom },
                    if lazy { to_atom } else { after },
                );
                self.shift_targets_after(start, 1);
            }
            b'*' => {
                // L0: SPLIT L1 L2; atom; JMP L0; L2:
                self.code.insert(start, Insn::new(Op::Split(0, 0)));
                self.shift_targets_after(start, 1);
                // We've inserted one before start; compute after the atom (now end+1).
                let after_atom = self.code.len(); // before JMP emit
                self.emit(Op::Jmp(start as i32));
                let exit = self.code.len();
                let to_atom = (start + 1) as i32;
                self.code[start].op = Op::Split(
                    if lazy { exit as i32 } else { to_atom },
                    if lazy { to_atom } else { exit as i32 },
                );
                let _ = after_atom;
            }
            b'+' => {
                let _ix = self.emit(Op::Split(0, 0));
                let after = self.code.len() as i32;
                let s_ix = self.code.len() - 1;
                self.code[s_ix].op = Op::Split(
                    if lazy { after } else { start as i32 },
                    if lazy { start as i32 } else { after },
                );
            }
            b'{' => {
                // Emit n_lo mandatory copies (we already have one — the original atom).
                for _ in 1..n_lo {
                    self.code_clone(start, end);
                }
                if n_hi == -1 {
                    // {n,}: Kleene-star of the atom appended.
                    let split_ix = self.emit(Op::Split(0, 0));
                    let atom_start = self.code.len();
                    self.code_clone(start, end);
                    let jmp_ix = self.emit(Op::Jmp(split_ix as i32));
                    let exit = self.code.len() as i32;
                    self.code[split_ix].op = Op::Split(
                        if lazy { exit } else { atom_start as i32 },
                        if lazy { atom_start as i32 } else { exit },
                    );
                    let _ = jmp_ix;
                } else if n_hi > n_lo {
                    for _ in 0..(n_hi - n_lo) {
                        let sp = self.emit(Op::Split(0, 0));
                        let clone_start = self.code.len();
                        self.code_clone(start, end);
                        let after = self.code.len() as i32;
                        self.code[sp].op = Op::Split(
                            if lazy { after } else { clone_start as i32 },
                            if lazy { clone_start as i32 } else { after },
                        );
                    }
                }
            }
            _ => {}
        }
    }

    fn parse_concat(&mut self) -> usize {
        let start = self.code.len();
        while self.pos < self.src.len() && self.src[self.pos] != b')' && self.src[self.pos] != b'|'
        {
            let atom_start = self.parse_atom();
            if self.err.is_some() {
                return start;
            }
            if self.pos < self.src.len() {
                let q = self.src[self.pos];
                if q == b'*' || q == b'+' || q == b'?' {
                    self.pos += 1;
                    let mut lazy = false;
                    if self.pos < self.src.len() && self.src[self.pos] == b'?' {
                        lazy = true;
                        self.pos += 1;
                    }
                    self.apply_quant(atom_start, q, 0, 0, lazy);
                } else if q == b'{' {
                    let save = self.pos;
                    self.pos += 1;
                    let mut n_lo: i32 = 0;
                    let mut got_lo = false;
                    while self.pos < self.src.len() && self.src[self.pos].is_ascii_digit() {
                        n_lo = n_lo * 10 + (self.src[self.pos] - b'0') as i32;
                        got_lo = true;
                        self.pos += 1;
                    }
                    let mut n_hi: i32 = n_lo;
                    let mut open = false;
                    if !got_lo {
                        self.pos = save;
                    } else {
                        if self.pos < self.src.len() && self.src[self.pos] == b',' {
                            self.pos += 1;
                            n_hi = -1;
                            let mut hi: i32 = 0;
                            let mut got_hi = false;
                            while self.pos < self.src.len() && self.src[self.pos].is_ascii_digit() {
                                hi = hi * 10 + (self.src[self.pos] - b'0') as i32;
                                got_hi = true;
                                self.pos += 1;
                            }
                            if got_hi {
                                n_hi = hi;
                            } else {
                                open = true;
                            }
                        }
                        if self.pos < self.src.len() && self.src[self.pos] == b'}' {
                            self.pos += 1;
                            let mut lazy = false;
                            if self.pos < self.src.len() && self.src[self.pos] == b'?' {
                                lazy = true;
                                self.pos += 1;
                            }
                            self.apply_quant(
                                atom_start,
                                b'{',
                                n_lo,
                                if open { -1 } else { n_hi },
                                lazy,
                            );
                        } else {
                            self.perr("bad {n,m}");
                        }
                    }
                }
            }
        }
        start
    }

    fn parse_alt(&mut self) -> usize {
        let start = self.parse_concat();
        if self.err.is_some() {
            return start;
        }
        while self.pos < self.src.len() && self.src[self.pos] == b'|' {
            let branch1_end = self.code.len();
            let jmp_ix = self.emit(Op::Jmp(0)); // placeholder
            let branch2_start = self.code.len();
            // Insert SPLIT at `start`.
            self.code.insert(start, Insn::new(Op::Split(0, 0)));
            // Patch jumps inside the moved block (everything from start+1 to end).
            for i in (start + 1)..self.code.len() {
                match &mut self.code[i].op {
                    Op::Jmp(t) if *t as usize >= start => {
                        *t += 1;
                    }
                    Op::Split(x, y) => {
                        if *x as usize >= start {
                            *x += 1;
                        }
                        if *y as usize >= start {
                            *y += 1;
                        }
                    }
                    _ => {}
                }
            }
            self.code[start].op = Op::Split((start + 1) as i32, (branch2_start + 1) as i32);
            let _ = branch1_end;
            let jmp_ix = jmp_ix + 1;
            self.pos += 1;
            self.parse_concat();
            self.code[jmp_ix].op = Op::Jmp(self.code.len() as i32);
        }
        start
    }
}

// ---------- compile ----------

impl Regex {
    pub fn new(pattern: &str) -> Result<Self, RegexError> {
        let bytes = pattern.as_bytes();
        let mut p = Parser {
            src: bytes,
            pos: 0,
            next_group: 1, // 0 reserved for whole match
            err: None,
            code: Vec::new(),
        };
        // Wrap whole pattern in implicit group 0.
        p.code.push(Insn::new(Op::Save(0)));
        let anchored_start = !bytes.is_empty() && bytes[0] == b'^';
        p.parse_alt();
        if let Some(e) = p.err {
            return Err(RegexError(e));
        }
        if p.pos < bytes.len() {
            return Err(RegexError(format!(
                "regex parse error at {}: unexpected )",
                p.pos
            )));
        }
        p.code.push(Insn::new(Op::Save(1)));
        p.code.push(Insn::new(Op::Match));
        Ok(Self {
            code: p.code,
            ngroups: p.next_group,
            anchored_start,
        })
    }

    pub fn is_match(&self, input: &str) -> bool {
        self.find_first(input.as_bytes()).is_some()
    }

    pub fn captures<'h>(&self, input: &'h str) -> Option<Captures<'h>> {
        let slots = self.find_first(input.as_bytes())?;
        Some(Captures {
            input,
            slots,
            ngroups: self.ngroups,
        })
    }

    pub fn captures_iter<'r, 'h>(&'r self, input: &'h str) -> CapturesIter<'r, 'h> {
        CapturesIter {
            re: self,
            input,
            pos: 0,
            done: false,
        }
    }

    /// Replace the FIRST match only. Mirrors `regex` crate `replace`.
    pub fn replace<'h, R: Replacer>(&self, input: &'h str, mut rep: R) -> Cow<'h, str> {
        let bytes = input.as_bytes();
        let mut start = 0usize;
        let slots = loop {
            if start > bytes.len() {
                return Cow::Borrowed(input);
            }
            if let Some(s) = self.match_at(bytes, start) {
                break s;
            }
            if self.anchored_start {
                return Cow::Borrowed(input);
            }
            start += 1;
        };
        let mut out = String::with_capacity(input.len());
        out.push_str(&input[..start]);
        let caps = Captures {
            input,
            slots: slots.clone(),
            ngroups: self.ngroups,
        };
        rep.replace_into(&caps, &mut out);
        let mend = slots[1] as usize;
        out.push_str(&input[mend..]);
        Cow::Owned(out)
    }

    pub fn replace_all<'h, R: Replacer>(&self, input: &'h str, mut rep: R) -> Cow<'h, str> {
        let bytes = input.as_bytes();
        let mut out = String::new();
        let mut pos: usize = 0;
        let mut any = false;
        while pos <= bytes.len() {
            let mut start = pos;
            let mut found_slots: Option<Vec<i32>> = None;
            while start <= bytes.len() {
                if let Some(s) = self.match_at(bytes, start) {
                    found_slots = Some(s);
                    break;
                }
                if self.anchored_start && start > pos {
                    break;
                }
                start += 1;
                if start > bytes.len() {
                    break;
                }
            }
            let slots = match found_slots {
                Some(s) => s,
                None => {
                    out.push_str(&input[pos..]);
                    break;
                }
            };
            any = true;
            // Copy pre-match.
            out.push_str(&input[pos..start]);
            let caps = Captures {
                input,
                slots: slots.clone(),
                ngroups: self.ngroups,
            };
            rep.replace_into(&caps, &mut out);
            let mend = slots[1] as usize;
            if slots[1] == slots[0] {
                // Empty match: emit one char and advance.
                if mend < bytes.len() {
                    let ch = input[mend..].chars().next().unwrap();
                    out.push(ch);
                    pos = mend + ch.len_utf8();
                } else {
                    pos = mend + 1;
                }
            } else {
                pos = mend;
            }
        }
        if any {
            Cow::Owned(out)
        } else {
            Cow::Borrowed(input)
        }
    }

    // ---- internal matching ----

    fn find_first(&self, bytes: &[u8]) -> Option<Vec<i32>> {
        let mut start: usize = 0;
        loop {
            if let Some(s) = self.match_at(bytes, start) {
                return Some(s);
            }
            if self.anchored_start {
                return None;
            }
            if start > bytes.len() {
                return None;
            }
            start += 1;
        }
    }

    fn match_at(&self, input: &[u8], start: usize) -> Option<Vec<i32>> {
        let nslots = self.ngroups * 2;
        let mut cur = ThreadList::new(self.code.len());
        let mut nxt = ThreadList::new(self.code.len());
        let init: Vec<i32> = vec![-1; nslots];
        cur.gen = 1; // bump past initial visited[] = 0
        cur.add(self, input, 0, &init, start);
        let mut best: Option<Vec<i32>> = None;
        let mut sp = start;
        loop {
            if cur.threads.is_empty() {
                break;
            }
            nxt.reset();
            let c: i32 = if sp < input.len() {
                input[sp] as i32
            } else {
                -1
            };
            for th in &cur.threads {
                let insn = &self.code[th.pc];
                match insn.op {
                    Op::Char(b) if c == b as i32 => {
                        nxt.add(self, input, th.pc + 1, &th.slots, sp + 1);
                    }
                    Op::Any if c >= 0 && c != b'\n' as i32 => {
                        nxt.add(self, input, th.pc + 1, &th.slots, sp + 1);
                    }
                    Op::Class if c >= 0 && insn.cc.has(c as u8) => {
                        nxt.add(self, input, th.pc + 1, &th.slots, sp + 1);
                    }
                    Op::Match => {
                        // Always overwrite: descendants of higher-priority
                        // threads (those iterated before this Match thread)
                        // are still alive in nxt and any later Match they
                        // produce is in a strictly-higher-priority lineage.
                        best = Some(th.slots.clone());
                        break;
                    }
                    _ => {}
                }
            }
            std::mem::swap(&mut cur, &mut nxt);
            sp += 1;
            if cur.threads.is_empty() {
                break;
            }
        }
        // Drain remaining current threads at EOI (some may have advanced past
        // last char and now point at Match via epsilons). Always overwrite —
        // same priority rule as the main loop.
        for th in &cur.threads {
            if matches!(self.code[th.pc].op, Op::Match) {
                best = Some(th.slots.clone());
                break;
            }
        }
        best
    }
}

// ---------- thread list (Thompson NFA driver) ----------

#[derive(Clone)]
struct Thread {
    pc: usize,
    slots: Vec<i32>,
}

struct ThreadList {
    threads: Vec<Thread>,
    visited: Vec<u32>,
    gen: u32,
}

impl ThreadList {
    fn new(code_len: usize) -> Self {
        Self {
            threads: Vec::new(),
            visited: vec![0; code_len],
            gen: 0,
        }
    }

    fn reset(&mut self) {
        self.threads.clear();
        self.gen = self.gen.wrapping_add(1);
        if self.gen == 0 {
            self.visited.iter_mut().for_each(|v| *v = 0);
            self.gen = 1;
        }
    }

    fn add(&mut self, re: &Regex, input: &[u8], pc: usize, slots: &[i32], sp: usize) {
        // Iterative epsilon-closure: we walk Jmp/Split/Save/Bol/Eol/Wb/Nwb
        // until we hit a char-consuming op or Match. A recursive version
        // overflows the stack on long Thompson chains (e.g. `a{0,10000}`
        // unrolls into 10000 chained Splits — `cargo test` aborted with
        // SIGABRT on the pathological-regex panel before this loop landed).
        //
        // The stack mirrors the recursive order: Split pushes y first then
        // x, so x is processed first (priority preserved).
        let mut stack: Vec<(usize, Vec<i32>)> = vec![(pc, slots.to_vec())];
        while let Some((cur_pc, cur_slots)) = stack.pop() {
            if cur_pc >= re.code.len() {
                continue;
            }
            if self.visited[cur_pc] == self.gen {
                continue;
            }
            self.visited[cur_pc] = self.gen;
            match re.code[cur_pc].op {
                Op::Jmp(t) => {
                    stack.push((t as usize, cur_slots));
                }
                Op::Split(x, y) => {
                    // Push y first so x (higher priority) is popped first.
                    stack.push((y as usize, cur_slots.clone()));
                    stack.push((x as usize, cur_slots));
                }
                Op::Save(slot) => {
                    let mut ns = cur_slots;
                    ns[slot] = sp as i32;
                    stack.push((cur_pc + 1, ns));
                }
                Op::Bol => {
                    if sp == 0 || (sp - 1 < input.len() && input[sp - 1] == b'\n') {
                        stack.push((cur_pc + 1, cur_slots));
                    }
                }
                Op::Eol => {
                    if sp >= input.len() || input[sp] == b'\n' {
                        stack.push((cur_pc + 1, cur_slots));
                    }
                }
                Op::Wb | Op::Nwb => {
                    let left = sp > 0
                        && sp - 1 < input.len()
                        && (input[sp - 1].is_ascii_alphanumeric() || input[sp - 1] == b'_');
                    let right = sp < input.len()
                        && (input[sp].is_ascii_alphanumeric() || input[sp] == b'_');
                    let at_boundary = left != right;
                    let want = matches!(re.code[cur_pc].op, Op::Wb);
                    if at_boundary == want {
                        stack.push((cur_pc + 1, cur_slots));
                    }
                }
                _ => {
                    // Char-consuming op (or Match): queue thread.
                    self.threads.push(Thread {
                        pc: cur_pc,
                        slots: cur_slots,
                    });
                }
            }
        }
    }
}

impl ThreadList {
    // Convenience: re-init visited with the right size when first used.
}

// Initial gen tracking: bump before first use to avoid 0 match.
impl ThreadList {
    #[allow(dead_code)] // kept for the regex engine's reset hooks.
    #[inline]
    fn ensure_first_gen(&mut self) {
        if self.gen == 0 {
            self.gen = 1;
        }
    }
}

// ---------- Captures ----------

#[derive(Debug, Clone, Copy)]
pub struct Match<'h> {
    text: &'h str,
    start: usize,
    end: usize,
}

impl<'h> Match<'h> {
    pub fn as_str(&self) -> &'h str {
        &self.text[self.start..self.end]
    }
    pub fn start(&self) -> usize {
        self.start
    }
    pub fn end(&self) -> usize {
        self.end
    }
}

pub struct Captures<'h> {
    input: &'h str,
    slots: Vec<i32>,
    ngroups: usize,
}

impl<'h> Captures<'h> {
    pub fn get(&self, i: usize) -> Option<Match<'h>> {
        if i >= self.ngroups {
            return None;
        }
        let s = self.slots[2 * i];
        let e = self.slots[2 * i + 1];
        if s < 0 || e < 0 || e < s {
            return None;
        }
        Some(Match {
            text: self.input,
            start: s as usize,
            end: e as usize,
        })
    }
    pub fn len(&self) -> usize {
        self.ngroups
    }
    pub fn is_empty(&self) -> bool {
        self.ngroups == 0
    }
    pub fn iter(&self) -> impl Iterator<Item = Option<Match<'h>>> + '_ {
        (0..self.ngroups).map(move |i| self.get(i))
    }
}

impl<'h> std::ops::Index<usize> for Captures<'h> {
    type Output = str;
    fn index(&self, i: usize) -> &str {
        self.get(i).map(|m| m.as_str()).unwrap_or("")
    }
}

// ---------- CapturesIter ----------

pub struct CapturesIter<'r, 'h> {
    re: &'r Regex,
    input: &'h str,
    pos: usize,
    done: bool,
}

impl<'r, 'h> Iterator for CapturesIter<'r, 'h> {
    type Item = Captures<'h>;
    fn next(&mut self) -> Option<Self::Item> {
        if self.done {
            return None;
        }
        let bytes = self.input.as_bytes();
        let mut start = self.pos;
        let mut found: Option<Vec<i32>> = None;
        loop {
            if start > bytes.len() {
                break;
            }
            if let Some(s) = self.re.match_at(bytes, start) {
                found = Some(s);
                break;
            }
            if self.re.anchored_start {
                break;
            }
            start += 1;
        }
        let slots = found?;
        // Advance: if match was empty, step by 1 to avoid infinite loop.
        let mend = slots[1] as usize;
        self.pos = if slots[1] == slots[0] { mend + 1 } else { mend };
        if mend > bytes.len() {
            self.done = true;
        }
        Some(Captures {
            input: self.input,
            slots,
            ngroups: self.re.ngroups,
        })
    }
}

// ---------- Replacer trait ----------

pub trait Replacer {
    fn replace_into(&mut self, caps: &Captures<'_>, dst: &mut String);
}

impl Replacer for &str {
    fn replace_into(&mut self, caps: &Captures<'_>, dst: &mut String) {
        let bytes = self.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b'$' && i + 1 < bytes.len() {
                let nc = bytes[i + 1];
                if nc == b'&' {
                    if let Some(m) = caps.get(0) {
                        dst.push_str(m.as_str());
                    }
                    i += 2;
                    continue;
                }
                if nc.is_ascii_digit() {
                    let g = (nc - b'0') as usize;
                    if let Some(m) = caps.get(g) {
                        dst.push_str(m.as_str());
                    }
                    i += 2;
                    continue;
                }
                if nc == b'{' {
                    // ${N} backref — read digits until '}'.
                    let mut j = i + 2;
                    let mut g: usize = 0;
                    let mut any = false;
                    while j < bytes.len() && bytes[j].is_ascii_digit() {
                        g = g * 10 + (bytes[j] - b'0') as usize;
                        any = true;
                        j += 1;
                    }
                    if any && j < bytes.len() && bytes[j] == b'}' {
                        if let Some(m) = caps.get(g) {
                            dst.push_str(m.as_str());
                        }
                        i = j + 1;
                        continue;
                    }
                }
                if nc == b'$' {
                    dst.push('$');
                    i += 2;
                    continue;
                }
            }
            dst.push(bytes[i] as char);
            i += 1;
        }
    }
}

impl Replacer for String {
    fn replace_into(&mut self, caps: &Captures<'_>, dst: &mut String) {
        let mut s = self.as_str();
        s.replace_into(caps, dst);
    }
}

impl<F: FnMut(&Captures<'_>) -> String> Replacer for F {
    fn replace_into(&mut self, caps: &Captures<'_>, dst: &mut String) {
        dst.push_str(&self(caps));
    }
}

// ---------- compile-time MAX_GROUPS sanity ----------
#[allow(dead_code)]
const _: () = {
    let _ = MAX_GROUPS;
};

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_match() {
        let r = Regex::new(r"^hello$").unwrap();
        assert!(r.is_match("hello"));
        assert!(!r.is_match("hello world"));
    }

    #[test]
    fn test_captures() {
        let r = Regex::new(r"(\w+)\s(\w+)").unwrap();
        let c = r.captures("foo bar").unwrap();
        assert_eq!(&c[0], "foo bar");
        assert_eq!(&c[1], "foo");
        assert_eq!(&c[2], "bar");
    }

    #[test]
    fn test_alternation() {
        let r = Regex::new(r"cat|dog").unwrap();
        assert!(r.is_match("cat"));
        assert!(r.is_match("dog"));
        assert!(!r.is_match("fish"));
    }

    #[test]
    fn test_quant() {
        let r = Regex::new(r"a{2,4}").unwrap();
        assert!(r.is_match("aa"));
        assert!(r.is_match("aaaa"));
        assert!(!r.is_match("a"));
    }

    #[test]
    fn test_replace_simple() {
        let r = Regex::new(r"\d+").unwrap();
        let out = r.replace_all("a1b22c333", "X");
        assert_eq!(out, "aXbXcX");
    }

    #[test]
    fn test_replace_backref() {
        let r = Regex::new(r"(\w+)").unwrap();
        let out = r.replace_all("hi", "<$1>");
        assert_eq!(out, "<hi>");
    }

    #[test]
    fn test_classes() {
        let r = Regex::new(r"^[a-z]+$").unwrap();
        assert!(r.is_match("hello"));
        assert!(!r.is_match("Hello"));
    }

    #[test]
    fn test_predef_class() {
        let r = Regex::new(r"^\d+$").unwrap();
        assert!(r.is_match("123"));
        assert!(!r.is_match("12a"));
    }

    #[test]
    fn test_word_boundary() {
        let r = Regex::new(r"\bcat\b").unwrap();
        assert!(r.is_match("the cat sat"));
        assert!(!r.is_match("category"));
    }

    #[test]
    fn test_meta_path_pattern() {
        // Pattern used by the struct port: ^([^$]+)\$([=~])(.+)$
        let r = Regex::new(r"^([^$]+)\$([=~])(.+)$").unwrap();
        let c = r.captures("name$=value").unwrap();
        assert_eq!(&c[1], "name");
        assert_eq!(&c[2], "=");
        assert_eq!(&c[3], "value");
    }

    #[test]
    fn test_injection_full_pattern() {
        let r = Regex::new(r"^`(\$[A-Z]+|[^`]*)[0-9]*`$").unwrap();
        let c = r.captures("`$NAME`").unwrap();
        assert_eq!(&c[1], "$NAME");
        let c = r.captures("`foo.bar`").unwrap();
        assert_eq!(&c[1], "foo.bar");
    }

    #[test]
    fn test_captures_iter() {
        let r = Regex::new(r"\d+").unwrap();
        let nums: Vec<String> = r
            .captures_iter("a1 b22 c333")
            .map(|c| c[0].to_string())
            .collect();
        assert_eq!(nums, vec!["1", "22", "333"]);
    }

    #[test]
    fn test_replace_callback() {
        let r = Regex::new(r"(\w+)").unwrap();
        let out = r.replace_all("foo bar", |c: &Captures<'_>| c[1].to_uppercase());
        assert_eq!(out, "FOO BAR");
    }
}
