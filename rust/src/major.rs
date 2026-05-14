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
use crate::value::{js_string, js_to_int32, js_to_number, Value};
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
    walk_impl(
        val,
        before,
        after,
        maxdepth,
        &Value::Noval,
        &Value::Noval,
        &mut path,
    )
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
                before.as_deref_mut(),
                after.as_deref_mut(),
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
                        dst_b
                            .borrow()
                            .get(pi as usize)
                            .cloned()
                            .unwrap_or(Value::Noval)
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
                let cur = m
                    .borrow()
                    .get("__d")
                    .and_then(|v| v.as_num())
                    .unwrap_or(0.0);
                m.borrow_mut()
                    .insert("__d".to_string(), Value::Num(cur + 1.0));
            }
        }
        let (parentkey, has_dparent, dpath_len, last_part) = {
            let b = this.borrow();
            let parentkey = if b.path.len() >= 2 {
                Some(b.path[b.path.len() - 2].clone())
            } else {
                None
            };
            (
                parentkey,
                !b.dparent.is_noval(),
                b.dpath.len(),
                b.dpath.last().cloned(),
            )
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
        let (
            key,
            parent_val,
            cval,
            path,
            nodes,
            mode,
            handler,
            modify,
            base,
            meta,
            errs,
            dpath,
            dparent,
        ) = {
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
    let dparent = injdef
        .map(|i| i.borrow().dparent.clone())
        .unwrap_or(Value::Noval);

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
                                    &Value::list(fullpath.into_iter().map(Value::Str).collect()),
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
        .replace_all(val, |caps: &crate::re::Captures<'_>| -> String {
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
                other => jsonify(
                    other,
                    Some(&JsonFlags {
                        indent: 0,
                        offset: 0,
                    }),
                ),
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

pub fn inject_child(child: Value, store: &Value, inj: &Inj) -> Inj {
    let prior = inj.borrow().prior.clone();
    let cinj: Inj = match prior {
        None => Rc::clone(inj),
        Some(p) => {
            let pprior = p.borrow().prior.clone();
            match pprior {
                Some(pp) => {
                    let (pki, pkeys, pkey) = {
                        let b = p.borrow();
                        (b.key_i, b.keys.clone(), b.key.clone())
                    };
                    let c = Injection::child(&pp, pki, pkeys);
                    c.borrow_mut().val = child.clone();
                    let cparent = c.borrow().parent.clone();
                    set_prop(cparent, &Value::str(pkey), child.clone());
                    c
                }
                None => {
                    let (ki, keys, key) = {
                        let b = inj.borrow();
                        (b.key_i, b.keys.clone(), b.key.clone())
                    };
                    let c = Injection::child(&p, ki, keys);
                    c.borrow_mut().val = child.clone();
                    let cparent = c.borrow().parent.clone();
                    set_prop(cparent, &Value::str(key), child.clone());
                    c
                }
            }
        }
    };
    let _ = inject_inj(child, store, &cinj);
    cinj
}

const FORMATTER_NAMES: [&str; 7] = [
    "identity", "upper", "lower", "string", "number", "integer", "concat",
];

fn apply_formatter(name: &str, k: &Value, v: &Value) -> Value {
    match name {
        "identity" => v.clone(),
        "upper" => {
            if is_node(v) {
                v.clone()
            } else {
                Value::str(js_string(v).to_uppercase())
            }
        }
        "lower" => {
            if is_node(v) {
                v.clone()
            } else {
                Value::str(js_string(v).to_lowercase())
            }
        }
        "string" => {
            if is_node(v) {
                v.clone()
            } else {
                Value::str(js_string(v))
            }
        }
        "number" => {
            if is_node(v) {
                v.clone()
            } else {
                let n = js_to_number(v);
                Value::Num(if n.is_nan() { 0.0 } else { n })
            }
        }
        "integer" => {
            if is_node(v) {
                v.clone()
            } else {
                let n = js_to_number(v);
                let n = if n.is_nan() { 0.0 } else { n };
                Value::Num(js_to_int32(n) as f64)
            }
        }
        "concat" => {
            if k.is_noval() && is_list(v) {
                Value::str(
                    items_vec(v)
                        .iter()
                        .map(|(_, n)| {
                            if is_node(n) {
                                String::new()
                            } else {
                                js_string(n)
                            }
                        })
                        .collect::<Vec<_>>()
                        .join(""),
                )
            } else {
                v.clone()
            }
        }
        _ => v.clone(),
    }
}

// `$FORMAT` — render a templated value through a named (or supplied) formatter.
fn transform_format(inj: &Inj, _val: &Value, _r: &str, store: &Value) -> Value {
    inj.borrow().keys.borrow_mut().truncate(1);
    if inj.borrow().mode != M_VAL {
        return Value::Noval;
    }
    let (parent, path, nodes) = {
        let b = inj.borrow();
        (b.parent.clone(), b.path.clone(), b.nodes.clone())
    };
    let name = get_prop(&parent, &Value::Num(1.0), Value::Noval);
    let child = get_prop(&parent, &Value::Num(2.0), Value::Noval);
    let tkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let nlen = nodes.len();
    let target = if nlen >= 2 {
        nodes[nlen - 2].clone()
    } else if nlen >= 1 {
        nodes[nlen - 1].clone()
    } else {
        Value::Noval
    };

    let cinj = inject_child(child, store, inj);
    let resolved = cinj.borrow().val.clone();

    let fname: Option<String> = name
        .as_str()
        .filter(|n| FORMATTER_NAMES.contains(n))
        .map(|s| s.to_string());
    if fname.is_none() && !is_func(&name) {
        errs_push(
            inj,
            format!("$FORMAT: unknown format: {}.", js_string(&name)),
        );
        return Value::Noval;
    }

    let out = if let Some(fn_name) = &fname {
        let mut fmt = |k: &Value, v: &Value, _p: &Value, _t: &[String]| -> Value {
            apply_formatter(fn_name, k, v)
        };
        walk(resolved, Some(&mut fmt), None, None)
    } else if let Value::Func(f) = &name {
        let f = f.clone();
        let mut fmt =
            |_k: &Value, v: &Value, _p: &Value, _t: &[String]| -> Value { f(inj, v, "", store) };
        walk(resolved, Some(&mut fmt), None, None)
    } else {
        resolved
    };

    set_prop(target, &Value::str(tkey), out.clone());
    out
}

// `$APPLY` — call a function (from the spec args) on the resolved child.
fn transform_apply(inj: &Inj, _val: &Value, _r: &str, store: &Value) -> Value {
    if !check_placement(M_VAL, "APPLY", T_LIST as i64, inj) {
        return Value::Noval;
    }
    let (parent, path, nodes) = {
        let b = inj.borrow();
        (b.parent.clone(), b.path.clone(), b.nodes.clone())
    };
    let args: Vec<Value> = slice(parent.clone(), Some(1), None, false)
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    let ia = injector_args(&[T_FUNCTION as i64, T_ANY as i64], &args);
    if let Value::Str(e) = &ia[0] {
        errs_push(inj, format!("$APPLY: {e}"));
        return Value::Noval;
    }
    let apply = ia.get(1).cloned().unwrap_or(Value::Noval);
    let child = ia.get(2).cloned().unwrap_or(Value::Noval);
    let tkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let nlen = nodes.len();
    let target = if nlen >= 2 {
        nodes[nlen - 2].clone()
    } else if nlen >= 1 {
        nodes[nlen - 1].clone()
    } else {
        Value::Noval
    };
    let cinj = inject_child(child, store, inj);
    let resolved = cinj.borrow().val.clone();
    // The corpus only exercises the error paths; if `apply` is a callable, do
    // a best-effort call (the canonical passes (resolved, store, cinj)).
    let out = if let Value::Func(f) = &apply {
        f(&cinj, &resolved, "", store)
    } else {
        resolved
    };
    set_prop(target, &Value::str(tkey), out.clone());
    out
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
        let args_vec: Vec<Value> = args
            .as_list()
            .map(|l| l.borrow().clone())
            .unwrap_or_default();
        let mut mergelist: Vec<Value> = vec![parent.clone()];
        mergelist.extend(args_vec);
        mergelist.push(clone(&parent));
        merge(&Value::list(mergelist), Some(1));
    }
    out
}

fn slice_str_vec(v: &[String], start: Option<i64>, end: Option<i64>) -> Vec<String> {
    match slice(path_value(v), start, end, false) {
        Value::List(l) => l
            .borrow()
            .iter()
            .map(|x| x.as_str().map(|s| s.to_string()).unwrap_or_default())
            .collect(),
        _ => Vec::new(),
    }
}

// `$REF` — reference the original spec (enables recursive transforms).
fn transform_ref(inj: &Inj, val: &Value, _r: &str, store: &Value) -> Value {
    let (mode, parent, path, nodes) = {
        let b = inj.borrow();
        (b.mode, b.parent.clone(), b.path.clone(), b.nodes.clone())
    };
    if mode != M_VAL {
        return Value::Noval;
    }
    let refpath = get_prop(&parent, &Value::Num(1.0), Value::Noval);
    {
        let keylen = inj.borrow().keys.borrow().len() as i64;
        inj.borrow_mut().key_i = keylen;
    }
    // spec = ($SPEC)()
    let spec = {
        let sf = get_prop(store, &Value::str(S_DSPEC), Value::Noval);
        match &sf {
            Value::Func(f) => f(inj, &Value::Noval, "", store),
            _ => Value::Noval,
        }
    };
    let dpath = slice_str_vec(&path, Some(1), None);
    let dparent_for_ref = get_path_inj(&spec, &path_value(&dpath), None);
    let ref_def = InjectDef {
        dpath: Some(dpath.clone()),
        dparent: Some(dparent_for_ref),
        ..Default::default()
    };
    let refval = get_path(&spec, &refpath, Some(&ref_def));

    let mut has_sub_ref = false;
    if is_node(&refval) {
        let mut probe = |_k: &Value, v: &Value, _p: &Value, _t: &[String]| -> Value {
            if matches!(v, Value::Str(s) if s == "`$REF`") {
                has_sub_ref = true;
            }
            v.clone()
        };
        walk(refval.clone(), Some(&mut probe), None, None);
    }

    let tref = clone(&refval);
    let cpath = slice_str_vec(&path, Some(-3), None);
    let tpath = slice_str_vec(&path, Some(-1), None);
    let tcur = get_path_inj(store, &path_value(&cpath), None);
    let tval_at = get_path_inj(store, &path_value(&tpath), None);

    let rval = if !has_sub_ref || !tval_at.is_noval() {
        let tinj = Injection::child(
            inj,
            0,
            Rc::new(RefCell::new(vec![tpath
                .last()
                .cloned()
                .unwrap_or_default()])),
        );
        {
            let mut b = tinj.borrow_mut();
            b.path = tpath.clone();
            let nlen = nodes.len();
            b.nodes = if nlen >= 1 {
                nodes[..nlen - 1].to_vec()
            } else {
                Vec::new()
            };
            b.parent = if nlen >= 2 {
                nodes[nlen - 2].clone()
            } else {
                Value::Noval
            };
            b.val = tref.clone();
            b.dpath = cpath.clone();
            b.dparent = tcur.clone();
        }
        let _ = inject_inj(tref.clone(), store, &tinj);
        let v = tinj.borrow().val.clone();
        v
    } else {
        Value::Noval
    };

    let grandparent = Injection::setval(inj, rval, Some(2));
    if is_list(&grandparent) {
        let prior = inj.borrow().prior.clone();
        if let Some(p) = prior {
            p.borrow_mut().key_i -= 1;
        }
    }
    val.clone()
}

fn srcpath_split(srcpath: &str) -> Vec<String> {
    srcpath.split('.').map(|s| s.to_string()).collect()
}

// `$EACH` — apply a child template to every entry of a list or map.
// Spec form (a list): ['`$EACH`', 'source-path', child-template]
fn transform_each(inj: &Inj, _val: &Value, _r: &str, store: &Value) -> Value {
    if !check_placement(M_VAL, "EACH", T_LIST as i64, inj) {
        return Value::Noval;
    }
    // remove remaining keys to avoid spurious processing
    inj.borrow().keys.borrow_mut().truncate(1);

    let (parent, path, nodes, base) = {
        let b = inj.borrow();
        (
            b.parent.clone(),
            b.path.clone(),
            b.nodes.clone(),
            b.base.clone(),
        )
    };
    let args: Vec<Value> = slice(parent.clone(), Some(1), None, false)
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    let ia = injector_args(&[T_STRING as i64, T_ANY as i64], &args);
    if let Value::Str(e) = &ia[0] {
        errs_push(inj, format!("$EACH: {e}"));
        return Value::Noval;
    }
    let srcpath = ia.get(1).cloned().unwrap_or(Value::Noval);
    let child = ia.get(2).cloned().unwrap_or(Value::Noval);
    let srcpath_str = srcpath.as_str().unwrap_or("").to_string();

    let srcstore = get_prop(
        store,
        &Value::str(base.clone().unwrap_or_default()),
        store.clone(),
    );
    let src = get_path_inj(&srcstore, &srcpath, Some(inj));
    let srctype = typify(&src);

    let tkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let nlen = nodes.len();
    let target = if nlen >= 2 {
        nodes[nlen - 2].clone()
    } else if nlen >= 1 {
        nodes[nlen - 1].clone()
    } else {
        Value::Noval
    };

    let tval: Vec<Value> = if srctype & (T_LIST as i64) != 0 {
        items_vec(&src).iter().map(|_| clone(&child)).collect()
    } else if srctype & (T_MAP as i64) != 0 {
        items_vec(&src)
            .iter()
            .map(|(k, _)| {
                merge(
                    &Value::list(vec![
                        clone(&child),
                        Value::map_of([(
                            S_BANNO.to_string(),
                            Value::map_of([(S_KEY.to_string(), Value::str(k.clone()))]),
                        )]),
                    ]),
                    Some(1),
                )
            })
            .collect()
    } else {
        Vec::new()
    };

    let mut rval = Value::empty_list();
    if !tval.is_empty() {
        let tcur_inner: Value = if src.is_nullish() {
            Value::Noval
        } else {
            Value::list(items_vec(&src).into_iter().map(|(_, v)| v).collect())
        };
        let ckey = path
            .get(path.len().saturating_sub(2))
            .cloned()
            .unwrap_or_default();
        let tpath = slice_str_vec(&path, Some(-1), None);
        let mut dpath: Vec<String> = vec![S_DTOP.to_string()];
        dpath.extend(srcpath_split(&srcpath_str));
        dpath.push(format!("$:{ckey}"));

        let mut tcur = Value::map_of([(ckey.clone(), tcur_inner)]);
        if tpath.len() > 1 {
            let pkey = path
                .get(path.len().saturating_sub(3))
                .cloned()
                .unwrap_or_else(|| S_DTOP.to_string());
            tcur = Value::map_of([(pkey.clone(), tcur)]);
            dpath.push(format!("$:{pkey}"));
        }

        let tval_v = Value::list(tval);
        let tinj = Injection::child(inj, 0, Rc::new(RefCell::new(vec![ckey.clone()])));
        {
            let mut b = tinj.borrow_mut();
            b.path = tpath;
            b.nodes = if nlen >= 1 {
                nodes[..nlen - 1].to_vec()
            } else {
                Vec::new()
            };
            b.parent = b.nodes.last().cloned().unwrap_or(Value::Noval);
            b.val = tval_v.clone();
            b.dpath = dpath;
            b.dparent = tcur;
        }
        let pclone = tinj.borrow().parent.clone();
        set_prop(pclone, &Value::str(ckey), tval_v.clone());
        let _ = inject_inj(tval_v.clone(), store, &tinj);
        rval = tinj.borrow().val.clone();
    }

    set_prop(target, &Value::str(tkey), rval.clone());
    get_prop(&rval, &Value::Num(0.0), Value::Noval)
}

// `$PACK` — repack a list/map into a map keyed by `$KEY`.
// Spec form (a map): { '`$PACK`': ['source-path', child-template] }
fn transform_pack(inj: &Inj, _val: &Value, _r: &str, store: &Value) -> Value {
    if !check_placement(M_KEYPRE, "EACH", T_MAP as i64, inj) {
        return Value::Noval;
    }
    let (key, parent, path, nodes, base) = {
        let b = inj.borrow();
        (
            b.key.clone(),
            b.parent.clone(),
            b.path.clone(),
            b.nodes.clone(),
            b.base.clone(),
        )
    };
    let args = get_prop(&parent, &Value::str(key), Value::Noval);
    let args_vec: Vec<Value> = args
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    let ia = injector_args(&[T_STRING as i64, T_ANY as i64], &args_vec);
    if let Value::Str(e) = &ia[0] {
        errs_push(inj, format!("$EACH: {e}"));
        return Value::Noval;
    }
    let srcpath = ia.get(1).cloned().unwrap_or(Value::Noval);
    let origchildspec = ia.get(2).cloned().unwrap_or(Value::Noval);
    let srcpath_str = srcpath.as_str().unwrap_or("").to_string();

    let tkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let pathsize = path.len();
    let nlen = nodes.len();
    let target = if pathsize >= 2 {
        nodes.get(pathsize - 2).cloned().unwrap_or(Value::Noval)
    } else {
        nodes
            .get(pathsize.saturating_sub(1))
            .cloned()
            .unwrap_or(Value::Noval)
    };
    let target = if target.is_noval() {
        nodes
            .get(pathsize.saturating_sub(1))
            .cloned()
            .unwrap_or(Value::Noval)
    } else {
        target
    };

    let srcstore = get_prop(
        store,
        &Value::str(base.clone().unwrap_or_default()),
        store.clone(),
    );
    let src_raw = get_path_inj(&srcstore, &srcpath, Some(inj));
    let src: Value = if is_list(&src_raw) {
        src_raw
    } else if is_map(&src_raw) {
        Value::list(
            items_vec(&src_raw)
                .into_iter()
                .map(|(k, v)| {
                    set_prop(
                        v.clone(),
                        &Value::str(S_BANNO),
                        Value::map_of([(S_KEY.to_string(), Value::str(k))]),
                    );
                    v
                })
                .collect(),
        )
    } else {
        return Value::Noval;
    };
    if src.is_nullish() {
        return Value::Noval;
    }

    let keypath = get_prop(&origchildspec, &Value::str(S_BKEY), Value::Noval);
    let childspec = del_prop(origchildspec.clone(), &Value::str(S_BKEY));
    let child = get_prop(&childspec, &Value::str(S_BVAL), childspec.clone());

    let resolve_key = |srckey: &str, srcnode: &Value| -> Value {
        if keypath.is_noval() {
            Value::str(srckey)
        } else if let Value::Str(kp) = &keypath {
            if kp.starts_with('`') {
                let m = merge(
                    &Value::list(vec![
                        Value::empty_map(),
                        store.clone(),
                        Value::map_of([(S_DTOP.to_string(), srcnode.clone())]),
                    ]),
                    Some(1),
                );
                inject(Value::str(kp.clone()), &m, None)
            } else {
                get_path_inj(srcnode, &Value::str(kp.clone()), Some(inj))
            }
        } else {
            Value::str(srckey)
        }
    };

    let tval = Value::empty_map();
    for (srckey, srcnode) in items_vec(&src) {
        let k = resolve_key(&srckey, &srcnode);
        let tchild = clone(&child);
        set_prop(tval.clone(), &k, tchild.clone());
        let anno = get_prop(&srcnode, &Value::str(S_BANNO), Value::Noval);
        if anno.is_noval() {
            del_prop(tchild, &Value::str(S_BANNO));
        } else {
            set_prop(tchild, &Value::str(S_BANNO), anno);
        }
    }

    let mut rval = Value::empty_map();
    if !is_empty(&tval) {
        let tsrc = Value::empty_map();
        for (i, (_, n)) in items_vec(&src).into_iter().enumerate() {
            let kn = if keypath.is_noval() {
                Value::Num(i as f64)
            } else {
                resolve_key("", &n)
            };
            set_prop(tsrc.clone(), &kn, n);
        }
        let tpath = slice_str_vec(&path, Some(-1), None);
        let ckey = path
            .get(path.len().saturating_sub(2))
            .cloned()
            .unwrap_or_default();
        let mut dpath: Vec<String> = vec![S_DTOP.to_string()];
        dpath.extend(srcpath_split(&srcpath_str));
        dpath.push(format!("$:{ckey}"));
        let mut tcur = Value::map_of([(ckey.clone(), tsrc)]);
        if tpath.len() > 1 {
            let pkey = path
                .get(path.len().saturating_sub(3))
                .cloned()
                .unwrap_or_else(|| S_DTOP.to_string());
            tcur = Value::map_of([(pkey.clone(), tcur)]);
            dpath.push(format!("$:{pkey}"));
        }
        let tinj = Injection::child(inj, 0, Rc::new(RefCell::new(vec![ckey.clone()])));
        {
            let mut b = tinj.borrow_mut();
            b.path = tpath;
            b.nodes = if nlen >= 1 {
                nodes[..nlen - 1].to_vec()
            } else {
                Vec::new()
            };
            b.parent = b.nodes.last().cloned().unwrap_or(Value::Noval);
            b.val = tval.clone();
            b.dpath = dpath;
            b.dparent = tcur;
        }
        let _ = inject_inj(tval.clone(), store, &tinj);
        rval = tinj.borrow().val.clone();
    }

    set_prop(target, &Value::str(tkey), rval);
    Value::Noval
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
    store_base.insert("$EACH".to_string(), Value::func(transform_each));
    store_base.insert("$PACK".to_string(), Value::func(transform_pack));
    store_base.insert("$REF".to_string(), Value::func(transform_ref));
    store_base.insert("$FORMAT".to_string(), Value::func(transform_format));
    store_base.insert("$APPLY".to_string(), Value::func(transform_apply));

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
            .map(|l| l.borrow().iter().map(js_string).collect())
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
    let dur = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = dur.as_secs() as i64;
    let millis = dur.subsec_millis();
    // days since 1970-01-01
    let days = secs.div_euclid(86_400);
    let tod = secs.rem_euclid(86_400);
    let (h, m, s) = (tod / 3600, (tod % 3600) / 60, tod % 60);
    let (y, mo, d) = civil_from_days(days);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}.{millis:03}Z")
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

// ---- validate --------------------------------------------------------

fn path_value(path: &[String]) -> Value {
    Value::list(path.iter().cloned().map(Value::Str).collect())
}

fn invalid_type_msg(path: &[String], needtype: &str, vt: i64, v: &Value) -> String {
    let vs = if v.is_nullish() {
        "no value".to_string()
    } else {
        stringify(v, None, false)
    };
    let field_part = if path.len() > 1 {
        format!("field {} to be ", pathify(&path_value(path), Some(1), None))
    } else {
        String::new()
    };
    let type_part = if !v.is_nullish() {
        format!("{}{}", type_name(vt), S_VIZ)
    } else {
        String::new()
    };
    format!("Expected {field_part}{needtype}, but found {type_part}{vs}.")
}

fn validate_string(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let (dparent, key, path) = {
        let b = inj.borrow();
        (b.dparent.clone(), b.key.clone(), b.path.clone())
    };
    let out = get_prop(&dparent, &Value::str(key), Value::Noval);
    let t = typify(&out);
    if t & (T_STRING as i64) == 0 {
        errs_push(inj, invalid_type_msg(&path, "string", t, &out));
        return Value::Noval;
    }
    if matches!(&out, Value::Str(s) if s.is_empty()) {
        errs_push(
            inj,
            format!(
                "Empty string at {}",
                pathify(&path_value(&path), Some(1), None)
            ),
        );
        return Value::Noval;
    }
    out
}

fn validate_type(inj: &Inj, _v: &Value, r: &str, _store: &Value) -> Value {
    let tname: String = r.chars().skip(1).collect::<String>().to_lowercase();
    let typev: i64 = match TYPENAME.iter().position(|x| *x == tname) {
        Some(idx) => 1i64 << (31 - idx as i64),
        None => 0,
    };
    let (dparent, key, path) = {
        let b = inj.borrow();
        (b.dparent.clone(), b.key.clone(), b.path.clone())
    };
    let out = get_prop(&dparent, &Value::str(key), Value::Noval);
    let t = typify(&out);
    if t & typev == 0 {
        errs_push(inj, invalid_type_msg(&path, &tname, t, &out));
        return Value::Noval;
    }
    out
}

fn validate_any(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let (dparent, key) = {
        let b = inj.borrow();
        (b.dparent.clone(), b.key.clone())
    };
    get_prop(&dparent, &Value::str(key), Value::Noval)
}

/// Render a list of tvals as `"a, b, c"`, lowering `` `$NAME` `` -> `name`.
fn tvals_desc(tvals: &[Value]) -> String {
    let joined = tvals
        .iter()
        .map(|v| stringify(v, None, false))
        .collect::<Vec<_>>()
        .join(", ");
    R_TRANSFORM_NAME
        .replace_all(&joined, |caps: &crate::re::Captures<'_>| caps[1].to_lowercase())
        .to_string()
}

// Map / list `$CHILD`: apply a child template to every direct child.
fn validate_child(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let (mode, key, parent, path, dparent) = {
        let b = inj.borrow();
        (
            b.mode,
            b.key.clone(),
            b.parent.clone(),
            b.path.clone(),
            b.dparent.clone(),
        )
    };

    if mode == M_KEYPRE {
        let childtm = get_prop(&parent, &Value::str(key), Value::Noval);
        let pkey = path
            .get(path.len().saturating_sub(2))
            .cloned()
            .unwrap_or_default();
        let mut tval = get_prop(&dparent, &Value::str(pkey), Value::Noval);
        if tval.is_noval() {
            tval = Value::empty_map();
        } else if !is_map(&tval) {
            errs_push(
                inj,
                invalid_type_msg(
                    &path[..path.len().saturating_sub(1)],
                    S_object,
                    typify(&tval),
                    &tval,
                ),
            );
            return Value::Noval;
        }
        let ckeys = keysof_vec(&tval);
        for ck in ckeys {
            set_prop(parent.clone(), &Value::str(ck.clone()), clone(&childtm));
            inj.borrow().keys.borrow_mut().push(ck);
        }
        Injection::setval(inj, Value::Noval, None);
        return Value::Noval;
    }

    if mode == M_VAL {
        if !is_list(&parent) {
            errs_push(inj, "Invalid $CHILD as value".to_string());
            return Value::Noval;
        }
        let childtm = get_prop(&parent, &Value::Num(1.0), Value::Noval);
        if dparent.is_noval() {
            slice(parent.clone(), Some(0), Some(0), true); // empty default
            return Value::Noval;
        }
        if !is_list(&dparent) {
            errs_push(
                inj,
                invalid_type_msg(
                    &path[..path.len().saturating_sub(1)],
                    S_list,
                    typify(&dparent),
                    &dparent,
                ),
            );
            let plen = parent.as_list().map(|l| l.borrow().len()).unwrap_or(0) as i64;
            inj.borrow_mut().key_i = plen;
            return dparent;
        }
        let dlen = dparent.as_list().map(|l| l.borrow().len()).unwrap_or(0);
        for n in 0..dlen {
            set_prop(parent.clone(), &Value::Num(n as f64), clone(&childtm));
        }
        slice(parent.clone(), Some(0), Some(dlen as i64), true);
        inj.borrow_mut().key_i = 0;
        return get_prop(&dparent, &Value::Num(0.0), Value::Noval);
    }

    Value::Noval
}

// `$ONE`: value must match exactly one of a list of alternative sub-specs.
fn validate_one(inj: &Inj, _v: &Value, _r: &str, store: &Value) -> Value {
    let (mode, parent, key_i) = {
        let b = inj.borrow();
        (b.mode, b.parent.clone(), b.key_i)
    };
    if mode != M_VAL {
        return Value::Noval;
    }
    if !is_list(&parent) || key_i != 0 {
        let path = inj.borrow().path.clone();
        errs_push(
            inj,
            format!(
                "The $ONE validator at field {} must be the first element of an array.",
                pathify(&path_value(&path), Some(1), Some(1))
            ),
        );
        return Value::Noval;
    }
    let keylen = inj.borrow().keys.borrow().len() as i64;
    inj.borrow_mut().key_i = keylen;
    let dparent = inj.borrow().dparent.clone();
    Injection::setval(inj, dparent.clone(), Some(2));
    {
        let mut b = inj.borrow_mut();
        let n = b.path.len();
        b.path.truncate(n.saturating_sub(1));
        b.key = b.path.last().cloned().unwrap_or_default();
    }
    let path_after = inj.borrow().path.clone();
    let meta = inj.borrow().meta.clone();
    let tvals: Vec<Value> = slice(parent.clone(), Some(1), None, false)
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    if tvals.is_empty() {
        errs_push(
            inj,
            format!(
                "The $ONE validator at field {} must have at least one argument.",
                pathify(&path_value(&path_after), Some(1), Some(1))
            ),
        );
        return Value::Noval;
    }
    for tval in &tvals {
        let terrs = Value::empty_list();
        let mut vstore = match merge(
            &Value::list(vec![Value::empty_map(), store.clone()]),
            Some(1),
        ) {
            v @ Value::Map(_) => v,
            _ => Value::empty_map(),
        };
        set_prop(vstore.clone(), &Value::str(S_DTOP), dparent.clone());
        let _ = &mut vstore;
        let vd = InjectDef {
            extra: Some(vstore.clone()),
            errs: Some(terrs.clone()),
            meta: Some(meta.clone()),
            ..Default::default()
        };
        let vcur = validate(&dparent, tval, Some(&vd)).unwrap_or(Value::Noval);
        Injection::setval(inj, vcur, Some(-2)); // hmm: ancestor -2 -> handled below
        let terrlen = terrs.as_list().map(|l| l.borrow().len()).unwrap_or(0);
        if terrlen == 0 {
            return Value::Noval;
        }
    }
    let valdesc = tvals_desc(&tvals);
    errs_push(
        inj,
        invalid_type_msg(
            &path_after,
            &format!(
                "{}{}",
                if tvals.len() > 1 { "one of " } else { "" },
                valdesc
            ),
            typify(&dparent),
            &dparent,
        ),
    );
    Value::Noval
}

// `$EXACT`: value must equal a literal exactly (no shape coercion).
fn validate_exact(inj: &Inj, _v: &Value, _r: &str, _store: &Value) -> Value {
    let (mode, parent, key, key_i) = {
        let b = inj.borrow();
        (b.mode, b.parent.clone(), b.key.clone(), b.key_i)
    };
    if mode != M_VAL {
        del_prop(parent, &Value::str(key));
        return Value::Noval;
    }
    if !is_list(&parent) || key_i != 0 {
        let path = inj.borrow().path.clone();
        errs_push(
            inj,
            format!(
                "The $EXACT validator at field {} must be the first element of an array.",
                pathify(&path_value(&path), Some(1), Some(1))
            ),
        );
        return Value::Noval;
    }
    let keylen = inj.borrow().keys.borrow().len() as i64;
    inj.borrow_mut().key_i = keylen;
    let dparent = inj.borrow().dparent.clone();
    Injection::setval(inj, dparent.clone(), Some(2));
    {
        let mut b = inj.borrow_mut();
        let n = b.path.len();
        b.path.truncate(n.saturating_sub(1));
        b.key = b.path.last().cloned().unwrap_or_default();
    }
    let path_after = inj.borrow().path.clone();
    let tvals: Vec<Value> = slice(parent.clone(), Some(1), None, false)
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    if tvals.is_empty() {
        errs_push(
            inj,
            format!(
                "The $EXACT validator at field {} must have at least one argument.",
                pathify(&path_value(&path_after), Some(1), Some(1))
            ),
        );
        return Value::Noval;
    }
    let mut currentstr: Option<String> = None;
    for tval in &tvals {
        let mut exactmatch = tval == &dparent;
        if !exactmatch && is_node(tval) {
            let cs = currentstr
                .get_or_insert_with(|| stringify(&dparent, None, false))
                .clone();
            exactmatch = stringify(tval, None, false) == cs;
        }
        if exactmatch {
            return Value::Noval;
        }
    }
    let valdesc = tvals_desc(&tvals);
    let need = format!(
        "{}exactly equal to {}{}",
        if path_after.len() > 1 { "" } else { "value " },
        if tvals.len() == 1 { "" } else { "one of " },
        valdesc
    );
    errs_push(
        inj,
        invalid_type_msg(&path_after, &need, typify(&dparent), &dparent),
    );
    Value::Noval
}

/// `_validation` — the modify hook installed by `validate` (runs after the
/// per-key special commands).
fn validation_modify(pval: &Value, key: &Value, parent: &Value, inj: &Inj, _store: &Value) {
    if pval.is_skip() {
        return;
    }
    let (meta, dparent, path) = {
        let b = inj.borrow();
        (b.meta.clone(), b.dparent.clone(), b.path.clone())
    };
    let exact = matches!(
        get_prop(&meta, &Value::str(S_BEXACT), Value::Bool(false)),
        Value::Bool(true)
    );
    let cval = get_prop(&dparent, key, Value::Noval);
    if !exact && cval.is_noval() {
        return;
    }
    let ptype = typify(pval);
    if ptype & (T_STRING as i64) != 0 {
        if let Value::Str(s) = pval {
            if s.contains(S_DS) {
                return; // remaining special command — leave it
            }
        }
    }
    let ctype = typify(&cval);
    if ptype != ctype && !pval.is_noval() {
        errs_push(
            inj,
            invalid_type_msg(&path, &type_name(ptype), ctype, &cval),
        );
        return;
    }

    if is_map(&cval) {
        if !is_map(pval) {
            errs_push(
                inj,
                invalid_type_msg(&path, &type_name(ptype), ctype, &cval),
            );
            return;
        }
        let ckeys = keysof_vec(&cval);
        let pkeys = keysof_vec(pval);
        let open = matches!(
            get_prop(pval, &Value::str(S_BOPEN), Value::Noval),
            Value::Bool(true)
        );
        if !pkeys.is_empty() && !open {
            let badkeys: Vec<String> = ckeys
                .iter()
                .filter(|ck| !has_key(pval, &Value::str((*ck).clone())))
                .cloned()
                .collect();
            if !badkeys.is_empty() {
                errs_push(
                    inj,
                    format!(
                        "Unexpected keys at field {}{}{}",
                        pathify(&path_value(&path), Some(1), None),
                        S_VIZ,
                        badkeys.join(", ")
                    ),
                );
            }
        } else {
            merge(&Value::list(vec![pval.clone(), cval.clone()]), None);
            if is_node(pval) {
                del_prop(pval.clone(), &Value::str(S_BOPEN));
            }
        }
    } else if is_list(&cval) {
        if !is_list(pval) {
            errs_push(
                inj,
                invalid_type_msg(&path, &type_name(ptype), ctype, &cval),
            );
        }
    } else if exact {
        if &cval != pval {
            let pathmsg = if path.len() > 1 {
                format!(
                    "at field {}{}",
                    pathify(&path_value(&path), Some(1), None),
                    S_VIZ
                )
            } else {
                String::new()
            };
            errs_push(
                inj,
                format!(
                    "Value {}{} should equal {}{}",
                    pathmsg,
                    js_string(&cval),
                    js_string(pval),
                    S_DT
                ),
            );
        }
    } else {
        set_prop(parent.clone(), key, cval.clone());
    }
}

/// `_validatehandler` — `getpath`/`_injectstr` handler installed by `validate`.
fn validatehandler(inj: &Inj, val: &Value, r: &str, store: &Value) -> Value {
    if let Some(caps) = R_META_PATH.captures(r) {
        if &caps[2] == "=" {
            Injection::setval(
                inj,
                Value::list(vec![Value::str(S_BEXACT), val.clone()]),
                None,
            );
        } else {
            Injection::setval(inj, val.clone(), None);
        }
        inj.borrow_mut().key_i = -1;
        return Value::skip();
    }
    inject_handler(inj, val, r, store)
}

pub fn validate(
    data: &Value,
    spec: &Value,
    injdef: Option<&InjectDef>,
) -> Result<Value, StructError> {
    let extra = injdef.and_then(|d| d.extra.clone());
    let collect = injdef.map(|d| d.errs.is_some()).unwrap_or(false);
    let errs = injdef
        .and_then(|d| d.errs.clone())
        .unwrap_or_else(Value::empty_list);

    // build the validator store
    let mut vmap: indexmap::IndexMap<String, Value> = indexmap::IndexMap::new();
    for k in [
        "$DELETE", "$COPY", "$KEY", "$META", "$MERGE", "$EACH", "$PACK",
    ] {
        vmap.insert(k.to_string(), Value::Null);
    }
    vmap.insert("$STRING".to_string(), Value::func(validate_string));
    for k in [
        "$NUMBER",
        "$INTEGER",
        "$DECIMAL",
        "$BOOLEAN",
        "$NULL",
        "$NIL",
        "$MAP",
        "$LIST",
        "$FUNCTION",
        "$INSTANCE",
    ] {
        vmap.insert(k.to_string(), Value::func(validate_type));
    }
    vmap.insert("$ANY".to_string(), Value::func(validate_any));
    vmap.insert("$CHILD".to_string(), Value::func(validate_child));
    vmap.insert("$ONE".to_string(), Value::func(validate_one));
    vmap.insert("$EXACT".to_string(), Value::func(validate_exact));

    let extra_or_empty = match &extra {
        Some(e) => e.clone(),
        None => Value::empty_map(),
    };
    let store = merge(
        &Value::list(vec![
            Value::map(vmap),
            extra_or_empty,
            Value::map_of([(S_DERRS.to_string(), errs.clone())]),
        ]),
        Some(1),
    );

    let meta = match injdef.and_then(|d| d.meta.clone()) {
        Some(m) => m,
        None => Value::empty_map(),
    };
    let exact_cur = get_prop(&meta, &Value::str(S_BEXACT), Value::Bool(false));
    set_prop(meta.clone(), &Value::str(S_BEXACT), exact_cur);

    let td = InjectDef {
        meta: Some(meta),
        extra: Some(store),
        modify: Some(Rc::new(validation_modify) as Modify),
        handler: Some(Rc::new(validatehandler) as NativeFn),
        errs: Some(errs.clone()),
        ..Default::default()
    };

    let out = transform(data, spec, Some(&td)).unwrap_or(Value::Noval);

    let errlen = errs.as_list().map(|l| l.borrow().len()).unwrap_or(0);
    if errlen > 0 && !collect {
        let msgs: Vec<String> = errs
            .as_list()
            .map(|l| l.borrow().iter().map(js_string).collect())
            .unwrap_or_default();
        return Err(StructError {
            message: msgs.join(" | "),
        });
    }

    Ok(out)
}

// ---- select ----------------------------------------------------------

fn js_lt(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => x < y,
        _ => {
            let (x, y) = (js_to_number(a), js_to_number(b));
            x < y // NaN -> false, matches JS
        }
    }
}
fn js_gt(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Str(x), Value::Str(y)) => x > y,
        _ => {
            let (x, y) = (js_to_number(a), js_to_number(b));
            x > y
        }
    }
}

fn select_subvalidate(point: &Value, term: &Value, store: &Value, meta: &Value) -> bool {
    let vstore = match merge(
        &Value::list(vec![Value::empty_map(), store.clone()]),
        Some(1),
    ) {
        v @ Value::Map(_) => v,
        _ => Value::empty_map(),
    };
    set_prop(vstore.clone(), &Value::str(S_DTOP), point.clone());
    let terrs = Value::empty_list();
    let vd = InjectDef {
        extra: Some(vstore),
        errs: Some(terrs.clone()),
        meta: Some(meta.clone()),
        ..Default::default()
    };
    let _ = validate(point, term, Some(&vd));
    terrs
        .as_list()
        .map(|l| l.borrow().is_empty())
        .unwrap_or(true)
}

fn select_and(inj: &Inj, _v: &Value, _r: &str, store: &Value) -> Value {
    if inj.borrow().mode != M_KEYPRE {
        return Value::Noval;
    }
    let (key, parent, path, nodes, meta) = {
        let b = inj.borrow();
        (
            b.key.clone(),
            b.parent.clone(),
            b.path.clone(),
            b.nodes.clone(),
            b.meta.clone(),
        )
    };
    let terms: Vec<Value> = get_prop(&parent, &Value::str(key), Value::Noval)
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    let ppath = slice_str_vec(&path, Some(-1), None);
    let point = get_path_inj(store, &path_value(&ppath), None);
    for term in &terms {
        if !select_subvalidate(&point, term, store, &meta) {
            errs_push(
                inj,
                format!(
                    "AND:{}{}{} fail:{}",
                    pathify(&path_value(&ppath), None, None),
                    S_VIZ,
                    stringify(&point, None, false),
                    stringify(&Value::list(terms.clone()), None, false)
                ),
            );
        }
    }
    let gkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let nlen = nodes.len();
    if nlen >= 2 {
        set_prop(nodes[nlen - 2].clone(), &Value::str(gkey), point);
    }
    Value::Noval
}

fn select_or(inj: &Inj, _v: &Value, _r: &str, store: &Value) -> Value {
    if inj.borrow().mode != M_KEYPRE {
        return Value::Noval;
    }
    let (key, parent, path, nodes, meta) = {
        let b = inj.borrow();
        (
            b.key.clone(),
            b.parent.clone(),
            b.path.clone(),
            b.nodes.clone(),
            b.meta.clone(),
        )
    };
    let terms: Vec<Value> = get_prop(&parent, &Value::str(key), Value::Noval)
        .as_list()
        .map(|l| l.borrow().clone())
        .unwrap_or_default();
    let ppath = slice_str_vec(&path, Some(-1), None);
    let point = get_path_inj(store, &path_value(&ppath), None);
    for term in &terms {
        if select_subvalidate(&point, term, store, &meta) {
            let gkey = path
                .get(path.len().saturating_sub(2))
                .cloned()
                .unwrap_or_default();
            let nlen = nodes.len();
            if nlen >= 2 {
                set_prop(nodes[nlen - 2].clone(), &Value::str(gkey), point);
            }
            return Value::Noval;
        }
    }
    errs_push(
        inj,
        format!(
            "OR:{}{}{} fail:{}",
            pathify(&path_value(&ppath), None, None),
            S_VIZ,
            stringify(&point, None, false),
            stringify(&Value::list(terms.clone()), None, false)
        ),
    );
    Value::Noval
}

fn select_not(inj: &Inj, _v: &Value, _r: &str, store: &Value) -> Value {
    if inj.borrow().mode != M_KEYPRE {
        return Value::Noval;
    }
    let (key, parent, path, nodes, meta) = {
        let b = inj.borrow();
        (
            b.key.clone(),
            b.parent.clone(),
            b.path.clone(),
            b.nodes.clone(),
            b.meta.clone(),
        )
    };
    let term = get_prop(&parent, &Value::str(key), Value::Noval);
    let ppath = slice_str_vec(&path, Some(-1), None);
    let point = get_path_inj(store, &path_value(&ppath), None);
    if select_subvalidate(&point, &term, store, &meta) {
        errs_push(
            inj,
            format!(
                "NOT:{}{}{} fail:{}",
                pathify(&path_value(&ppath), None, None),
                S_VIZ,
                stringify(&point, None, false),
                stringify(&term, None, false)
            ),
        );
    }
    let gkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let nlen = nodes.len();
    if nlen >= 2 {
        set_prop(nodes[nlen - 2].clone(), &Value::str(gkey), point);
    }
    Value::Noval
}

fn select_cmp(inj: &Inj, _v: &Value, r: &str, store: &Value) -> Value {
    if inj.borrow().mode != M_KEYPRE {
        return Value::Noval;
    }
    let (key, parent, path, nodes) = {
        let b = inj.borrow();
        (
            b.key.clone(),
            b.parent.clone(),
            b.path.clone(),
            b.nodes.clone(),
        )
    };
    let term = get_prop(&parent, &Value::str(key), Value::Noval);
    let gkey = path
        .get(path.len().saturating_sub(2))
        .cloned()
        .unwrap_or_default();
    let ppath = slice_str_vec(&path, Some(-1), None);
    let point = get_path_inj(store, &path_value(&ppath), None);

    let pass = match r {
        "$GT" => js_gt(&point, &term),
        "$LT" => js_lt(&point, &term),
        "$GTE" => js_gt(&point, &term) || point == term,
        "$LTE" => js_lt(&point, &term) || point == term,
        "$LIKE" => {
            let pat = term.as_str().unwrap_or("").to_string();
            crate::re::Regex::new(&pat)
                .map(|re| re.is_match(&stringify(&point, None, false)))
                .unwrap_or(false)
        }
        _ => false,
    };

    if pass {
        let nlen = nodes.len();
        if nlen >= 2 {
            set_prop(nodes[nlen - 2].clone(), &Value::str(gkey), point);
        }
    } else {
        errs_push(
            inj,
            format!(
                "CMP: {}{}{} fail:{} {}",
                pathify(&path_value(&ppath), None, None),
                S_VIZ,
                stringify(&point, None, false),
                r,
                stringify(&term, None, false)
            ),
        );
    }
    Value::Noval
}

pub fn select(children: &Value, query: &Value) -> Value {
    if !is_node(children) {
        return Value::empty_list();
    }

    let child_list: Vec<Value> = match children {
        Value::Map(_) => items_vec(children)
            .into_iter()
            .map(|(k, v)| {
                set_prop(v.clone(), &Value::str(S_DKEY), Value::str(k));
                v
            })
            .collect(),
        Value::List(_) => items_vec(children)
            .into_iter()
            .map(|(k, v)| {
                set_prop(
                    v.clone(),
                    &Value::str(S_DKEY),
                    Value::Num(k.parse::<f64>().unwrap_or(f64::NAN)),
                );
                v
            })
            .collect(),
        _ => return Value::empty_list(),
    };

    let extra = Value::map_of([
        ("$AND".to_string(), Value::func(select_and)),
        ("$OR".to_string(), Value::func(select_or)),
        ("$NOT".to_string(), Value::func(select_not)),
        ("$GT".to_string(), Value::func(select_cmp)),
        ("$LT".to_string(), Value::func(select_cmp)),
        ("$GTE".to_string(), Value::func(select_cmp)),
        ("$LTE".to_string(), Value::func(select_cmp)),
        ("$LIKE".to_string(), Value::func(select_cmp)),
    ]);
    let meta = Value::map_of([(S_BEXACT.to_string(), Value::Bool(true))]);

    let q = clone(query);
    let mut open = |_k: &Value, v: &Value, _p: &Value, _t: &[String]| -> Value {
        if is_map(v) {
            let cur = get_prop(v, &Value::str(S_BOPEN), Value::Bool(true));
            set_prop(v.clone(), &Value::str(S_BOPEN), cur);
        }
        v.clone()
    };
    walk(q.clone(), Some(&mut open), None, None);

    let mut results: Vec<Value> = Vec::new();
    for child in &child_list {
        let errs = Value::empty_list();
        let vd = InjectDef {
            errs: Some(errs.clone()),
            meta: Some(meta.clone()),
            extra: Some(extra.clone()),
            ..Default::default()
        };
        let _ = validate(child, &clone(&q), Some(&vd));
        if errs
            .as_list()
            .map(|l| l.borrow().is_empty())
            .unwrap_or(true)
        {
            results.push(child.clone());
        }
    }
    Value::list(results)
}

// keep `Injection::has_handler` referenced (used once staging is complete)
#[allow(dead_code)]
fn _keepalive() {
    let _ = Injection::has_handler(None);
    let _ = inject_child as fn(Value, &Value, &Inj) -> Inj;
}
