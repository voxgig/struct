// Test Provider (prototype) — Rust port of the CANONICAL implementation
// (../ts/provider.ts).
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// DEPENDENCY-FREE: this crate has NO third-party dependencies. JSON is handled
// by the hand-written `json` module below (a `Json` value enum + recursive
// descent parser). The object variant is a `Vec<(String, Json)>` that preserves
// key insertion order, so `functions()`/`groups()` return the corpus order
// (minor first) rather than sorted keys. Regex matching is provided by the tiny
// dependency-free `mini_regex` module.

use std::fs;
use std::path::PathBuf;

pub use json::Json;

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
    // Holds `in` OR `args` OR `ctx` as a Json, per `kind`.
    pub value: Json,
}

#[derive(Debug, Clone)]
pub struct Expect {
    pub kind: ExpectKind,
    pub value: Option<Json>,
    pub error: Option<ErrorCheck>,
    pub r#match: Option<Json>,
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
    pub raw: Json,
}

#[derive(Debug, Clone)]
pub struct MatchResult {
    pub ok: bool,
    pub path: Vec<String>,
    pub expected: Option<Json>,
    pub actual: Option<Json>,
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
    spec: Json,
}

impl TestProvider {
    pub fn load(testfile: Option<&str>) -> TestProvider {
        let path: PathBuf = match testfile {
            Some(f) => PathBuf::from(f),
            None => default_test_file(),
        };
        let txt = fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("read {:?}: {e}", path));
        let spec: Json = json::parse(&txt).expect("parse test.json");
        TestProvider { spec }
    }

    pub fn raw(&self) -> &Json {
        &self.spec
    }

    // Root node: prefer spec.struct, else the spec itself.
    fn root(&self) -> &Json {
        match self.spec.get("struct") {
            Some(s) => s,
            None => &self.spec,
        }
    }

    fn fn_node(&self, func: &str) -> &Json {
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
fn is_group_bag(v: &Json) -> bool {
    v.as_object()
        .map(|o| object_get(o, "set").map(|s| s.is_array()).unwrap_or(false))
        .unwrap_or(false)
}

// A function node has at least one child group bag (other than `name`).
fn has_groups(v: &Json) -> bool {
    match v.as_object() {
        Some(o) => o.iter().any(|(k, val)| k.as_str() != "name" && is_group_bag(val)),
        None => false,
    }
}

fn has(raw: &Json, key: &str) -> bool {
    raw.as_object()
        .map(|o| object_get(o, key).is_some())
        .unwrap_or(false)
}

fn normalize(func: &str, group: &str, index: usize, raw: &Json) -> Entry {
    let id = raw
        .get("id")
        .filter(|v| !v.is_null())
        .map(value_to_string_key);
    let doc = raw.get("doc") == Some(&Json::Bool(true));
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
fn value_to_string_key(v: &Json) -> String {
    match v {
        Json::Str(s) => s.clone(),
        _ => v.to_string(),
    }
}

fn resolve_input(raw: &Json) -> Input {
    if has(raw, "ctx") {
        return Input {
            kind: InputKind::Ctx,
            value: raw.get("ctx").cloned().unwrap_or(Json::Null),
        };
    }
    if has(raw, "args") {
        return Input {
            kind: InputKind::Args,
            value: raw.get("args").cloned().unwrap_or(Json::Null),
        };
    }
    Input {
        kind: InputKind::In,
        value: if has(raw, "in") {
            raw.get("in").cloned().unwrap_or(Json::Null)
        } else {
            Json::Null
        },
    }
}

fn parse_err(err: &Json) -> ErrorCheck {
    if err == &Json::Bool(true) {
        return ErrorCheck { any: true, text: None, regex: false };
    }
    if let Json::Str(s) = err {
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

fn resolve_expect(raw: &Json) -> Expect {
    let match_part: Option<Json> = if has(raw, "match") {
        Some(raw.get("match").cloned().unwrap_or(Json::Null))
    } else {
        None
    };
    if has(raw, "err") {
        return Expect {
            kind: ExpectKind::Error,
            value: None,
            error: Some(parse_err(raw.get("err").unwrap_or(&Json::Null))),
            r#match: match_part,
        };
    }
    if has(raw, "out") {
        return Expect {
            kind: ExpectKind::Value,
            value: Some(raw.get("out").cloned().unwrap_or(Json::Null)),
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
fn stringify(x: &Json) -> String {
    match x {
        Json::Str(s) => s.clone(),
        _ => x.to_string(),
    }
}

// Normalize "__NULL__" and Null -> Null deeply (both sides), mirroring the
// runner's `flags.null` round-trip used by `equal`.
fn norm_null(x: &Json) -> Json {
    match x {
        Json::Str(s) if s == NULLMARK => Json::Null,
        Json::Null => Json::Null,
        Json::Arr(a) => Json::Arr(a.iter().map(norm_null).collect()),
        Json::Obj(o) => {
            Json::Obj(o.iter().map(|(k, v)| (k.clone(), norm_null(v))).collect())
        }
        other => other.clone(),
    }
}

// Normalize only "__NULL__" -> Null deeply, used by `equal_strict`.
fn norm_mark(x: &Json) -> Json {
    match x {
        Json::Str(s) if s == NULLMARK => Json::Null,
        Json::Arr(a) => Json::Arr(a.iter().map(norm_mark).collect()),
        Json::Obj(o) => {
            Json::Obj(o.iter().map(|(k, v)| (k.clone(), norm_mark(v))).collect())
        }
        other => other.clone(),
    }
}

pub fn matchval(check: &Json, base: &Json) -> bool {
    if check == base {
        return true;
    }
    if let Json::Str(c) = check {
        let basestr = stringify(base);
        if c.len() >= 2 && c.starts_with('/') && c.ends_with('/') {
            let inner = &c[1..c.len() - 1];
            if !inner.is_empty() {
                return mini_regex::is_match(inner, &basestr);
            }
        }
        return basestr.to_lowercase().contains(&c.to_lowercase());
    }
    // (A "function" check is not representable as a JSON value.)
    false
}

pub fn equal(expected: &Json, actual: &Json) -> bool {
    deep_eq(&norm_null(expected), &norm_null(actual))
}

pub fn equal_strict(expected: &Json, actual: &Json) -> bool {
    deep_eq(&norm_mark(expected), &norm_mark(actual))
}

fn deep_eq(a: &Json, b: &Json) -> bool {
    match (a, b) {
        (Json::Arr(av), Json::Arr(bv)) => {
            av.len() == bv.len() && av.iter().zip(bv.iter()).all(|(x, y)| deep_eq(x, y))
        }
        (Json::Obj(ao), Json::Obj(bo)) => {
            ao.len() == bo.len()
                && ao.iter().all(|(k, v)| {
                    object_get(bo, k).map(|bv| deep_eq(v, bv)).unwrap_or(false)
                })
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
pub fn struct_match(check: &Json, base: &Json) -> MatchResult {
    let mut result = MatchResult {
        ok: true,
        path: Vec::new(),
        expected: None,
        actual: None,
    };
    let mut leaves: Vec<(Json, Vec<String>)> = Vec::new();
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
        if val == Json::Str(UNDEFMARK.to_string()) && is_absent(&baseval) {
            continue;
        }
        // __EXISTS__ requires present (non-null)
        if val == Json::Str(EXISTSMARK.to_string()) && is_present(&baseval) {
            continue;
        }
        let bv_ref = baseval.clone().unwrap_or(Json::Null);
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
fn is_absent(v: &Option<Json>) -> bool {
    match v {
        None => true,
        Some(Json::Null) => true,
        _ => false,
    }
}

// "present" means a non-null value was found.
fn is_present(v: &Option<Json>) -> bool {
    matches!(v, Some(val) if !val.is_null())
}

fn is_node(v: &Json) -> bool {
    matches!(v, Json::Arr(_) | Json::Obj(_))
}

fn walk_leaves(node: &Json, path: &mut Vec<String>, out: &mut Vec<(Json, Vec<String>)>) {
    match node {
        Json::Arr(a) => {
            for (i, v) in a.iter().enumerate() {
                path.push(i.to_string());
                walk_leaves(v, path, out);
                path.pop();
            }
        }
        Json::Obj(o) => {
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
fn getpath(store: &Json, path: &[String]) -> Option<Json> {
    let mut cur = store;
    for key in path {
        match cur {
            Json::Null => return None,
            Json::Arr(a) => {
                let idx: usize = match key.parse() {
                    Ok(i) => i,
                    Err(_) => return None,
                };
                match a.get(idx) {
                    Some(v) => cur = v,
                    None => return None,
                }
            }
            Json::Obj(o) => match object_get(o, key) {
                Some(v) => cur = v,
                None => return None,
            },
            _ => return None,
        }
    }
    Some(cur.clone())
}

// Linear lookup over an insertion-ordered object (Vec of pairs).
fn object_get<'a>(obj: &'a [(String, Json)], key: &str) -> Option<&'a Json> {
    obj.iter().find(|(k, _)| k == key).map(|(_, v)| v)
}

// ─── minimal dependency-free JSON value + parser ───────────────────────────
//
// A small JSON value type and recursive-descent parser, sufficient for the
// shared corpus. The object variant is a `Vec<(String, Json)>` so key insertion
// order is preserved (matching serde_json's `preserve_order`), which is what
// makes `functions()`/`groups()` return corpus order.
mod json {
    use std::fmt;
    use std::fmt::Write as _;

    #[derive(Debug, Clone)]
    pub enum Json {
        Null,
        Bool(bool),
        Num(f64),
        Str(String),
        Arr(Vec<Json>),
        Obj(Vec<(String, Json)>),
    }

    impl Json {
        pub fn is_null(&self) -> bool {
            matches!(self, Json::Null)
        }

        pub fn is_array(&self) -> bool {
            matches!(self, Json::Arr(_))
        }

        pub fn as_array(&self) -> Option<&Vec<Json>> {
            match self {
                Json::Arr(a) => Some(a),
                _ => None,
            }
        }

        pub fn as_object(&self) -> Option<&Vec<(String, Json)>> {
            match self {
                Json::Obj(o) => Some(o),
                _ => None,
            }
        }

        // Object field lookup; None for non-objects or missing keys.
        pub fn get(&self, key: &str) -> Option<&Json> {
            match self {
                Json::Obj(o) => o.iter().find(|(k, _)| k == key).map(|(_, v)| v),
                _ => None,
            }
        }
    }

    // Structural equality mirroring serde_json::Value's PartialEq: objects
    // compare as key sets (order-independent), arrays element-wise, numbers by
    // value. This matches how the helpers compared serde_json values before.
    impl PartialEq for Json {
        fn eq(&self, other: &Json) -> bool {
            match (self, other) {
                (Json::Null, Json::Null) => true,
                (Json::Bool(a), Json::Bool(b)) => a == b,
                (Json::Num(a), Json::Num(b)) => a == b,
                (Json::Str(a), Json::Str(b)) => a == b,
                (Json::Arr(a), Json::Arr(b)) => {
                    a.len() == b.len() && a.iter().zip(b.iter()).all(|(x, y)| x == y)
                }
                (Json::Obj(a), Json::Obj(b)) => {
                    a.len() == b.len()
                        && a.iter().all(|(k, v)| {
                            b.iter().find(|(bk, _)| bk == k).map(|(_, bv)| v == bv).unwrap_or(false)
                        })
                }
                _ => false,
            }
        }
    }

    // Compact JSON serialization, matching serde_json's compact output for the
    // value shapes in the corpus (no spaces; integers without a decimal point;
    // shortest round-trip floats via Rust's f64 Display).
    impl fmt::Display for Json {
        fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
            match self {
                Json::Null => f.write_str("null"),
                Json::Bool(true) => f.write_str("true"),
                Json::Bool(false) => f.write_str("false"),
                Json::Num(n) => write_num(*n, f),
                Json::Str(s) => write_json_string(s, f),
                Json::Arr(a) => {
                    f.write_str("[")?;
                    for (i, v) in a.iter().enumerate() {
                        if i > 0 {
                            f.write_str(",")?;
                        }
                        v.fmt(f)?;
                    }
                    f.write_str("]")
                }
                Json::Obj(o) => {
                    f.write_str("{")?;
                    for (i, (k, v)) in o.iter().enumerate() {
                        if i > 0 {
                            f.write_str(",")?;
                        }
                        write_json_string(k, f)?;
                        f.write_str(":")?;
                        v.fmt(f)?;
                    }
                    f.write_str("}")
                }
            }
        }
    }

    fn write_num(n: f64, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        if !n.is_finite() {
            // serde_json serializes non-finite numbers as null.
            return f.write_str("null");
        }
        if n.fract() == 0.0 && n.abs() < 1e16 {
            // Integer-valued: print without a decimal point (e.g. "42", "-3").
            write!(f, "{}", n as i64)
        } else {
            // Shortest round-trip float (Rust's Display matches serde/ryu here).
            write!(f, "{}", n)
        }
    }

    fn write_json_string(s: &str, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("\"")?;
        for c in s.chars() {
            match c {
                '"' => f.write_str("\\\"")?,
                '\\' => f.write_str("\\\\")?,
                '\n' => f.write_str("\\n")?,
                '\r' => f.write_str("\\r")?,
                '\t' => f.write_str("\\t")?,
                '\u{08}' => f.write_str("\\b")?,
                '\u{0C}' => f.write_str("\\f")?,
                c if (c as u32) < 0x20 => write!(f, "\\u{:04x}", c as u32)?,
                c => f.write_char(c)?,
            }
        }
        f.write_str("\"")
    }

    pub fn parse(input: &str) -> Result<Json, String> {
        let mut p = Parser {
            chars: input.chars().collect(),
            pos: 0,
        };
        p.skip_ws();
        let v = p.parse_value()?;
        p.skip_ws();
        if p.pos != p.chars.len() {
            return Err(format!("trailing characters at {}", p.pos));
        }
        Ok(v)
    }

    struct Parser {
        chars: Vec<char>,
        pos: usize,
    }

    impl Parser {
        fn peek(&self) -> Option<char> {
            self.chars.get(self.pos).copied()
        }

        fn bump(&mut self) -> Option<char> {
            let c = self.chars.get(self.pos).copied();
            if c.is_some() {
                self.pos += 1;
            }
            c
        }

        fn skip_ws(&mut self) {
            while let Some(c) = self.peek() {
                if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
                    self.pos += 1;
                } else {
                    break;
                }
            }
        }

        fn parse_value(&mut self) -> Result<Json, String> {
            self.skip_ws();
            match self.peek() {
                Some('{') => self.parse_object(),
                Some('[') => self.parse_array(),
                Some('"') => Ok(Json::Str(self.parse_string()?)),
                Some('t') | Some('f') => self.parse_bool(),
                Some('n') => self.parse_null(),
                Some(c) if c == '-' || c.is_ascii_digit() => self.parse_number(),
                Some(c) => Err(format!("unexpected character '{}' at {}", c, self.pos)),
                None => Err("unexpected end of input".to_string()),
            }
        }

        fn expect(&mut self, c: char) -> Result<(), String> {
            match self.bump() {
                Some(got) if got == c => Ok(()),
                Some(got) => Err(format!("expected '{}' but found '{}' at {}", c, got, self.pos)),
                None => Err(format!("expected '{}' but reached end of input", c)),
            }
        }

        fn parse_object(&mut self) -> Result<Json, String> {
            self.expect('{')?;
            let mut obj: Vec<(String, Json)> = Vec::new();
            self.skip_ws();
            if self.peek() == Some('}') {
                self.pos += 1;
                return Ok(Json::Obj(obj));
            }
            loop {
                self.skip_ws();
                if self.peek() != Some('"') {
                    return Err(format!("expected string key at {}", self.pos));
                }
                let key = self.parse_string()?;
                self.skip_ws();
                self.expect(':')?;
                let val = self.parse_value()?;
                obj.push((key, val));
                self.skip_ws();
                match self.bump() {
                    Some(',') => continue,
                    Some('}') => break,
                    Some(c) => {
                        return Err(format!("expected ',' or '}}' but found '{}' at {}", c, self.pos))
                    }
                    None => return Err("unterminated object".to_string()),
                }
            }
            Ok(Json::Obj(obj))
        }

        fn parse_array(&mut self) -> Result<Json, String> {
            self.expect('[')?;
            let mut arr: Vec<Json> = Vec::new();
            self.skip_ws();
            if self.peek() == Some(']') {
                self.pos += 1;
                return Ok(Json::Arr(arr));
            }
            loop {
                let val = self.parse_value()?;
                arr.push(val);
                self.skip_ws();
                match self.bump() {
                    Some(',') => continue,
                    Some(']') => break,
                    Some(c) => {
                        return Err(format!("expected ',' or ']' but found '{}' at {}", c, self.pos))
                    }
                    None => return Err("unterminated array".to_string()),
                }
            }
            Ok(Json::Arr(arr))
        }

        fn parse_bool(&mut self) -> Result<Json, String> {
            if self.matches_keyword("true") {
                Ok(Json::Bool(true))
            } else if self.matches_keyword("false") {
                Ok(Json::Bool(false))
            } else {
                Err(format!("invalid literal at {}", self.pos))
            }
        }

        fn parse_null(&mut self) -> Result<Json, String> {
            if self.matches_keyword("null") {
                Ok(Json::Null)
            } else {
                Err(format!("invalid literal at {}", self.pos))
            }
        }

        fn matches_keyword(&mut self, kw: &str) -> bool {
            let end = self.pos + kw.len();
            if end <= self.chars.len() && self.chars[self.pos..end].iter().collect::<String>() == kw
            {
                self.pos = end;
                true
            } else {
                false
            }
        }

        fn parse_number(&mut self) -> Result<Json, String> {
            let start = self.pos;
            if self.peek() == Some('-') {
                self.pos += 1;
            }
            while let Some(c) = self.peek() {
                if c.is_ascii_digit() {
                    self.pos += 1;
                } else {
                    break;
                }
            }
            if self.peek() == Some('.') {
                self.pos += 1;
                while let Some(c) = self.peek() {
                    if c.is_ascii_digit() {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
            }
            if matches!(self.peek(), Some('e') | Some('E')) {
                self.pos += 1;
                if matches!(self.peek(), Some('+') | Some('-')) {
                    self.pos += 1;
                }
                while let Some(c) = self.peek() {
                    if c.is_ascii_digit() {
                        self.pos += 1;
                    } else {
                        break;
                    }
                }
            }
            let text: String = self.chars[start..self.pos].iter().collect();
            text.parse::<f64>()
                .map(Json::Num)
                .map_err(|_| format!("invalid number '{}' at {}", text, start))
        }

        fn parse_string(&mut self) -> Result<String, String> {
            self.expect('"')?;
            let mut out = String::new();
            loop {
                match self.bump() {
                    None => return Err("unterminated string".to_string()),
                    Some('"') => break,
                    Some('\\') => {
                        let esc = self.bump().ok_or("unterminated escape")?;
                        match esc {
                            '"' => out.push('"'),
                            '\\' => out.push('\\'),
                            '/' => out.push('/'),
                            'b' => out.push('\u{08}'),
                            'f' => out.push('\u{0C}'),
                            'n' => out.push('\n'),
                            'r' => out.push('\r'),
                            't' => out.push('\t'),
                            'u' => {
                                let cp = self.parse_hex4()?;
                                if (0xD800..=0xDBFF).contains(&cp) {
                                    // High surrogate: expect a following low surrogate.
                                    if self.bump() != Some('\\') || self.bump() != Some('u') {
                                        return Err("expected low surrogate".to_string());
                                    }
                                    let low = self.parse_hex4()?;
                                    if !(0xDC00..=0xDFFF).contains(&low) {
                                        return Err("invalid low surrogate".to_string());
                                    }
                                    let combined = 0x10000
                                        + ((cp - 0xD800) << 10)
                                        + (low - 0xDC00);
                                    match char::from_u32(combined) {
                                        Some(c) => out.push(c),
                                        None => return Err("invalid surrogate pair".to_string()),
                                    }
                                } else if (0xDC00..=0xDFFF).contains(&cp) {
                                    return Err("unexpected low surrogate".to_string());
                                } else {
                                    match char::from_u32(cp) {
                                        Some(c) => out.push(c),
                                        None => return Err("invalid code point".to_string()),
                                    }
                                }
                            }
                            other => {
                                return Err(format!("invalid escape '\\{}'", other));
                            }
                        }
                    }
                    Some(c) => out.push(c),
                }
            }
            Ok(out)
        }

        fn parse_hex4(&mut self) -> Result<u32, String> {
            let mut v: u32 = 0;
            for _ in 0..4 {
                let c = self.bump().ok_or("unterminated \\u escape")?;
                let d = c
                    .to_digit(16)
                    .ok_or_else(|| format!("invalid hex digit '{}'", c))?;
                v = v * 16 + d;
            }
            Ok(v)
        }
    }
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
