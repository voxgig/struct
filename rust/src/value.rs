// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
// VERSION: @voxgig/struct 0.1.0
//
// The in-memory JSON-shaped value type for the Rust port. See rs/PLAN.md.
//
// - `Noval` is the TS `undefined` — property absent. NOT a scalar.
// - `Null` is JSON null — a real value, distinct from `Noval`.
// - Lists and maps are `Rc<RefCell<...>>`: reference-stable, mutated in place.
// - `OrderedMap` preserves insertion order (the inject machinery needs it);
//   defined inline in `ordered_map.rs` — no third-party dependency.
// - `Func` carries callables that live inside the data (transform commands, etc.).
// - `Sentinel` (SKIP / DELETE) is compared by pointer identity.

use std::cell::RefCell;
use std::fmt;
use std::rc::Rc;

use crate::major::Inj;
use crate::ordered_map::OrderedMap;

pub type VList = Rc<RefCell<Vec<Value>>>;
pub type VMap = Rc<RefCell<OrderedMap<Value>>>;

/// Injector-shaped native function: `(inj, val, ref, store) -> any`.
/// Thunks (e.g. `$WHEN`) just ignore the arguments. Takes the injection by
/// `&Inj` (the `Rc<RefCell<…>>`) so injectors can re-borrow it as needed.
pub type NativeFn = Rc<dyn Fn(&Inj, &Value, &str, &Value) -> Value>;

/// `Modify` hook: mutates `parent[key]` (or `inj`), returns nothing.
pub type ModifyFn = Rc<dyn Fn(&Value, &Value, &Value, &Inj, &Value)>;

/// Identity-only marker for SKIP / DELETE.
pub struct Sentinel {
    pub tag: &'static str,
}

pub static SKIP: Sentinel = Sentinel { tag: "`$SKIP`" };
pub static DELETE: Sentinel = Sentinel { tag: "`$DELETE`" };

#[derive(Clone)]
pub enum Value {
    Noval,
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    List(VList),
    Map(VMap),
    Func(NativeFn),
    Sentinel(&'static Sentinel),
}

impl Value {
    // ---- constructors --------------------------------------------------

    pub fn list(items: Vec<Value>) -> Value {
        Value::List(Rc::new(RefCell::new(items)))
    }

    pub fn empty_list() -> Value {
        Value::list(Vec::new())
    }

    pub fn map(entries: OrderedMap<Value>) -> Value {
        Value::Map(Rc::new(RefCell::new(entries)))
    }

    pub fn empty_map() -> Value {
        Value::map(OrderedMap::new())
    }

    pub fn map_of<I: IntoIterator<Item = (String, Value)>>(pairs: I) -> Value {
        let mut m = OrderedMap::new();
        for (k, v) in pairs {
            m.insert(k, v);
        }
        Value::map(m)
    }

    pub fn func<F>(f: F) -> Value
    where
        F: Fn(&Inj, &Value, &str, &Value) -> Value + 'static,
    {
        Value::Func(Rc::new(f))
    }

    pub fn str<S: Into<String>>(s: S) -> Value {
        Value::Str(s.into())
    }

    pub fn skip() -> Value {
        Value::Sentinel(&SKIP)
    }

    pub fn delete() -> Value {
        Value::Sentinel(&DELETE)
    }

    // ---- predicates / accessors ---------------------------------------

    pub fn is_noval(&self) -> bool {
        matches!(self, Value::Noval)
    }

    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    /// JS `null == val` — true for both `undefined` and JSON `null`.
    pub fn is_nullish(&self) -> bool {
        matches!(self, Value::Noval | Value::Null)
    }

    pub fn is_skip(&self) -> bool {
        matches!(self, Value::Sentinel(s) if std::ptr::eq(*s, &SKIP))
    }

    pub fn is_delete(&self) -> bool {
        matches!(self, Value::Sentinel(s) if std::ptr::eq(*s, &DELETE))
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s.as_str()),
            _ => None,
        }
    }

    pub fn as_bool(&self) -> Option<bool> {
        match self {
            Value::Bool(b) => Some(*b),
            _ => None,
        }
    }

    pub fn as_num(&self) -> Option<f64> {
        match self {
            Value::Num(n) => Some(*n),
            _ => None,
        }
    }

    pub fn as_list(&self) -> Option<&VList> {
        match self {
            Value::List(l) => Some(l),
            _ => None,
        }
    }

    pub fn as_map(&self) -> Option<&VMap> {
        match self {
            Value::Map(m) => Some(m),
            _ => None,
        }
    }

    pub fn as_func(&self) -> Option<&NativeFn> {
        match self {
            Value::Func(f) => Some(f),
            _ => None,
        }
    }

    /// Truthy in the JS sense (used rarely; mostly for predicate returns).
    pub fn truthy(&self) -> bool {
        match self {
            Value::Noval | Value::Null => false,
            Value::Bool(b) => *b,
            Value::Num(n) => *n != 0.0 && !n.is_nan(),
            Value::Str(s) => !s.is_empty(),
            _ => true,
        }
    }
}

// Deep, order-independent (for maps) equality — matches `deepStrictEqual`
// semantics used by the corpus runner and the JSON-string fallback used by
// `validate_EXACT`. Functions are never equal (pointer-eq would also do).
impl PartialEq for Value {
    fn eq(&self, other: &Value) -> bool {
        match (self, other) {
            (Value::Noval, Value::Noval) => true,
            (Value::Null, Value::Null) => true,
            (Value::Bool(a), Value::Bool(b)) => a == b,
            (Value::Num(a), Value::Num(b)) => a == b,
            (Value::Str(a), Value::Str(b)) => a == b,
            (Value::Sentinel(a), Value::Sentinel(b)) => std::ptr::eq(*a, *b),
            (Value::List(a), Value::List(b)) => {
                if Rc::ptr_eq(a, b) {
                    return true;
                }
                let a = a.borrow();
                let b = b.borrow();
                a.len() == b.len() && a.iter().zip(b.iter()).all(|(x, y)| x == y)
            }
            (Value::Map(a), Value::Map(b)) => {
                if Rc::ptr_eq(a, b) {
                    return true;
                }
                let a = a.borrow();
                let b = b.borrow();
                a.len() == b.len()
                    && a.iter()
                        .all(|(k, v)| b.get(k).map(|w| v == w).unwrap_or(false))
            }
            _ => false,
        }
    }
}

impl fmt::Debug for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Noval => write!(f, "Noval"),
            Value::Null => write!(f, "Null"),
            Value::Bool(b) => write!(f, "Bool({b})"),
            Value::Num(n) => write!(f, "Num({n})"),
            Value::Str(s) => write!(f, "Str({s:?})"),
            Value::List(l) => write!(f, "List({:?})", l.borrow()),
            Value::Map(m) => write!(f, "Map({:?})", m.borrow()),
            Value::Func(_) => write!(f, "Func(..)"),
            Value::Sentinel(s) => write!(f, "Sentinel({})", s.tag),
        }
    }
}

// Convenient `From` impls for building values in tests / the runner.
impl From<bool> for Value {
    fn from(b: bool) -> Value {
        Value::Bool(b)
    }
}
impl From<i64> for Value {
    fn from(n: i64) -> Value {
        Value::Num(n as f64)
    }
}
impl From<i32> for Value {
    fn from(n: i32) -> Value {
        Value::Num(n as f64)
    }
}
impl From<usize> for Value {
    fn from(n: usize) -> Value {
        Value::Num(n as f64)
    }
}
impl From<f64> for Value {
    fn from(n: f64) -> Value {
        Value::Num(n)
    }
}
impl From<&str> for Value {
    fn from(s: &str) -> Value {
        Value::Str(s.to_string())
    }
}
impl From<String> for Value {
    fn from(s: String) -> Value {
        Value::Str(s)
    }
}
impl<T: Into<Value>> From<Vec<T>> for Value {
    fn from(v: Vec<T>) -> Value {
        Value::list(v.into_iter().map(Into::into).collect())
    }
}

// ---- JS numeric / string coercions ------------------------------------
//
// The canonical leans on JS coercions with no Rust stdlib equivalent.
// Implemented faithfully for the cases the corpus exercises.

/// `Number.isInteger(v)` — note `Number.isInteger(2.0) === true`.
pub fn is_integer_f64(v: f64) -> bool {
    v.is_finite() && v.fract() == 0.0
}

/// `String(v)` / `"" + v` for the value kinds that get stringified as keys.
pub fn js_string(v: &Value) -> String {
    match v {
        Value::Noval => "undefined".to_string(),
        Value::Null => "null".to_string(),
        Value::Bool(b) => b.to_string(),
        Value::Num(n) => num_to_string(*n),
        Value::Str(s) => s.clone(),
        // JS `String([1,2])` => "1,2"; `String({})` => "[object Object]".
        Value::List(l) => l
            .borrow()
            .iter()
            .map(|x| match x {
                Value::Noval | Value::Null => String::new(),
                _ => js_string(x),
            })
            .collect::<Vec<_>>()
            .join(","),
        Value::Map(_) => "[object Object]".to_string(),
        Value::Func(_) => "function".to_string(),
        Value::Sentinel(s) => s.tag.to_string(),
    }
}

/// JS number -> string. Differs from JS only for very large / very small
/// magnitudes where JS switches to exponent notation (documented gap).
pub fn num_to_string(n: f64) -> String {
    if n.is_nan() {
        return "NaN".to_string();
    }
    if n.is_infinite() {
        return if n > 0.0 { "Infinity" } else { "-Infinity" }.to_string();
    }
    if n == 0.0 {
        return "0".to_string();
    }
    if n.fract() == 0.0 && n.abs() < 1e21 {
        // Integer-valued: no decimal point, no exponent.
        return format!("{}", n as i128);
    }
    let s = format!("{n}");
    s
}

/// JS unary `+x` / `Number(x)` (ToNumber). Returns NaN on failure.
pub fn js_to_number(v: &Value) -> f64 {
    match v {
        Value::Noval => f64::NAN,
        Value::Null => 0.0,
        Value::Bool(b) => {
            if *b {
                1.0
            } else {
                0.0
            }
        }
        Value::Num(n) => *n,
        Value::Str(s) => js_string_to_number(s),
        Value::List(l) => {
            let b = l.borrow();
            match b.len() {
                0 => 0.0,
                1 => js_to_number(&b[0]),
                _ => f64::NAN,
            }
        }
        _ => f64::NAN,
    }
}

/// `Number("...")` for a string: trims, accepts decimal/hex/empty.
pub fn js_string_to_number(s: &str) -> f64 {
    let t = s.trim();
    if t.is_empty() {
        return 0.0;
    }
    if let Some(hex) = t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")) {
        return i64::from_str_radix(hex, 16)
            .map(|n| n as f64)
            .unwrap_or(f64::NAN);
    }
    t.parse::<f64>().unwrap_or(f64::NAN)
}

/// JS `n | 0` (ToInt32): truncate toward zero, wrap mod 2^32, signed.
pub fn js_to_int32(n: f64) -> i32 {
    if !n.is_finite() {
        return 0;
    }
    let trunc = n.trunc();
    // wrap into u32 then reinterpret as i32
    let m = trunc.rem_euclid(4294967296.0);
    m as u32 as i32
}
