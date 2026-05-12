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

    /// Fresh root injection: `val` wrapped in the virtual parent holder.
    pub fn root(val: Value, parent: Value) -> Inj {
        let parent_clone = parent.clone();
        Rc::new(RefCell::new(Injection {
            mode: M_VAL,
            full: false,
            key_i: 0,
            keys: Rc::new(RefCell::new(vec![S_DTOP.to_string()])),
            key: S_DTOP.to_string(),
            val,
            parent,
            path: vec![S_DTOP.to_string()],
            nodes: vec![parent_clone],
            handler: inject_handler_fn(),
            errs: Value::empty_list(),
            meta: Value::empty_map(),
            dparent: Value::Noval,
            dpath: vec![S_DTOP.to_string()],
            base: Some(S_DTOP.to_string()),
            modify: None,
            extra: None,
            prior: None,
        }))
    }

    pub fn descend(this: &Inj) {
        // meta.__d++
        {
            let b = this.borrow();
            if let Value::Map(m) = &b.meta {
                let cur = m.borrow().get("__d").and_then(|v| v.as_num()).unwrap_or(0.0);
                m.borrow_mut().insert("__d".to_string(), Value::Num(cur + 1.0));
            }
        }
        let (parentkey, has_dparent, dpath_len, last_part) = {
            let b = this.borrow();
            let parentkey = if b.path.len() >= 2 {
                Some(b.path[b.path.len() - 2].clone())
            } else {
                None
            };
            (parentkey, !b.dparent.is_noval(), b.dpath.len(), b.dpath.last().cloned())
        };

        if !has_dparent {
            if dpath_len > 1 {
                if let Some(pk) = parentkey {
                    this.borrow_mut().dpath.push(pk);
                }
            }
        } else if let Some(pk) = parentkey {
            let newdparent = {
                let b = this.borrow();
                get_prop(&b.dparent, &Value::str(pk.clone()), Value::Noval)
            };
            let mut b = this.borrow_mut();
            b.dparent = newdparent;
            if last_part.as_deref() == Some(format!("$:{pk}").as_str()) {
                let n = b.dpath.len();
                b.dpath.truncate(n.saturating_sub(1));
            } else {
                b.dpath.push(pk);
            }
        }
    }

    pub fn child(this: &Inj, key_i: i64, keys: SVec) -> Inj {
        let (key, parent_val, cval, path, nodes, mode, handler, modify, base, meta, errs, dpath, dparent) = {
            let b = this.borrow();
            let key = str_key(
                keys.borrow()
                    .get(key_i.max(0) as usize)
                    .cloned()
                    .map(Value::Str)
                    .unwrap_or(Value::Noval),
            );
            let parent_val = b.val.clone();
            let cval = get_prop(&parent_val, &Value::str(key.clone()), Value::Noval);
            let mut path = b.path.clone();
            path.push(key.clone());
            let mut nodes = b.nodes.clone();
            nodes.push(parent_val.clone());
            (
                key,
                parent_val,
                cval,
                path,
                nodes,
                b.mode,
                b.handler.clone(),
                b.modify.clone(),
                b.base.clone(),
                b.meta.clone(),
                b.errs.clone(),
                b.dpath.clone(),
                b.dparent.clone(),
            )
        };
        Rc::new(RefCell::new(Injection {
            mode,
            full: false,
            key_i,
            keys,
            key,
            val: cval,
            parent: parent_val,
            path,
            nodes,
            handler,
            errs,
            meta,
            dparent,
            dpath,
            base,
            modify,
            extra: None,
            prior: Some(Rc::clone(this)),
        }))
    }

    pub fn setval(this: &Inj, val: Value, ancestor: Option<i64>) -> Value {
        let anc = ancestor.unwrap_or(0);
        if anc < 2 {
            let (parent, key) = {
                let b = this.borrow();
                (b.parent.clone(), b.key.clone())
            };
            if val.is_noval() {
                let np = del_prop(parent, &Value::str(key));
                this.borrow_mut().parent = np.clone();
                np
            } else {
                set_prop(parent, &Value::str(key), val)
            }
        } else {
            let (aval, akey) = {
                let b = this.borrow();
                let n = b.nodes.len() as i64;
                let aval = if n - anc >= 0 {
                    b.nodes[(n - anc) as usize].clone()
                } else {
                    Value::Noval
                };
                let pn = b.path.len() as i64;
                let akey = if pn - anc >= 0 {
                    b.path[(pn - anc) as usize].clone()
                } else {
                    String::new()
                };
                (aval, akey)
            };
            if val.is_noval() {
                del_prop(aval, &Value::str(akey))
            } else {
                set_prop(aval, &Value::str(akey), val)
            }
        }
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

/// Default inject handler (`_injecthandler`): if the value is a `$NAME`
/// command function, call it; otherwise, in `val` mode for a full-string
/// injection, write the value back into the parent.
pub fn inject_handler_fn() -> NativeFn {
    Rc::new(inject_handler)
}

fn inject_handler(inj: &Inj, val: &Value, r: &str, store: &Value) -> Value {
    let iscmd = is_func(val) && (r.is_empty() || r.starts_with('$'));
    if iscmd {
        if let Value::Func(f) = val {
            return f(inj, val, r, store);
        }
    }
    let (mode, full) = {
        let b = inj.borrow();
        (b.mode, b.full)
    };
    if mode == M_VAL && full {
        Injection::setval(inj, val.clone(), None);
    }
    val.clone()
}

/// `_injectstr` — substitute `` `path` `` references inside a string.
fn injectstr(val: &str, store: &Value, inj: Option<&Inj>) -> Value {
    if val.is_empty() {
        return Value::str("");
    }

    if let Some(caps) = R_INJECTION_FULL.captures(val) {
        if let Some(i) = inj {
            i.borrow_mut().full = true;
        }
        let mut pathref = caps[1].to_string();
        if pathref.chars().count() > 3 {
            pathref = pathref.replace("$BT", S_BT).replace("$DS", S_DS);
        }
        return get_path_inj(store, &Value::str(pathref), inj);
    }

    // partial injection: replace each `ref` occurrence
    let out_str = R_INJECTION_PARTIAL
        .replace_all(val, |caps: &regex::Captures| -> String {
            let mut r = caps[1].to_string();
            if r.chars().count() > 3 {
                r = r.replace("$BT", S_BT).replace("$DS", S_DS);
            }
            if let Some(i) = inj {
                i.borrow_mut().full = false;
            }
            let found = get_path_inj(store, &Value::str(r), inj);
            match &found {
                Value::Noval => String::new(),
                Value::Str(s) => s.clone(),
                other => jsonify(other, Some(&JsonFlags { indent: 0, offset: 0 })),
            }
        })
        .to_string();

    if let Some(i) = inj {
        let handler = {
            i.borrow_mut().full = true;
            i.borrow().handler.clone()
        };
        return handler(i, &Value::str(out_str), val, store);
    }
    Value::str(out_str)
}

pub fn inject(val: Value, store: &Value, injdef: Option<&InjectDef>) -> Value {
    let inj = make_root_injection(val.clone(), store, injdef);
    inject_inj(val, store, &inj)
}

/// Build the root injection for a top-level `inject` (mirrors the TS setup
/// block when `injdef.mode == null`).
fn make_root_injection(val: Value, store: &Value, injdef: Option<&InjectDef>) -> Inj {
    let mut top = indexmap::IndexMap::new();
    top.insert(S_DTOP.to_string(), val.clone());
    let inj = Injection::root(val, Value::map(top));
    {
        let mut b = inj.borrow_mut();
        b.dparent = store.clone();
        let store_errs = get_prop(store, &Value::str(S_DERRS), Value::Noval);
        if !store_errs.is_noval() {
            b.errs = store_errs;
        }
        if let Value::Map(m) = &b.meta {
            m.borrow_mut().insert("__d".to_string(), Value::Num(0.0));
        }
        if let Some(d) = injdef {
            if let Some(x) = &d.modify {
                b.modify = Some(x.clone());
            }
            if let Some(x) = &d.extra {
                b.extra = Some(x.clone());
            }
            if let Some(x) = &d.meta {
                b.meta = x.clone();
            }
            if let Some(x) = &d.handler {
                b.handler = x.clone();
            }
        }
    }
    inj
}

/// Recursive `inject` working against an existing injection.
// `nk_i` is re-read after every child phase to match the canonical loop
// (an injector in the M_VAL phase, e.g. $REF, may change `key_i`).
#[allow(unused_assignments)]
fn inject_inj(mut val: Value, store: &Value, inj: &Inj) -> Value {
    Injection::descend(inj);

    if is_node(&val) {
        // node keys: sorted, then `$`-bearing keys last (for maps).
        let nodekeys: SVec = {
            let ks = keysof_vec(&val);
            if is_map(&val) {
                let (mut plain, dollar): (Vec<String>, Vec<String>) =
                    ks.into_iter().partition(|k| !k.contains(S_DS));
                plain.extend(dollar);
                Rc::new(RefCell::new(plain))
            } else {
                Rc::new(RefCell::new(ks))
            }
        };

        let mut nk_i: i64 = 0;
        loop {
            if nk_i < 0 {
                nk_i += 1;
                continue;
            }
            if nk_i as usize >= nodekeys.borrow().len() {
                break;
            }

            let childinj = Injection::child(inj, nk_i, nodekeys.clone());
            let nodekey = childinj.borrow().key.clone();
            childinj.borrow_mut().mode = M_KEYPRE;

            let prekey = injectstr(&nodekey, store, Some(&childinj));
            nk_i = childinj.borrow().key_i;
            // (keys may have been replaced by an injector — `nodekeys` itself
            // is the shared Rc, so re-reading is implicit.)

            if !prekey.is_noval() {
                let cval = get_prop(&val, &prekey, Value::Noval);
                {
                    let mut b = childinj.borrow_mut();
                    b.val = cval.clone();
                    b.mode = M_VAL;
                }
                inject_inj(cval, store, &childinj);
                nk_i = childinj.borrow().key_i;

                childinj.borrow_mut().mode = M_KEYPOST;
                injectstr(&nodekey, store, Some(&childinj));
                nk_i = childinj.borrow().key_i;
            }

            nk_i += 1;
        }
    } else if let Value::Str(s) = val.clone() {
        inj.borrow_mut().mode = M_VAL;
        let r = injectstr(&s, store, Some(inj));
        val = r.clone();
        if !val.is_skip() {
            Injection::setval(inj, val.clone(), None);
        }
    }

    // custom modification
    let modify = inj.borrow().modify.clone();
    if let Some(m) = modify {
        if !val.is_skip() {
            let (mkey, mparent) = {
                let b = inj.borrow();
                (b.key.clone(), b.parent.clone())
            };
            let mval = get_prop(&mparent, &Value::str(mkey.clone()), Value::Noval);
            m(&mval, &Value::str(mkey), &mparent, inj, store);
        }
    }

    inj.borrow_mut().val = val;
    let parent = inj.borrow().parent.clone();
    get_prop(&parent, &Value::str(S_DTOP), Value::Noval)
}

// ---- transform commands ----------------------------------------------

const T_ANY_I: i64 = T_ANY as i64;

fn errs_push(inj: &Inj, msg: String) {
    let errs = inj.borrow().errs.clone();
    if let Value::List(l) = &errs {
        l.borrow_mut().push(Value::Str(msg));
    }
}

fn placement_str(mode: i64) -> &'static str {
    match mode {
        M_VAL => "value",
        M_KEYPRE | M_KEYPOST => "key",
        _ => "",
    }
}

pub fn check_placement(modes: i64, ijname: &str, parent_types: i64, inj: &Inj) -> bool {
    let (mode, parent) = {
        let b = inj.borrow();
        (b.mode, b.parent.clone())
    };
    if modes & mode == 0 {
        let expected: Vec<&str> = [M_KEYPRE, M_KEYPOST, M_VAL]
            .iter()
            .filter(|m| modes & **m != 0)
            .map(|m| placement_str(*m))
            .collect();
        errs_push(
            inj,
            format!(
                "${ijname}: invalid placement as {}, expected: {}.",
                placement_str(mode),
                expected.join(",")
            ),
        );
        return false;
    }
    if !is_empty(&Value::Num(parent_types as f64)) {
        let ptype = typify(&parent);
        if parent_types & ptype == 0 {
            errs_push(
                inj,
                format!(
                    "${ijname}: invalid placement in parent {}, expected: {}.",
                    type_name(ptype),
                    type_name(parent_types)
                ),
            );
            return false;
        }
    }
    true
}

pub fn injector_args(arg_types: &[i64], args: &[Value]) -> Vec<Value> {
    let mut found: Vec<Value> = Vec::with_capacity(1 + arg_types.len());
    found.push(Value::Noval);
    for (i, at) in arg_types.iter().enumerate() {
        let arg = args.get(i).cloned().unwrap_or(Value::Noval);
        let argtype = typify(&arg);
        if at & argtype == 0 {
            found[0] = Value::str(format!(
                "invalid argument: {} ({} at position {}) is not of type: {}.",
                stringify(&arg, Some(22), false),
                type_name(argtype),
                1 + i,
                type_name(*at)
            ));
            return found;
        }
        found.push(arg);
    }
    found
}

pub fn inject_child(_child: Value, _store: &Value, _inj: &Inj) -> Inj {
    unimplemented!("injectChild: used by $FORMAT/$APPLY — staged")
}

fn transform_delete(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    Injection::setval(inj, Value::Noval, None);
    Value::Noval
}

fn transform_copy(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    if !check_placement(M_VAL, "COPY", T_ANY_I, inj) {
        return Value::Noval;
    }
    let (dparent, key) = {
        let b = inj.borrow();
        (b.dparent.clone(), b.key.clone())
    };
    let out = get_prop(&dparent, &Value::str(key), Value::Noval);
    Injection::setval(inj, out.clone(), None);
    out
}

fn transform_key(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let (mode, parent, dparent, anno_key) = {
        let b = inj.borrow();
        let anno_key = b.path.get(b.path.len().saturating_sub(2)).cloned();
        (b.mode, b.parent.clone(), b.dparent.clone(), anno_key)
    };
    if mode != M_VAL {
        return Value::Noval;
    }
    let keyspec = get_prop(&parent, &Value::str(S_BKEY), Value::Noval);
    if !keyspec.is_noval() {
        del_prop(parent.clone(), &Value::str(S_BKEY));
        return get_prop(&dparent, &keyspec, Value::Noval);
    }
    let anno = get_prop(&parent, &Value::str(S_BANNO), Value::Noval);
    get_prop(
        &anno,
        &Value::str(S_KEY),
        anno_key.map(Value::Str).unwrap_or(Value::Noval),
    )
}

fn transform_anno(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let parent = inj.borrow().parent.clone();
    del_prop(parent, &Value::str(S_BANNO));
    Value::Noval
}

fn transform_merge(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let (mode, key, parent) = {
        let b = inj.borrow();
        (b.mode, b.key.clone(), b.parent.clone())
    };
    let mut out = Value::Noval;
    if mode == M_KEYPRE {
        out = Value::str(key);
    } else if mode == M_KEYPOST {
        out = Value::str(key.clone());
        let mut args = get_prop(&parent, &Value::str(key.clone()), Value::Noval);
        if !is_list(&args) {
            args = Value::list(vec![args]);
        }
        Injection::setval(inj, Value::Noval, None); // remove $MERGE key from parent
        let args_vec: Vec<Value> = args.as_list().map(|l| l.borrow().clone()).unwrap_or_default();
        let mut mergelist: Vec<Value> = vec![parent.clone()];
        mergelist.extend(args_vec);
        mergelist.push(clone(&parent));
        merge(&Value::list(mergelist), Some(1));
    }
    out
}

fn transform_unsupported(name: &'static str) -> impl Fn(&Inj, &Value, &str, &Value) -> Value {
    move |inj: &Inj, _v: &Value, _r: &str, _store: &Value| -> Value {
        errs_push(inj, format!("${name}: not yet ported in the Rust port."));
        Value::Noval
    }
}

pub fn transform(
    data: &Value,
    spec: &Value,
    injdef: Option<&InjectDef>,
) -> Result<Value, StructError> {
    let origspec = spec.clone();
    let spec_clone = clone(&origspec);

    let extra = injdef.and_then(|d| d.extra.clone());
    let collect = injdef.map(|d| d.errs.is_some()).unwrap_or(false);
    let errs = injdef
        .and_then(|d| d.errs.clone())
        .unwrap_or_else(Value::empty_list);

    // split `extra` into data-extras (non-$) and transform-extras ($)
    let mut extra_transforms = indexmap::IndexMap::new();
    let extra_data: Value = match &extra {
        None => Value::Noval,
        Some(e) => {
            let mut a = indexmap::IndexMap::new();
            for (k, v) in items_vec(e) {
                if k.starts_with(S_DS) {
                    extra_transforms.insert(k, v);
                } else {
                    a.insert(k, v);
                }
            }
            Value::map(a)
        }
    };

    let data_clone = merge(
        &Value::list(vec![
            if is_empty(&extra_data) {
                Value::Noval
            } else {
                clone(&extra_data)
            },
            clone(data),
        ]),
        None,
    );

    // build the transform store
    let origspec_for_thunk = origspec.clone();
    let mut store_base: indexmap::IndexMap<String, Value> = indexmap::IndexMap::new();
    store_base.insert(S_DTOP.to_string(), data_clone);
    store_base.insert(
        "$SPEC".to_string(),
        Value::func(move |_i: &Inj, _v: &Value, _r: &str, _s: &Value| origspec_for_thunk.clone()),
    );
    store_base.insert(
        "$BT".to_string(),
        Value::func(|_i: &Inj, _v: &Value, _r: &str, _s: &Value| Value::str(S_BT)),
    );
    store_base.insert(
        "$DS".to_string(),
        Value::func(|_i: &Inj, _v: &Value, _r: &str, _s: &Value| Value::str(S_DS)),
    );
    store_base.insert(
        "$WHEN".to_string(),
        Value::func(|_i: &Inj, _v: &Value, _r: &str, _s: &Value| Value::str(iso_now())),
    );
    store_base.insert("$DELETE".to_string(), Value::func(transform_delete));
    store_base.insert("$COPY".to_string(), Value::func(transform_copy));
    store_base.insert("$KEY".to_string(), Value::func(transform_key));
    store_base.insert("$ANNO".to_string(), Value::func(transform_anno));
    store_base.insert("$MERGE".to_string(), Value::func(transform_merge));
    store_base.insert("$EACH".to_string(), Value::func(transform_unsupported("EACH")));
    store_base.insert("$PACK".to_string(), Value::func(transform_unsupported("PACK")));
    store_base.insert("$REF".to_string(), Value::func(transform_unsupported("REF")));
    store_base.insert(
        "$FORMAT".to_string(),
        Value::func(transform_unsupported("FORMAT")),
    );
    store_base.insert(
        "$APPLY".to_string(),
        Value::func(transform_unsupported("APPLY")),
    );

    let store = merge(
        &Value::list(vec![
            Value::map(store_base),
            Value::map(extra_transforms),
            Value::map_of([(S_DERRS.to_string(), errs.clone())]),
        ]),
        Some(1),
    );

    let out = inject(spec_clone, &store, injdef);

    let errlen = errs.as_list().map(|l| l.borrow().len()).unwrap_or(0);
    if errlen > 0 && !collect {
        let msgs: Vec<String> = errs
            .as_list()
            .map(|l| l.borrow().iter().map(|e| js_string(e)).collect())
            .unwrap_or_default();
        return Err(StructError {
            message: msgs.join(" | "),
        });
    }

    Ok(out)
}

fn iso_now() -> String {
    // best-effort ISO-8601 UTC string; the corpus can't assert the exact
    // value (it changes), so granularity to the second is fine.
    use std::time::{SystemTime, UNIX_EPOCH};
    let dur = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    let secs = dur.as_secs() as i64;
    let millis = dur.subsec_millis();
    // days since 1970-01-01
    let days = secs.div_euclid(86_400);
    let tod = secs.rem_euclid(86_400);
    let (h, m, s) = (tod / 3600, (tod % 3600) / 60, tod % 60);
    let (y, mo, d) = civil_from_days(days);
    format!(
        "{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}.{millis:03}Z"
    )
}

fn civil_from_days(z: i64) -> (i64, i64, i64) {
    // Howard Hinnant's algorithm.
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    (if m <= 2 { y + 1 } else { y }, m, d)
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

// keep `Injection::has_handler` referenced (used once staging is complete)
#[allow(dead_code)]
fn _keepalive() {
    let _ = Injection::has_handler(None);
    let _ = inject_child as fn(Value, &Value, &Inj) -> Inj;
}
