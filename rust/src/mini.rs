// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
// VERSION: @voxgig/struct 0.1.0
//
// Minor utilities — port of the predicate / accessor / string-and-JSON
// helpers from StructUtility.ts. Names are idiomatic snake_case; see the
// TS->Rust table in README.md.

use crate::ordered_map::OrderedMap;
use crate::re::{Captures, Regex, RegexError};

use crate::consts::*;
use crate::value::{is_integer_f64, js_string, js_to_number, num_to_string, Value};

const MIN_SAFE_INTEGER: i64 = -9007199254740991;
const MAX_SAFE_INTEGER: i64 = 9007199254740991;

// ---- type names / type codes ------------------------------------------

/// `typename(t)` — human name for a type bit-flag.
pub fn type_name(t: i64) -> String {
    let idx = (t as u32).leading_zeros() as usize;
    TYPENAME
        .get(idx)
        .map(|s| s.to_string())
        .unwrap_or_else(|| TYPENAME[0].to_string())
}

/// `typify(value)` — type bit-code for a value.
pub fn typify(value: &Value) -> i64 {
    match value {
        Value::Noval => T_NOVAL as i64,
        Value::Null => (T_SCALAR | T_NULL) as i64,
        Value::Num(n) => {
            if is_integer_f64(*n) {
                (T_SCALAR | T_NUMBER | T_INTEGER) as i64
            } else if n.is_nan() {
                T_NOVAL as i64
            } else {
                (T_SCALAR | T_NUMBER | T_DECIMAL) as i64
            }
        }
        Value::Str(_) => (T_SCALAR | T_STRING) as i64,
        Value::Bool(_) => (T_SCALAR | T_BOOLEAN) as i64,
        Value::Func(_) => (T_SCALAR | T_FUNCTION) as i64,
        Value::List(_) => (T_NODE | T_LIST) as i64,
        // Sentinels are `{ '`$SKIP`': true }` plain objects in TS.
        Value::Map(_) | Value::Sentinel(_) => (T_NODE | T_MAP) as i64,
    }
}

// ---- predicates -------------------------------------------------------

pub fn get_def(val: Value, alt: Value) -> Value {
    if val.is_noval() {
        alt
    } else {
        val
    }
}

pub fn is_node(val: &Value) -> bool {
    matches!(val, Value::List(_) | Value::Map(_))
}

pub fn is_map(val: &Value) -> bool {
    matches!(val, Value::Map(_))
}

pub fn is_list(val: &Value) -> bool {
    matches!(val, Value::List(_))
}

pub fn is_key(key: &Value) -> bool {
    match key {
        Value::Str(s) => !s.is_empty(),
        Value::Num(_) => true,
        _ => false,
    }
}

pub fn is_empty(val: &Value) -> bool {
    match val {
        Value::Noval | Value::Null => true,
        Value::Str(s) => s.is_empty(),
        Value::List(l) => l.borrow().is_empty(),
        Value::Map(m) => m.borrow().is_empty(),
        _ => false,
    }
}

pub fn is_func(val: &Value) -> bool {
    matches!(val, Value::Func(_))
}

/// `size(val)` — length for lists/strings, key count for maps, integer
/// part for numbers, 1/0 for booleans, 0 otherwise.
pub fn size(val: &Value) -> i64 {
    match val {
        Value::List(l) => l.borrow().len() as i64,
        Value::Map(m) => m.borrow().len() as i64,
        Value::Str(s) => s.encode_utf16().count() as i64,
        Value::Num(n) if n.is_finite() => n.floor() as i64,
        Value::Bool(b) => i64::from(*b),
        _ => 0,
    }
}

// ---- slice ------------------------------------------------------------

/// `slice(val, start?, end?, mutate?)` — sub-section of a list, string, or
/// bounded number. When `val` is a list and `mutate` is true, the list is
/// truncated/shifted in place (and the same list value is returned).
pub fn slice(val: Value, start: Option<i64>, end: Option<i64>, mutate: bool) -> Value {
    if let Value::Num(n) = val {
        let s = start.unwrap_or(MIN_SAFE_INTEGER);
        let e = end.unwrap_or(MAX_SAFE_INTEGER) - 1;
        let lo = n.max(s as f64);
        let r = lo.min(e as f64);
        return Value::Num(r);
    }

    let vlen = size(&val);

    let mut start = start;
    if end.is_some() && start.is_none() {
        start = Some(0);
    }

    if let Some(mut s) = start {
        let mut e: Option<i64>;
        if s < 0 {
            let mut ee = vlen + s;
            if ee < 0 {
                ee = 0;
            }
            e = Some(ee);
            s = 0;
        } else if let Some(mut ee) = end {
            if ee < 0 {
                ee += vlen;
                if ee < 0 {
                    ee = 0;
                }
            } else if vlen < ee {
                ee = vlen;
            }
            e = Some(ee);
        } else {
            e = Some(vlen);
        }

        if vlen < s {
            s = vlen;
        }

        let e = e.take().unwrap_or(vlen);

        if -1 < s && s <= e && e <= vlen {
            match &val {
                Value::List(l) => {
                    if mutate {
                        let mut lb = l.borrow_mut();
                        let sub: Vec<Value> = lb[s as usize..e as usize].to_vec();
                        *lb = sub;
                        drop(lb);
                        return val;
                    } else {
                        let lb = l.borrow();
                        return Value::list(lb[s as usize..e as usize].to_vec());
                    }
                }
                Value::Str(st) => {
                    // substring by UTF-16 units to match JS .substring
                    let units: Vec<u16> = st.encode_utf16().collect();
                    let sub: Vec<u16> = units[s as usize..e as usize].to_vec();
                    return Value::Str(String::from_utf16_lossy(&sub));
                }
                _ => {}
            }
        } else {
            match &val {
                Value::List(_) => return Value::empty_list(),
                Value::Str(_) => return Value::Str(String::new()),
                _ => {}
            }
        }
    }

    val
}

// ---- pad --------------------------------------------------------------

pub fn pad(s: Value, padding: Option<i64>, padchar: Option<String>) -> String {
    let mut s = match s {
        Value::Str(s) => s,
        other => stringify(&other, None, false),
    };
    let padding = padding.unwrap_or(44);
    let padchar = {
        let mut pc = padchar.unwrap_or_default();
        pc.push(' ');
        pc.chars().next().unwrap()
    };
    let cur = s.encode_utf16().count() as i64;
    if padding > -1 {
        if cur < padding {
            for _ in 0..(padding - cur) {
                s.push(padchar);
            }
        }
        s
    } else {
        let target = -padding;
        if cur < target {
            let mut out = String::new();
            for _ in 0..(target - cur) {
                out.push(padchar);
            }
            out.push_str(&s);
            out
        } else {
            s
        }
    }
}

// ---- node accessors ---------------------------------------------------

/// `getelem(list, key, alt?)` — list lookup by integer key, negative counts
/// from the end. If the element is absent and `alt` is a callable value, it
/// is invoked (with the uniform `(inj, val, ref, store)` shape — a fresh
/// throwaway injection, `Noval` value/store, empty ref) and its result used,
/// mirroring the canonical `alt()` call.
pub fn get_elem(val: &Value, key: &Value, alt: Value) -> Value {
    let out = get_elem_or_else(val, key, || Value::Noval);
    if !out.is_noval() {
        return out;
    }
    match &alt {
        Value::Func(f) => {
            let inj = crate::major::Injection::from_def(None);
            f(&inj, &Value::Noval, "", &Value::Noval)
        }
        _ => alt,
    }
}

pub fn get_elem_or_else<F: FnOnce() -> Value>(val: &Value, key: &Value, alt: F) -> Value {
    if val.is_noval() || key.is_noval() {
        return alt();
    }
    let out = if let Value::List(l) = val {
        let keystr = js_string(key);
        if R_INTEGER_KEY.is_match(&keystr) {
            match keystr.parse::<i64>() {
                Ok(mut n) => {
                    let lb = l.borrow();
                    if n < 0 {
                        n += lb.len() as i64;
                    }
                    if n >= 0 && (n as usize) < lb.len() {
                        lb[n as usize].clone()
                    } else {
                        Value::Noval
                    }
                }
                Err(_) => Value::Noval,
            }
        } else {
            Value::Noval
        }
    } else {
        Value::Noval
    };
    if out.is_noval() {
        alt()
    } else {
        out
    }
}

/// `getprop(node, key, alt?)` — safe property lookup on a map or list.
pub fn get_prop(val: &Value, key: &Value, alt: Value) -> Value {
    if val.is_noval() || key.is_noval() {
        return alt;
    }
    let out = match val {
        Value::List(l) => {
            let lb = l.borrow();
            // Array index: a non-negative integer (string or number).
            let ks = js_string(key);
            ks.parse::<usize>()
                .ok()
                .and_then(|i| lb.get(i).cloned())
                .unwrap_or(Value::Noval)
        }
        Value::Map(m) => m
            .borrow()
            .get(&js_string(key))
            .cloned()
            .unwrap_or(Value::Noval),
        Value::Sentinel(s) => {
            if js_string(key) == s.tag {
                Value::Bool(true)
            } else {
                Value::Noval
            }
        }
        _ => Value::Noval,
    };
    if out.is_noval() {
        alt
    } else {
        out
    }
}

/// `strkey(key)` — coerce a key to its canonical string form (`""` if invalid).
pub fn str_key(key: Value) -> String {
    let t = typify(&key);
    if t & (T_STRING as i64) != 0 {
        return key.as_str().unwrap_or("").to_string();
    }
    if t & (T_BOOLEAN as i64) != 0 {
        return String::new();
    }
    if t & (T_NUMBER as i64) != 0 {
        if let Value::Num(n) = key {
            return if n.fract() == 0.0 {
                num_to_string(n)
            } else {
                num_to_string(n.floor())
            };
        }
    }
    String::new()
}

/// `keysof(node)` — sorted keys of a map, or list indices as strings.
pub fn keysof_vec(val: &Value) -> Vec<String> {
    match val {
        Value::Map(m) => {
            let mut ks: Vec<String> = m.borrow().keys().cloned().collect();
            ks.sort();
            ks
        }
        Value::List(l) => (0..l.borrow().len()).map(|i| i.to_string()).collect(),
        _ => Vec::new(),
    }
}

pub fn keys_of(val: &Value) -> Value {
    Value::list(keysof_vec(val).into_iter().map(Value::Str).collect())
}

pub fn has_key(val: &Value, key: &Value) -> bool {
    !get_prop(val, key, Value::Noval).is_noval()
}

/// `items(node)` — `[key, value]` pairs (keys sorted, as strings).
pub fn items_vec(val: &Value) -> Vec<(String, Value)> {
    keysof_vec(val)
        .into_iter()
        .map(|k| {
            let v = get_prop(val, &Value::str(k.clone()), Value::Noval);
            (k, v)
        })
        .collect()
}

pub fn items(val: &Value) -> Value {
    Value::list(
        items_vec(val)
            .into_iter()
            .map(|(k, v)| Value::list(vec![Value::Str(k), v]))
            .collect(),
    )
}

// ---- flatten / filter -------------------------------------------------

pub fn flatten(list: &Value, depth: Option<i64>) -> Value {
    match list {
        Value::List(l) => {
            let d = depth.unwrap_or(1);
            Value::list(flat_slice(&l.borrow(), d))
        }
        other => other.clone(),
    }
}

fn flat_slice(v: &[Value], depth: i64) -> Vec<Value> {
    let mut out = Vec::new();
    for item in v {
        match item {
            Value::List(inner) if depth > 0 => out.extend(flat_slice(&inner.borrow(), depth - 1)),
            other => out.push(other.clone()),
        }
    }
    out
}

/// `flatten([a, b, [c]])` — internal helper taking a Vec directly. Default
/// depth 1 (matches `flatten(...)` calls with no depth arg).
#[allow(dead_code)]
pub fn flatten_vals(v: Vec<Value>, depth: i64) -> Vec<Value> {
    flat_slice(&v, depth)
}

pub fn filter_vals<F: Fn(&(String, Value)) -> bool>(val: &Value, check: F) -> Vec<Value> {
    let all = items_vec(val);
    let mut out = Vec::new();
    for item in &all {
        if check(item) {
            out.push(item.1.clone());
        }
    }
    out
}

pub fn filter<F: Fn(&(String, Value)) -> bool>(val: &Value, check: F) -> Value {
    Value::list(filter_vals(val, check))
}

// ---- escaping / replace ----------------------------------------------

/// `escre(s)` — escape regex metacharacters.
pub fn esc_re(s: &Value) -> String {
    let rs = coerce_for_replace(s);
    R_ESCAPE_REGEXP
        .replace_all(&rs, |caps: &Captures<'_>| format!("\\{}", &caps[0]))
        .into_owned()
}

// ---------------------------------------------------------------------------
// Regex utility — uniform re_* API (see /REGEX_API.md). Backed by the
// in-tree pure-Rust Thompson NFA engine (crate::re), no third-party crate.
// ---------------------------------------------------------------------------

/// Compile a pattern. Mirrors `re_compile(pattern)`.
pub fn re_compile(pattern: &str) -> Result<Regex, RegexError> {
    Regex::new(pattern)
}

/// First match. Returns `Some([whole, capture1, ...])` or `None`.
pub fn re_find(pattern: &str, input: &str) -> Option<Vec<String>> {
    let re = Regex::new(pattern).ok()?;
    let m = re.captures(input)?;
    Some(
        m.iter()
            .map(|c| c.map(|x| x.as_str().to_string()).unwrap_or_default())
            .collect(),
    )
}

/// All non-overlapping matches.
pub fn re_find_all(pattern: &str, input: &str) -> Vec<Vec<String>> {
    let re = match Regex::new(pattern) {
        Ok(r) => r,
        Err(_) => return Vec::new(),
    };
    re.captures_iter(input)
        .map(|caps| {
            caps.iter()
                .map(|c| c.map(|x| x.as_str().to_string()).unwrap_or_default())
                .collect()
        })
        .collect()
}

/// Replace every match. Supports `$&` (whole match) and `$1`..`$9` (captures).
pub fn re_replace(pattern: &str, input: &str, replacement: &str) -> String {
    let re = match Regex::new(pattern) {
        Ok(r) => r,
        Err(_) => return input.to_string(),
    };
    re.replace_all(input, replacement).into_owned()
}

/// Boolean test.
pub fn re_test(pattern: &str, input: &str) -> bool {
    Regex::new(pattern)
        .map(|re| re.is_match(input))
        .unwrap_or(false)
}

/// Alias of `esc_re`.
pub fn re_escape(s: &str) -> String {
    esc_re(&Value::from(s))
}

/// `escurl(s)` — `encodeURIComponent`.
pub fn esc_url(s: &Value) -> String {
    let s = match s {
        Value::Str(s) => s.clone(),
        Value::Noval | Value::Null => String::new(),
        other => js_string(other),
    };
    let mut out = String::new();
    for b in s.bytes() {
        let c = b as char;
        if c.is_ascii_alphanumeric() || "-_.!~*'()".contains(c) {
            out.push(c);
        } else {
            out.push_str(&format!("%{:02X}", b));
        }
    }
    out
}

/// The `replace`-helper's string coercion: undefined -> "", everything else
/// via `stringify` (which returns a string unchanged).
fn coerce_for_replace(s: &Value) -> String {
    match s {
        Value::Str(s) => s.clone(),
        Value::Noval => String::new(),
        other => stringify(other, None, false),
    }
}

/// `replace(s, regex, literal-with-$1-$2)` — JS-style replace-all (the `g`
/// behaviour). `$1`, `$2` etc. refer to capture groups; use `$$` for a
/// literal `$`. (`$&` is not used by any call site; would be `${0}` here.)
#[allow(dead_code)]
pub fn replace_str(s: &Value, from: &Regex, to: &str) -> String {
    let rs = coerce_for_replace(s);
    from.replace_all(&rs, to).to_string()
}

// ---- join -------------------------------------------------------------

pub fn join(arr: &Value, sep: Option<&str>, url: bool) -> String {
    let sepdef = sep.unwrap_or(S_CM).to_string();
    let sarr = size(arr);
    let sepre: Option<String> = if sepdef.encode_utf16().count() == 1 {
        Some(esc_re(&Value::str(sepdef.clone())))
    } else {
        None
    };

    // filter to string non-empty entries
    let str_entries: Vec<Value> =
        filter_vals(arr, |n| matches!(&n.1, Value::Str(s) if !s.is_empty()));

    let processed: Vec<String> = items_vec(&Value::list(str_entries))
        .into_iter()
        .map(|(idx_str, v)| {
            let i = idx_str.parse::<i64>().unwrap_or(0);
            let mut s = v.as_str().unwrap_or("").to_string();
            if let Some(sre) = &sepre {
                if !sre.is_empty() {
                    if url && i == 0 {
                        s = re_replace_first(&format!("{sre}+$"), &s, "");
                        return s;
                    }
                    if i > 0 {
                        s = re_replace_first(&format!("^{sre}+"), &s, "");
                    }
                    if i < sarr - 1 || !url {
                        s = re_replace_first(&format!("{sre}+$"), &s, "");
                    }
                    let pat = format!("([^{sre}]){sre}+([^{sre}])");
                    let repl = format!("${{1}}{sepdef}${{2}}");
                    s = re_replace_first(&pat, &s, &repl);
                }
            }
            s
        })
        .collect();

    processed
        .into_iter()
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(&sepdef)
}

/// `join` over an already-built `Vec<Value>`.
pub fn join_vals(arr: &[Value], sep: Option<&str>, url: bool) -> String {
    join(&Value::list(arr.to_vec()), sep, url)
}

fn re_replace_first(pat: &str, s: &str, repl: &str) -> String {
    match Regex::new(pat) {
        Ok(re) => re.replace(s, repl).to_string(),
        Err(_) => s.to_string(),
    }
}

// ---- jsonify / stringify ---------------------------------------------

pub struct JsonFlags {
    pub indent: usize,
    pub offset: usize,
}

impl Default for JsonFlags {
    fn default() -> Self {
        JsonFlags {
            indent: 2,
            offset: 0,
        }
    }
}

/// `jsonify(val, flags?)` — strict JSON serialisation, default 2-space indent.
pub fn jsonify(val: &Value, flags: Option<&JsonFlags>) -> String {
    let def = JsonFlags::default();
    let flags = flags.unwrap_or(&def);
    if val.is_nullish() {
        return S_null.to_string();
    }
    let mut s = match json_encode(val, flags.indent, 0) {
        Some(s) => s,
        None => return S_null.to_string(),
    };
    if flags.offset > 0 {
        // Left-offset every line but the first by `offset` spaces.
        let lines: Vec<&str> = s.split('\n').collect();
        let mut out = String::from("{\n");
        let mut parts: Vec<String> = Vec::new();
        for line in lines.iter().skip(1) {
            parts.push(pad(
                Value::str(*line),
                Some(0 - flags.offset as i64 - line.encode_utf16().count() as i64),
                None,
            ));
        }
        out.push_str(&parts.join("\n"));
        s = out;
    }
    s
}

fn json_encode(val: &Value, indent: usize, level: usize) -> Option<String> {
    match val {
        Value::Noval => None,
        Value::Func(_) => None,
        Value::Null => Some("null".to_string()),
        Value::Bool(b) => Some(b.to_string()),
        Value::Num(n) => {
            if n.is_finite() {
                Some(num_to_string(*n))
            } else {
                Some("null".to_string())
            }
        }
        Value::Str(s) => Some(json_quote(s)),
        Value::Sentinel(_) => {
            // a `{ '`$SKIP`': true }` map
            let mut m = OrderedMap::new();
            let tag = match val {
                Value::Sentinel(s) => s.tag.to_string(),
                _ => unreachable!(),
            };
            m.insert(tag, Value::Bool(true));
            json_encode(&Value::map(m), indent, level)
        }
        Value::List(l) => {
            let lb = l.borrow();
            if lb.is_empty() {
                return Some("[]".to_string());
            }
            let inner_pad = " ".repeat(indent * (level + 1));
            let outer_pad = " ".repeat(indent * level);
            let nl = if indent > 0 { "\n" } else { "" };
            let sep = if indent > 0 { ",\n" } else { "," };
            let items: Vec<String> = lb
                .iter()
                .map(|v| {
                    let enc =
                        json_encode(v, indent, level + 1).unwrap_or_else(|| "null".to_string());
                    if indent > 0 {
                        format!("{inner_pad}{enc}")
                    } else {
                        enc
                    }
                })
                .collect();
            Some(format!("[{nl}{}{nl}{outer_pad}]", items.join(sep)))
        }
        Value::Map(m) => {
            let mb = m.borrow();
            // drop undefined / function-valued keys
            let entries: Vec<(&String, &Value)> = mb
                .iter()
                .filter(|(_, v)| !matches!(v, Value::Noval | Value::Func(_)))
                .collect();
            if entries.is_empty() {
                return Some("{}".to_string());
            }
            let inner_pad = " ".repeat(indent * (level + 1));
            let outer_pad = " ".repeat(indent * level);
            let nl = if indent > 0 { "\n" } else { "" };
            let colon = if indent > 0 { ": " } else { ":" };
            let sep = if indent > 0 { ",\n" } else { "," };
            let items: Vec<String> = entries
                .iter()
                .map(|(k, v)| {
                    let enc =
                        json_encode(v, indent, level + 1).unwrap_or_else(|| "null".to_string());
                    if indent > 0 {
                        format!("{inner_pad}{}{colon}{enc}", json_quote(k))
                    } else {
                        format!("{}{colon}{enc}", json_quote(k))
                    }
                })
                .collect();
            Some(format!("{{{nl}{}{nl}{outer_pad}}}", items.join(sep)))
        }
    }
}

fn json_quote(s: &str) -> String {
    let mut out = String::from("\"");
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\u{0008}' => out.push_str("\\b"),
            '\u{000C}' => out.push_str("\\f"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// `stringify(val, maxlen?, pretty?)` — compact, human-friendly string form.
pub fn stringify(val: &Value, maxlen: Option<i64>, pretty: bool) -> String {
    let mut valstr;
    if val.is_noval() {
        return if pretty {
            "<>".to_string()
        } else {
            String::new()
        };
    }
    if let Value::Str(s) = val {
        valstr = s.clone();
    } else {
        match human_json(val) {
            Some(s) => {
                // remove all double-quotes (a deliberate quirk)
                valstr = s.replace('"', "");
            }
            None => return "__STRINGIFY_FAILED__".to_string(),
        }
    }

    if let Some(m) = maxlen {
        if m >= 0 {
            let m = m as usize;
            let chars: Vec<char> = valstr.chars().collect();
            if chars.len() > m {
                let keep = m.saturating_sub(3);
                let head: String = chars.iter().take(keep).collect();
                valstr = format!("{head}...");
            }
        }
    }

    if pretty {
        return ansi_colour(&valstr);
    }

    valstr
}

/// Compact JSON with object keys sorted (used by `stringify`). Functions and
/// `undefined` map values are dropped. Cycles are not detected -> caller maps
/// the failure to `__STRINGIFY_FAILED__` only if recursion overflows (which
/// would actually panic); we approximate with a depth guard.
fn human_json(val: &Value) -> Option<String> {
    human_json_depth(val, 0)
}

fn human_json_depth(val: &Value, depth: usize) -> Option<String> {
    if depth > 1_000 {
        return None;
    }
    match val {
        Value::Noval => None,
        Value::Func(_) => None,
        Value::Null => Some("null".to_string()),
        Value::Bool(b) => Some(b.to_string()),
        Value::Num(n) => Some(if n.is_finite() {
            num_to_string(*n)
        } else {
            "null".to_string()
        }),
        Value::Str(s) => Some(json_quote(s)),
        Value::Sentinel(s) => Some(format!("{{\"{}\":true}}", s.tag)),
        Value::List(l) => {
            let lb = l.borrow();
            let parts: Vec<String> = lb
                .iter()
                .map(|v| human_json_depth(v, depth + 1).unwrap_or_else(|| "null".to_string()))
                .collect();
            Some(format!("[{}]", parts.join(",")))
        }
        Value::Map(m) => {
            let mb = m.borrow();
            let mut keys: Vec<&String> = mb
                .iter()
                .filter(|(_, v)| !matches!(v, Value::Noval | Value::Func(_)))
                .map(|(k, _)| k)
                .collect();
            keys.sort();
            let parts: Vec<String> = keys
                .iter()
                .map(|k| {
                    let v = mb.get(*k).unwrap();
                    format!(
                        "{}:{}",
                        json_quote(k),
                        human_json_depth(v, depth + 1).unwrap_or_else(|| "null".to_string())
                    )
                })
                .collect();
            Some(format!("{{{}}}", parts.join(",")))
        }
    }
}

fn ansi_colour(valstr: &str) -> String {
    let colours = [
        81, 118, 213, 39, 208, 201, 45, 190, 129, 51, 160, 121, 226, 33, 207, 69,
    ];
    let c: Vec<String> = colours.iter().map(|n| format!("\x1b[38;5;{n}m")).collect();
    let r = "\x1b[0m";
    let mut d: i64 = 0;
    let mut o = c[0].clone();
    let mut t = o.clone();
    for ch in valstr.chars() {
        if ch == '{' || ch == '[' {
            d += 1;
            o = c[(d as usize) % c.len()].clone();
            t.push_str(&o);
            t.push(ch);
        } else if ch == '}' || ch == ']' {
            t.push_str(&o);
            t.push(ch);
            d -= 1;
            o = c[(d.rem_euclid(c.len() as i64)) as usize].clone();
        } else {
            t.push_str(&o);
            t.push(ch);
        }
    }
    t.push_str(r);
    t
}

// ---- pathify ----------------------------------------------------------

pub fn pathify(val: &Value, startin: Option<i64>, endin: Option<i64>) -> String {
    let path: Option<Vec<Value>> = match val {
        Value::List(l) => Some(l.borrow().clone()),
        Value::Str(_) | Value::Num(_) => Some(vec![val.clone()]),
        _ => None,
    };
    let start = match startin {
        None => 0,
        Some(s) if -1 < s => s,
        _ => 0,
    };
    let end = match endin {
        None => 0,
        Some(e) if -1 < e => e,
        _ => 0,
    };

    let mut pathstr: Option<String> = None;
    if let Some(path) = &path {
        if start >= 0 {
            let plen = path.len() as i64;
            let sliced = slice(
                Value::list(path.clone()),
                Some(start),
                Some(plen - end),
                false,
            );
            let sv: Vec<Value> = sliced
                .as_list()
                .map(|l| l.borrow().clone())
                .unwrap_or_default();
            if sv.is_empty() {
                pathstr = Some("<root>".to_string());
            } else {
                let filtered = filter_vals(&Value::list(sv), |n| is_key(&n.1));
                let mapped: Vec<Value> = filtered
                    .iter()
                    .map(|p| match p {
                        Value::Num(n) => Value::str(num_to_string(n.floor())),
                        _ => Value::str(p.as_str().unwrap_or("").replace('.', "")),
                    })
                    .collect();
                pathstr = Some(join_vals(&mapped, Some("."), false));
            }
        }
    }

    pathstr.unwrap_or_else(|| {
        let tail = if val.is_noval() {
            String::new()
        } else {
            format!("{}{}", S_CN, stringify(val, Some(47), false))
        };
        format!("<unknown-path{tail}>")
    })
}

// ---- clone ------------------------------------------------------------

/// `clone(val)` — deep copy. Functions and sentinels are copied (not cloned).
pub fn clone(val: &Value) -> Value {
    match val {
        Value::Noval => Value::Noval,
        Value::Null => Value::Null,
        Value::Bool(b) => Value::Bool(*b),
        Value::Num(n) => Value::Num(*n),
        Value::Str(s) => Value::Str(s.clone()),
        Value::List(l) => Value::list(l.borrow().iter().map(clone).collect()),
        Value::Map(m) => {
            let mut nm = OrderedMap::new();
            for (k, v) in m.borrow().iter() {
                nm.insert(k.clone(), clone(v));
            }
            Value::map(nm)
        }
        Value::Func(f) => Value::Func(f.clone()),
        Value::Sentinel(s) => Value::Sentinel(s),
    }
}

// ---- delprop / setprop -----------------------------------------------

pub fn del_prop(parent: Value, key: &Value) -> Value {
    if !is_key(key) {
        return parent;
    }
    match &parent {
        Value::Map(m) => {
            let k = str_key(key.clone());
            m.borrow_mut().shift_remove(&k);
        }
        Value::List(l) => {
            let ki = js_to_number(key);
            if ki.is_nan() {
                return parent;
            }
            let ki = ki.floor() as i64;
            let mut lb = l.borrow_mut();
            if ki >= 0 && (ki as usize) < lb.len() {
                lb.remove(ki as usize);
            }
        }
        _ => {}
    }
    parent
}

pub fn set_prop(parent: Value, key: &Value, val: Value) -> Value {
    if !is_key(key) {
        return parent;
    }
    match &parent {
        Value::Map(m) => {
            let k = js_string(key);
            m.borrow_mut().insert(k, val);
        }
        Value::List(l) => {
            let ki = js_to_number(key);
            if ki.is_nan() {
                return parent;
            }
            let ki = ki.floor() as i64;
            let mut lb = l.borrow_mut();
            if ki >= 0 {
                let len = lb.len() as i64;
                let idx = ki.min(len).max(0) as usize;
                if idx < lb.len() {
                    lb[idx] = val;
                } else {
                    lb.push(val);
                }
            } else {
                lb.insert(0, val);
            }
        }
        _ => {}
    }
    parent
}

// ---- builders ---------------------------------------------------------

pub fn jm(kv: &[Value]) -> Value {
    let mut o = OrderedMap::new();
    let n = kv.len();
    let mut i = 0;
    while i < n {
        let k = match kv.get(i) {
            Some(Value::Str(s)) => s.clone(),
            Some(other) => stringify(other, None, false),
            None => format!("$KEY{i}"),
        };
        let v = kv.get(i + 1).cloned().unwrap_or(Value::Null);
        o.insert(k, v);
        i += 2;
    }
    Value::map(o)
}

pub fn jt(v: &[Value]) -> Value {
    Value::list(
        v.iter()
            .map(|x| if x.is_noval() { Value::Null } else { x.clone() })
            .collect(),
    )
}
