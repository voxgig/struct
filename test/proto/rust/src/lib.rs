// Test Provider (prototype) — Rust port of the CANONICAL implementation
// (../ts/provider.ts).
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// The library uses serde_json::Value as the JSON value type throughout. A JSON
// crate is permitted for the TEST harness (mirrors rust/Cargo.toml's dev-dep);
// `preserve_order` keeps object key insertion order so `functions()` returns
// the corpus order.

use std::fs;
use std::path::PathBuf;

use serde_json::{Map, Value};

const NULLMARK: &str = "__NULL__";
const UNDEFMARK: &str = "__UNDEF__";
const EXISTSMARK: &str = "__EXISTS__";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputKind {
    In,
    Args,
    Ctx,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExpectKind {
    Value,
    Error,
    Match,
    Absent,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ErrorCheck {
    pub any: bool,
    pub text: Option<String>,
    pub regex: bool,
}

#[derive(Debug, Clone)]
pub struct Input {
    pub kind: InputKind,
    // Holds `in` OR `args` OR `ctx` as a Value, per `kind`.
    pub value: Value,
}

#[derive(Debug, Clone)]
pub struct Expect {
    pub kind: ExpectKind,
    pub value: Option<Value>,
    pub error: Option<ErrorCheck>,
    pub r#match: Option<Value>,
}

#[derive(Debug, Clone)]
pub struct Entry {
    pub function: String,
    pub group: String,
    pub index: usize,
    pub id: Option<String>,
    pub doc: bool,
    pub client: Option<String>,
    pub input: Input,
    pub expect: Expect,
    pub raw: Value,
}

#[derive(Debug, Clone)]
pub struct MatchResult {
    pub ok: bool,
    pub path: Vec<String>,
    pub expected: Option<Value>,
    pub actual: Option<Value>,
}

// Default corpus path: build/test/test.json relative to the repo root.
// From test/proto/rust, the repo root is three levels up.
fn default_test_file() -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("..");
    p.push("..");
    p.push("..");
    p.push("build");
    p.push("test");
    p.push("test.json");
    p
}

pub struct TestProvider {
    spec: Value,
}

impl TestProvider {
    pub fn load(testfile: Option<&str>) -> TestProvider {
        let path: PathBuf = match testfile {
            Some(f) => PathBuf::from(f),
            None => default_test_file(),
        };
        let txt = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {:?}: {e}", path));
        let spec: Value = serde_json::from_str(&txt).expect("parse test.json");
        TestProvider { spec }
    }

    pub fn raw(&self) -> &Value {
        &self.spec
    }

    // Root node: prefer spec.struct, else the spec itself.
    fn root(&self) -> &Value {
        match self.spec.get("struct") {
            Some(s) => s,
            None => &self.spec,
        }
    }

    fn fn_node(&self, func: &str) -> &Value {
        let node = self
            .spec
            .get("struct")
            .and_then(|s| s.get(func))
            .or_else(|| self.spec.get(func));
        match node {
            Some(n) => n,
            None => panic!("Unknown function: {func}"),
        }
    }

    pub fn functions(&self) -> Vec<String> {
        let root = self.root();
        match root.as_object() {
            Some(obj) => obj
                .iter()
                .filter(|(_, v)| is_group_bag(v) || has_groups(v))
                .map(|(k, _)| k.clone())
                .collect(),
            None => Vec::new(),
        }
    }

    pub fn groups(&self, func: &str) -> Vec<String> {
        let node = self.fn_node(func);
        match node.as_object() {
            Some(obj) => obj
                .iter()
                .filter(|(k, v)| k.as_str() != "name" && is_group_bag(v))
                .map(|(k, _)| k.clone())
                .collect(),
            None => Vec::new(),
        }
    }

    pub fn entries(&self, func: &str, group: Option<&str>) -> Vec<Entry> {
        let node = self.fn_node(func);
        let groups: Vec<String> = match group {
            Some(g) => vec![g.to_string()],
            None => self.groups(func),
        };
        let mut out: Vec<Entry> = Vec::new();
        for g in &groups {
            let bag = match node.get(g) {
                Some(b) => b,
                None => continue,
            };
            if !is_group_bag(bag) {
                continue;
            }
            if let Some(set) = bag.get("set").and_then(|s| s.as_array()) {
                for (i, item) in set.iter().enumerate() {
                    out.push(normalize(func, g, i, item));
                }
            }
        }
        out
    }
}

// A group bag is a map with a `set` array.
fn is_group_bag(v: &Value) -> bool {
    v.as_object()
        .map(|o| o.get("set").map(|s| s.is_array()).unwrap_or(false))
        .unwrap_or(false)
}

// A function node has at least one child group bag (other than `name`).
fn has_groups(v: &Value) -> bool {
    match v.as_object() {
        Some(o) => o.iter().any(|(k, val)| k.as_str() != "name" && is_group_bag(val)),
        None => false,
    }
}

fn has(raw: &Value, key: &str) -> bool {
    raw.as_object().map(|o| o.contains_key(key)).unwrap_or(false)
}

fn normalize(func: &str, group: &str, index: usize, raw: &Value) -> Entry {
    let id = raw
        .get("id")
        .filter(|v| !v.is_null())
        .map(value_to_string_key);
    let doc = raw.get("doc") == Some(&Value::Bool(true));
    let client = raw
        .get("client")
        .filter(|v| !v.is_null())
        .map(value_to_string_key);
    Entry {
        function: func.to_string(),
        group: group.to_string(),
        index,
        id,
        doc,
        client,
        input: resolve_input(raw),
        expect: resolve_expect(raw),
        raw: raw.clone(),
    }
}

// String(x): the string itself if already a string, else its JSON text.
fn value_to_string_key(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        _ => v.to_string(),
    }
}

fn resolve_input(raw: &Value) -> Input {
    if has(raw, "ctx") {
        return Input {
            kind: InputKind::Ctx,
            value: raw.get("ctx").cloned().unwrap_or(Value::Null),
        };
    }
    if has(raw, "args") {
        return Input {
            kind: InputKind::Args,
            value: raw.get("args").cloned().unwrap_or(Value::Null),
        };
    }
    Input {
        kind: InputKind::In,
        value: if has(raw, "in") {
            raw.get("in").cloned().unwrap_or(Value::Null)
        } else {
            Value::Null
        },
    }
}

fn parse_err(err: &Value) -> ErrorCheck {
    if err == &Value::Bool(true) {
        return ErrorCheck { any: true, text: None, regex: false };
    }
    if let Value::String(s) = err {
        if s.len() >= 2 && s.starts_with('/') && s.ends_with('/') {
            let inner = &s[1..s.len() - 1];
            if !inner.is_empty() {
                return ErrorCheck {
                    any: false,
                    text: Some(inner.to_string()),
                    regex: true,
                };
            }
        }
        return ErrorCheck {
            any: false,
            text: Some(s.clone()),
            regex: false,
        };
    }
    // Non-true, non-string err spec: treat as "any error".
    ErrorCheck { any: true, text: None, regex: false }
}

fn resolve_expect(raw: &Value) -> Expect {
    let match_part: Option<Value> = if has(raw, "match") {
        Some(raw.get("match").cloned().unwrap_or(Value::Null))
    } else {
        None
    };
    if has(raw, "err") {
        return Expect {
            kind: ExpectKind::Error,
            value: None,
            error: Some(parse_err(raw.get("err").unwrap_or(&Value::Null))),
            r#match: match_part,
        };
    }
    if has(raw, "out") {
        return Expect {
            kind: ExpectKind::Value,
            value: Some(raw.get("out").cloned().unwrap_or(Value::Null)),
            error: None,
            r#match: match_part,
        };
    }
    if has(raw, "match") {
        return Expect {
            kind: ExpectKind::Match,
            value: None,
            error: None,
            r#match: match_part,
        };
    }
    Expect {
        kind: ExpectKind::Absent,
        value: None,
        error: None,
        r#match: None,
    }
}

// ─── pure comparison helpers ───────────────────────────────────────────────

// stringify(x) = x if it is already a string, else compact JSON.
fn stringify(x: &Value) -> String {
    match x {
        Value::String(s) => s.clone(),
        _ => x.to_string(),
    }
}

// Normalize "__NULL__" and Null -> Null deeply (both sides), mirroring the
// runner's `flags.null` round-trip used by `equal`.
fn norm_null(x: &Value) -> Value {
    match x {
        Value::String(s) if s == NULLMARK => Value::Null,
        Value::Null => Value::Null,
        Value::Array(a) => Value::Array(a.iter().map(norm_null).collect()),
        Value::Object(o) => {
            let mut m = Map::new();
            for (k, v) in o.iter() {
                m.insert(k.clone(), norm_null(v));
            }
            Value::Object(m)
        }
        other => other.clone(),
    }
}

// Normalize only "__NULL__" -> Null deeply, used by `equal_strict`.
fn norm_mark(x: &Value) -> Value {
    match x {
        Value::String(s) if s == NULLMARK => Value::Null,
        Value::Array(a) => Value::Array(a.iter().map(norm_mark).collect()),
        Value::Object(o) => {
            let mut m = Map::new();
            for (k, v) in o.iter() {
                m.insert(k.clone(), norm_mark(v));
            }
            Value::Object(m)
        }
        other => other.clone(),
    }
}

pub fn matchval(check: &Value, base: &Value) -> bool {
    if check == base {
        return true;
    }
    if let Value::String(c) = check {
        let basestr = stringify(base);
        if c.len() >= 2 && c.starts_with('/') && c.ends_with('/') {
            let inner = &c[1..c.len() - 1];
            if !inner.is_empty() {
                return mini_regex::is_match(inner, &basestr);
            }
        }
        return basestr.to_lowercase().contains(&c.to_lowercase());
    }
    // (A "function" check is not representable as a JSON Value.)
    false
}

pub fn equal(expected: &Value, actual: &Value) -> bool {
    deep_eq(&norm_null(expected), &norm_null(actual))
}

pub fn equal_strict(expected: &Value, actual: &Value) -> bool {
    deep_eq(&norm_mark(expected), &norm_mark(actual))
}

fn deep_eq(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Array(av), Value::Array(bv)) => {
            av.len() == bv.len() && av.iter().zip(bv.iter()).all(|(x, y)| deep_eq(x, y))
        }
        (Value::Object(ao), Value::Object(bo)) => {
            ao.len() == bo.len()
                && ao
                    .iter()
                    .all(|(k, v)| bo.get(k).map(|bv| deep_eq(v, bv)).unwrap_or(false))
        }
        _ => a == b,
    }
}

pub fn error_matches(check: &ErrorCheck, message: &str) -> bool {
    if check.any {
        return true;
    }
    let text = match &check.text {
        Some(t) => t,
        None => return false,
    };
    if check.regex {
        return mini_regex::is_match(text, message);
    }
    message.to_lowercase().contains(&text.to_lowercase())
}

// Partial structural match: every leaf of `check` must match `base` at its path.
pub fn struct_match(check: &Value, base: &Value) -> MatchResult {
    let mut result = MatchResult {
        ok: true,
        path: Vec::new(),
        expected: None,
        actual: None,
    };
    let mut leaves: Vec<(Value, Vec<String>)> = Vec::new();
    walk_leaves(check, &mut Vec::new(), &mut leaves);
    for (val, path) in leaves {
        if !result.ok {
            break;
        }
        let baseval = getpath(base, &path);
        // baseval == val
        if let Some(bv) = &baseval {
            if bv == &val {
                continue;
            }
        }
        // __UNDEF__ requires absent (missing / None)
        if val == Value::String(UNDEFMARK.to_string()) && is_absent(&baseval) {
            continue;
        }
        // __EXISTS__ requires present (non-null)
        if val == Value::String(EXISTSMARK.to_string()) && is_present(&baseval) {
            continue;
        }
        let bv_ref = baseval.clone().unwrap_or(Value::Null);
        if !matchval(&val, &bv_ref) {
            result = MatchResult {
                ok: false,
                path,
                expected: Some(val),
                actual: baseval,
            };
        }
    }
    result
}

// "absent" means the path resolved to nothing (None) or to a JSON null.
fn is_absent(v: &Option<Value>) -> bool {
    match v {
        None => true,
        Some(Value::Null) => true,
        _ => false,
    }
}

// "present" means a non-null value was found.
fn is_present(v: &Option<Value>) -> bool {
    matches!(v, Some(val) if !val.is_null())
}

fn is_node(v: &Value) -> bool {
    matches!(v, Value::Array(_) | Value::Object(_))
}

fn walk_leaves(node: &Value, path: &mut Vec<String>, out: &mut Vec<(Value, Vec<String>)>) {
    match node {
        Value::Array(a) => {
            for (i, v) in a.iter().enumerate() {
                path.push(i.to_string());
                walk_leaves(v, path, out);
                path.pop();
            }
        }
        Value::Object(o) => {
            for (k, v) in o.iter() {
                path.push(k.clone());
                walk_leaves(v, path, out);
                path.pop();
            }
        }
        _ => {
            out.push((node.clone(), path.clone()));
        }
    }
    // (is_node guards: scalars fall through to the leaf branch.)
    let _ = is_node;
}

// getpath returns None when the path runs off the end of the structure
// (mirrors `undefined` in the TS reference).
fn getpath(store: &Value, path: &[String]) -> Option<Value> {
    let mut cur = store;
    for key in path {
        match cur {
            Value::Null => return None,
            Value::Array(a) => {
                let idx: usize = match key.parse() {
                    Ok(i) => i,
                    Err(_) => return None,
                };
                match a.get(idx) {
                    Some(v) => cur = v,
                    None => return None,
                }
            }
            Value::Object(o) => match o.get(key) {
                Some(v) => cur = v,
                None => return None,
            },
            _ => return None,
        }
    }
    Some(cur.clone())
}

// ─── tiny dependency-free regex matcher ────────────────────────────────────
//
// PROTOTYPE: regex simplified. The workspace `rust/` crate ships its own regex
// engine; to keep this prototype self-contained with no extra dependency, this
// is a small backtracking matcher supporting a practical subset: literals, `.`,
// `*`, `+`, `?`, `^`, `$`, character classes `[...]` (with ranges and `^`
// negation) and the escapes `\d \w \s \D \W \S` plus escaped metacharacters.
// `is_match` is unanchored (searches for the pattern anywhere) unless `^`/`$`
// anchor it. This is sufficient for the corpus's err/match regexes.
mod mini_regex {
    #[derive(Clone)]
    enum Atom {
        Any,
        Lit(char),
        Class { negate: bool, items: Vec<ClassItem> },
    }

    #[derive(Clone)]
    enum ClassItem {
        Ch(char),
        Range(char, char),
        Digit,
        NotDigit,
        Word,
        NotWord,
        Space,
        NotSpace,
    }

    struct Token {
        atom: Atom,
        // quantifier: (min, max) where max == usize::MAX means unbounded
        min: usize,
        max: usize,
    }

    fn class_item_matches(item: &ClassItem, c: char) -> bool {
        match item {
            ClassItem::Ch(x) => *x == c,
            ClassItem::Range(a, b) => *a <= c && c <= *b,
            ClassItem::Digit => c.is_ascii_digit(),
            ClassItem::NotDigit => !c.is_ascii_digit(),
            ClassItem::Word => c.is_alphanumeric() || c == '_',
            ClassItem::NotWord => !(c.is_alphanumeric() || c == '_'),
            ClassItem::Space => c.is_whitespace(),
            ClassItem::NotSpace => !c.is_whitespace(),
        }
    }

    fn atom_matches(atom: &Atom, c: char) -> bool {
        match atom {
            Atom::Any => c != '\n',
            Atom::Lit(x) => *x == c,
            Atom::Class { negate, items } => {
                let any = items.iter().any(|it| class_item_matches(it, c));
                if *negate {
                    !any
                } else {
                    any
                }
            }
        }
    }

    fn escape_to_item(c: char) -> Option<ClassItem> {
        match c {
            'd' => Some(ClassItem::Digit),
            'D' => Some(ClassItem::NotDigit),
            'w' => Some(ClassItem::Word),
            'W' => Some(ClassItem::NotWord),
            's' => Some(ClassItem::Space),
            'S' => Some(ClassItem::NotSpace),
            _ => None,
        }
    }

    fn parse(pattern: &str) -> (Vec<Token>, bool, bool) {
        let chars: Vec<char> = pattern.chars().collect();
        let mut i = 0;
        let mut anchored_start = false;
        let mut anchored_end = false;
        if i < chars.len() && chars[i] == '^' {
            anchored_start = true;
            i += 1;
        }
        let mut tokens: Vec<Token> = Vec::new();
        while i < chars.len() {
            let c = chars[i];
            if c == '$' && i == chars.len() - 1 {
                anchored_end = true;
                break;
            }
            let atom = match c {
                '.' => {
                    i += 1;
                    Atom::Any
                }
                '\\' => {
                    i += 1;
                    if i >= chars.len() {
                        Atom::Lit('\\')
                    } else {
                        let e = chars[i];
                        i += 1;
                        if let Some(item) = escape_to_item(e) {
                            Atom::Class { negate: false, items: vec![item] }
                        } else {
                            Atom::Lit(e)
                        }
                    }
                }
                '[' => {
                    i += 1;
                    let mut negate = false;
                    if i < chars.len() && chars[i] == '^' {
                        negate = true;
                        i += 1;
                    }
                    let mut items: Vec<ClassItem> = Vec::new();
                    while i < chars.len() && chars[i] != ']' {
                        if chars[i] == '\\' && i + 1 < chars.len() {
                            let e = chars[i + 1];
                            i += 2;
                            if let Some(item) = escape_to_item(e) {
                                items.push(item);
                            } else {
                                items.push(ClassItem::Ch(e));
                            }
                            continue;
                        }
                        // range a-b
                        if i + 2 < chars.len() && chars[i + 1] == '-' && chars[i + 2] != ']' {
                            items.push(ClassItem::Range(chars[i], chars[i + 2]));
                            i += 3;
                            continue;
                        }
                        items.push(ClassItem::Ch(chars[i]));
                        i += 1;
                    }
                    if i < chars.len() {
                        i += 1; // consume ']'
                    }
                    Atom::Class { negate, items }
                }
                _ => {
                    i += 1;
                    Atom::Lit(c)
                }
            };
            // quantifier
            let (min, max) = if i < chars.len() {
                match chars[i] {
                    '*' => {
                        i += 1;
                        (0, usize::MAX)
                    }
                    '+' => {
                        i += 1;
                        (1, usize::MAX)
                    }
                    '?' => {
                        i += 1;
                        (0, 1)
                    }
                    _ => (1, 1),
                }
            } else {
                (1, 1)
            };
            tokens.push(Token { atom, min, max });
        }
        (tokens, anchored_start, anchored_end)
    }

    // Try to match tokens[ti..] against text[pos..]; returns true if a full
    // token match completes (respecting anchored_end).
    fn try_match(
        tokens: &[Token],
        ti: usize,
        text: &[char],
        pos: usize,
        anchored_end: bool,
    ) -> bool {
        if ti == tokens.len() {
            return !anchored_end || pos == text.len();
        }
        let tok = &tokens[ti];
        // Greedy: consume as many as possible (up to max), then backtrack.
        let mut count = 0usize;
        let mut positions: Vec<usize> = vec![pos];
        let mut p = pos;
        while count < tok.max && p < text.len() && atom_matches(&tok.atom, text[p]) {
            p += 1;
            count += 1;
            positions.push(p);
        }
        // positions[k] = end position after matching k repetitions.
        let mut k = count;
        loop {
            if k >= tok.min {
                if try_match(tokens, ti + 1, text, positions[k], anchored_end) {
                    return true;
                }
            }
            if k == 0 {
                break;
            }
            k -= 1;
        }
        false
    }

    pub fn is_match(pattern: &str, text: &str) -> bool {
        let (tokens, anchored_start, anchored_end) = parse(pattern);
        let chars: Vec<char> = text.chars().collect();
        if anchored_start {
            return try_match(&tokens, 0, &chars, 0, anchored_end);
        }
        // Unanchored: try every starting position.
        for start in 0..=chars.len() {
            if try_match(&tokens, 0, &chars, start, anchored_end) {
                return true;
            }
        }
        false
    }
}
