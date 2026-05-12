// Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
// VERSION: @voxgig/struct 0.1.0
//
// Major utilities — walk, merge, getpath, setpath, and (staged) the
// inject / transform / validate / select machinery. See rs/PLAN.md §8-§11.
//
// `merge` is implemented walk-based to stay close to the canonical; the
// `cur`/`dst` scratch vectors are shared between the before/after closures
// via `Rc<RefCell<…>>` (Rust can't have two FnMut closures both holding a
// `&mut` to the same Vec).

use std::cell::RefCell;
use std::rc::Rc;

use crate::consts::*;
use crate::mini::*;
use crate::value::{js_string, Value};
use crate::StructError;

// ---------------------------------------------------------------------
// callback / function types
// ---------------------------------------------------------------------

/// `WalkApply` — `(key, val, parent, path) -> any`. `key` is `Noval` at the
/// root and a `Str` for every descendant (matches the canonical, where
/// `items` always yields string keys).
pub type WalkClosure<'a> = dyn FnMut(&Value, &Value, &Value, &[String]) -> Value + 'a;

/// `Injector` — `(inj, val, ref, store) -> any`.
pub type NativeFn = crate::value::NativeFn;

/// `Modify` — `(val, key, parent, inj, store)`.
pub type Modify = crate::value::ModifyFn;

pub type Inj = Rc<RefCell<Injection>>;
pub type SVec = Rc<RefCell<Vec<String>>>;

// ---------------------------------------------------------------------
// walk
// ---------------------------------------------------------------------

pub fn walk(
    val: Value,
    before: Option<&mut WalkClosure>,
    after: Option<&mut WalkClosure>,
    maxdepth: Option<i64>,
) -> Value {
    let mut path: Vec<String> = Vec::new();
    walk_impl(val, before, after, maxdepth, &Value::Noval, &Value::Noval, &mut path)
}

fn walk_impl(
    val: Value,
    mut before: Option<&mut WalkClosure>,
    mut after: Option<&mut WalkClosure>,
    maxdepth: Option<i64>,
    key: &Value,
    parent: &Value,
    path: &mut Vec<String>,
) -> Value {
    let depth = path.len() as i64;

    let out = match before {
        Some(ref mut f) => f(key, &val, parent, path),
        None => val,
    };

    let md = match maxdepth {
        Some(m) if m >= 0 => m,
        _ => MAXDEPTH,
    };
    if md == 0 || (md > 0 && md <= depth) {
        return out;
    }

    if is_node(&out) {
        let entries = items_vec(&out);
        for (ckey, child) in entries {
            path.push(ckey.clone());
            let res = walk_impl(
                child,
                before.as_mut().map(|f| &mut **f),
                after.as_mut().map(|f| &mut **f),
                maxdepth,
                &Value::str(ckey.clone()),
                &out,
                path,
            );
            path.pop();
            set_prop(out.clone(), &Value::str(ckey), res);
        }
    }

    match after {
        Some(ref mut f) => f(key, &out, parent, path),
        None => out,
    }
}

// ---------------------------------------------------------------------
// merge
// ---------------------------------------------------------------------

const T_INSTANCE_I: i64 = T_INSTANCE as i64;

pub fn merge(val: &Value, maxdepth: Option<i64>) -> Value {
    let md = match slice(
        Value::Num(maxdepth.unwrap_or(MAXDEPTH) as f64),
        Some(0),
        None,
        false,
    ) {
        Value::Num(n) => n as i64,
        _ => MAXDEPTH,
    };

    let list: Vec<Value> = match val {
        Value::List(l) => l.borrow().clone(),
        other => return other.clone(),
    };

    if list.is_empty() {
        return Value::Noval;
    }
    if list.len() == 1 {
        return list[0].clone();
    }

    let mut out = match &list[0] {
        Value::Noval => Value::empty_map(),
        other => other.clone(),
    };

    for obj in list.iter().skip(1) {
        let obj = obj.clone();
        if !is_node(&obj) {
            out = obj;
            continue;
        }

        let cur: Rc<RefCell<Vec<Value>>> = Rc::new(RefCell::new(vec![out.clone()]));
        let dst: Rc<RefCell<Vec<Value>>> = Rc::new(RefCell::new(vec![out.clone()]));

        let cur_b = cur.clone();
        let dst_b = dst.clone();
        let mut before = move |key: &Value, v: &Value, _parent: &Value, path: &[String]| -> Value {
            let pi = path.len() as i64;
            let mut ret = v.clone();

            if md <= pi {
                let target = cur_b
                    .borrow()
                    .get((pi - 1) as usize)
                    .cloned()
                    .unwrap_or(Value::Noval);
                set_prop(target, key, v.clone());
            } else if !is_node(v) {
                let mut cb = cur_b.borrow_mut();
                grow(&mut cb, pi as usize);
                cb[pi as usize] = v.clone();
            } else {
                let tval = {
                    let d = if pi > 0 {
                        let prev = dst_b
                            .borrow()
                            .get((pi - 1) as usize)
                            .cloned()
                            .unwrap_or(Value::Noval);
                        get_prop(&prev, key, Value::Noval)
                    } else {
                        dst_b.borrow().get(pi as usize).cloned().unwrap_or(Value::Noval)
                    };
                    let mut db = dst_b.borrow_mut();
                    grow(&mut db, pi as usize);
                    db[pi as usize] = d.clone();
                    d
                };
                let mut cb = cur_b.borrow_mut();
                grow(&mut cb, pi as usize);
                if tval.is_noval() && (typify(v) & T_INSTANCE_I) == 0 {
                    cb[pi as usize] = if is_list(v) {
                        Value::empty_list()
                    } else {
                        Value::empty_map()
                    };
                } else if typify(v) == typify(&tval) {
                    cb[pi as usize] = tval;
                } else {
                    cb[pi as usize] = v.clone();
                    ret = Value::Noval;
                }
            }
            ret
        };

        let cur_a = cur.clone();
        let mut after = move |key: &Value, _v: &Value, _parent: &Value, path: &[String]| -> Value {
            let ci = path.len() as i64;
            let (target, value) = {
                let cb = cur_a.borrow();
                (
                    cb.get((ci - 1) as usize).cloned().unwrap_or(Value::Noval),
                    cb.get(ci as usize).cloned().unwrap_or(Value::Noval),
                )
            };
            set_prop(target, key, value.clone());
            value
        };

        out = walk(obj, Some(&mut before), Some(&mut after), maxdepth);
    }

    if md == 0 {
        let last = get_elem(&Value::list(list.clone()), &Value::Num(-1.0), Value::Noval);
        out = match &last {
            Value::List(_) => Value::empty_list(),
            Value::Map(_) => Value::empty_map(),
            other => other.clone(),
        };
    }

    out
}

fn grow(v: &mut Vec<Value>, idx: usize) {
    while v.len() <= idx {
        v.push(Value::Noval);
    }
}

// ---------------------------------------------------------------------
// Injection state
// ---------------------------------------------------------------------

pub struct Injection {
    pub mode: i64,
    pub full: bool,
    pub key_i: i64,
    pub keys: SVec,
    pub key: String,
    pub val: Value,
    pub parent: Value,
    pub path: Vec<String>,
    pub nodes: Vec<Value>,
    pub handler: NativeFn,
    pub errs: Value, // Value::List
    pub meta: Value, // Value::Map
    pub dparent: Value,
    pub dpath: Vec<String>,
    pub base: Option<String>,
    pub modify: Option<Modify>,
    pub extra: Option<Value>,
    pub prior: Option<Inj>,
}

/// Public `injdef` argument — the subset of `Partial<Injection>` callers set.
#[derive(Default, Clone)]
pub struct InjectDef {
    pub base: Option<String>,
    pub errs: Option<Value>,
    pub meta: Option<Value>,
    pub modify: Option<Modify>,
    pub handler: Option<NativeFn>,
    pub extra: Option<Value>,
    pub dparent: Option<Value>,
    pub dpath: Option<Vec<String>>,
    pub key: Option<Value>,
}

impl Injection {
    /// Build a (mostly-empty) injection carrying just the fields the public
    /// `getpath` / `setpath` read from an `injdef`.
    pub fn from_def(def: Option<&InjectDef>) -> Inj {
        let inj = Injection {
            mode: M_VAL,
            full: false,
            key_i: 0,
            keys: Rc::new(RefCell::new(vec![S_DTOP.to_string()])),
            key: S_DTOP.to_string(),
            val: Value::Noval,
            parent: Value::Noval,
            path: vec![S_DTOP.to_string()],
            nodes: vec![Value::Noval],
            handler: inject_handler_fn(),
            errs: Value::empty_list(),
            meta: Value::empty_map(),
            dparent: Value::Noval,
            dpath: vec![S_DTOP.to_string()],
            base: None,
            modify: None,
            extra: None,
            prior: None,
        };
        let inj = Rc::new(RefCell::new(inj));
        if let Some(d) = def {
            let mut b = inj.borrow_mut();
            if let Some(x) = &d.base {
                b.base = Some(x.clone());
            }
            if let Some(x) = &d.errs {
                b.errs = x.clone();
            }
            if let Some(x) = &d.meta {
                b.meta = x.clone();
            }
            if let Some(x) = &d.modify {
                b.modify = Some(x.clone());
            }
            if let Some(x) = &d.handler {
                b.handler = x.clone();
            }
            if let Some(x) = &d.extra {
                b.extra = Some(x.clone());
            }
            if let Some(x) = &d.dparent {
                b.dparent = x.clone();
            }
            if let Some(x) = &d.dpath {
                b.dpath = x.clone();
            }
            if let Some(x) = &d.key {
                b.key = str_key(x.clone());
            }
        }
        inj
    }

    fn has_handler(def: Option<&InjectDef>) -> bool {
        def.map(|d| d.handler.is_some()).unwrap_or(false)
    }
}

// ---------------------------------------------------------------------
// getpath
// ---------------------------------------------------------------------

pub fn get_path(store: &Value, path: &Value, injdef: Option<&InjectDef>) -> Value {
    let inj: Option<Inj> = injdef.map(|_| Injection::from_def(injdef));
    get_path_inj(store, path, inj.as_ref())
}

/// Internal `getpath` working against a full `Inj` (used by the inject
/// machinery and by the public `get_path` wrapper).
pub fn get_path_inj(store: &Value, path: &Value, injdef: Option<&Inj>) -> Value {
    let mut parts: Vec<String> = match path {
        Value::List(l) => l
            .borrow()
            .iter()
            .map(|x| match x {
                Value::Str(s) => s.clone(),
                other => js_string(other),
            })
            .collect(),
        Value::Str(s) => s.split('.').map(|p| p.to_string()).collect(),
        Value::Num(n) => vec![str_key(Value::Num(*n))],
        _ => return Value::Noval,
    };

    let base = injdef.and_then(|i| i.borrow().base.clone());
    let src = match &base {
        Some(b) => get_prop(store, &Value::str(b.clone()), store.clone()),
        None => store.clone(),
    };
    let numparts = parts.len();
    let dparent = injdef.map(|i| i.borrow().dparent.clone()).unwrap_or(Value::Noval);

    let mut val = store.clone();

    let path_nullish = matches!(path, Value::Noval | Value::Null);
    if path_nullish
        || matches!(store, Value::Noval | Value::Null)
        || (numparts == 1 && parts[0].is_empty())
    {
        val = src.clone();
    } else if numparts > 0 {
        if numparts == 1 {
            val = get_prop(store, &Value::str(parts[0].clone()), Value::Noval);
        }

        if !is_func(&val) {
            val = src.clone();

            // meta path prefix:  "name$=..."  /  "name$~..."
            if let Some(inj) = injdef {
                let meta = inj.borrow().meta.clone();
                let first = parts[0].clone();
                if let Some(caps) = R_META_PATH.captures(&first) {
                    if !meta.is_noval() {
                        val = get_prop(&meta, &Value::str(caps[1].to_string()), Value::Noval);
                        parts[0] = caps[3].to_string();
                    }
                }
            }

            let dpath: Vec<String> = injdef.map(|i| i.borrow().dpath.clone()).unwrap_or_default();

            let mut p_i = 0usize;
            while !val.is_noval() && p_i < numparts {
                let mut part = parts[p_i].clone();

                if let Some(inj) = injdef {
                    if part == S_DKEY {
                        part = inj.borrow().key.clone();
                    } else if let Some(rest) = part.strip_prefix("$GET:") {
                        part = js_string(&get_path_inj(&src, &Value::str(drop_last(rest)), None));
                    } else if let Some(rest) = part.strip_prefix("$REF:") {
                        let spec = get_prop(store, &Value::str(S_DSPEC), Value::Noval);
                        part = js_string(&get_path_inj(&spec, &Value::str(drop_last(rest)), None));
                    } else if let Some(rest) = part.strip_prefix("$META:") {
                        let meta = inj.borrow().meta.clone();
                        part = js_string(&get_path_inj(&meta, &Value::str(drop_last(rest)), None));
                    }
                }

                part = part.replace("$$", "$");

                if part.is_empty() {
                    let mut ascends = 0i64;
                    while parts.get(1 + p_i).map(|s| s.is_empty()).unwrap_or(false) {
                        ascends += 1;
                        p_i += 1;
                    }

                    if injdef.is_some() && ascends > 0 {
                        if p_i == parts.len() - 1 {
                            ascends -= 1;
                        }
                        if ascends == 0 {
                            val = dparent.clone();
                        } else {
                            // fullpath = slice(dpath, -ascends) ++ parts[p_i+1..]
                            let head = slice(
                                Value::list(dpath.iter().cloned().map(Value::Str).collect()),
                                Some(-ascends),
                                None,
                                false,
                            );
                            let mut fullpath: Vec<String> = match &head {
                                Value::List(l) => l
                                    .borrow()
                                    .iter()
                                    .map(|x| x.as_str().map(|s| s.to_string()).unwrap_or_default())
                                    .collect(),
                                _ => Vec::new(),
                            };
                            fullpath.extend_from_slice(&parts[p_i + 1..]);
                            if ascends <= dpath.len() as i64 {
                                val = get_path_inj(
                                    store,
                                    &Value::list(
                                        fullpath.into_iter().map(Value::Str).collect(),
                                    ),
                                    None,
                                );
                            } else {
                                val = Value::Noval;
                            }
                            break;
                        }
                    } else {
                        val = dparent.clone();
                    }
                } else {
                    val = get_prop(&val, &Value::str(part), Value::Noval);
                }

                p_i += 1;
            }
        }
    }

    if let Some(inj) = injdef {
        let handler = inj.borrow().handler.clone();
        let r = pathify(path, None, None);
        val = handler(inj, &val, &r, store);
    }

    val
}

fn drop_last(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.is_empty() {
        String::new()
    } else {
        chars[..chars.len() - 1].iter().collect()
    }
}

// ---------------------------------------------------------------------
// setpath
// ---------------------------------------------------------------------

pub fn set_path(store: &Value, path: &Value, val: Value, injdef: Option<&InjectDef>) -> Value {
    // Keep parts as Values so a numeric part (only possible when `path` is an
    // array) makes its parent a list, while a string part makes a map.
    let parts: Vec<Value> = match path {
        Value::List(l) => l.borrow().clone(),
        Value::Str(s) => s.split('.').map(Value::str).collect(),
        Value::Num(n) => vec![Value::Num(*n)],
        _ => return Value::Noval,
    };
    if parts.is_empty() {
        return Value::Noval;
    }

    let base = injdef.and_then(|d| d.base.clone());
    let numparts = parts.len();
    let mut parent = match &base {
        Some(b) => get_prop(store, &Value::str(b.clone()), store.clone()),
        None => store.clone(),
    };

    for p_i in 0..numparts - 1 {
        let part_key = parts[p_i].clone();
        let next_parent = get_prop(&parent, &part_key, Value::Noval);
        let next_parent = if !is_node(&next_parent) {
            let next_is_num = parts
                .get(p_i + 1)
                .map(|p| typify(p) & (T_NUMBER as i64) != 0)
                .unwrap_or(false);
            let np = if next_is_num {
                Value::empty_list()
            } else {
                Value::empty_map()
            };
            set_prop(parent.clone(), &part_key, np.clone());
            np
        } else {
            next_parent
        };
        parent = next_parent;
    }

    let last = parts[numparts - 1].clone();
    if val.is_delete() {
        del_prop(parent.clone(), &last);
    } else {
        set_prop(parent.clone(), &last, val);
    }

    parent
}

// ---------------------------------------------------------------------
// inject / transform / validate / select — staged (see rs/PLAN.md, NOTES.md)
// ---------------------------------------------------------------------

/// Default inject handler — passes the value through unless it's a `$NAME`
/// command function (the full machinery is staged; see PLAN.md §8).
pub fn inject_handler_fn() -> NativeFn {
    Rc::new(|_inj: &Inj, val: &Value, _r: &str, _store: &Value| -> Value { val.clone() })
}

pub fn inject(_val: Value, _store: &Value, _injdef: Option<&InjectDef>) -> Value {
    unimplemented!("inject: not yet ported — see rs/PLAN.md §8 and rs/NOTES.md")
}

pub fn transform(
    _data: &Value,
    _spec: &Value,
    _injdef: Option<&InjectDef>,
) -> Result<Value, StructError> {
    unimplemented!("transform: not yet ported — see rs/PLAN.md §9 and rs/NOTES.md")
}

pub fn validate(
    _data: &Value,
    _spec: &Value,
    _injdef: Option<&InjectDef>,
) -> Result<Value, StructError> {
    unimplemented!("validate: not yet ported — see rs/PLAN.md §10 and rs/NOTES.md")
}

pub fn select(_children: &Value, _query: &Value) -> Value {
    unimplemented!("select: not yet ported — see rs/PLAN.md §11 and rs/NOTES.md")
}

pub fn check_placement(_modes: i64, _ijname: &str, _parent_types: i64, _inj: &Inj) -> bool {
    unimplemented!()
}

pub fn injector_args(_arg_types: &[i64], _args: &[Value]) -> Vec<Value> {
    unimplemented!()
}

pub fn inject_child(_child: Value, _store: &Value, _inj: &Inj) -> Inj {
    unimplemented!()
}

// keep `Injection::has_handler` referenced (used once staging is complete)
#[allow(dead_code)]
fn _keepalive() {
    let _ = Injection::has_handler(None);
}
