// Corpus test runner — drives the shared JSON test corpus
// (../build/test/test.json) against the Rust port. Mirrors
// ts/test/runner.ts + ts/test/utility/StructUtility.test.ts.
//
// Only the implemented subsets are wired here: minor utilities, walk, merge,
// getpath, setpath. inject / transform / validate / select (and the
// top-level `primary` SDK tests) are staged; see rs/NOTES.md.

use std::cell::RefCell;
use std::fs;
use std::path::PathBuf;
use std::rc::Rc;

use serde_json::Value as J;
use voxgig_struct::ordered_map::OrderedMap;

use voxgig_struct::value::Value;
use voxgig_struct::*;

const NULLMARK: &str = "__NULL__";
const UNDEFMARK: &str = "__UNDEF__";
const EXISTSMARK: &str = "__EXISTS__";

// ---- JSON -> Value -----------------------------------------------------

fn j_to_v(j: &J) -> Value {
    match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Number(n) => Value::Num(n.as_f64().unwrap_or(f64::NAN)),
        J::String(s) => Value::Str(s.clone()),
        J::Array(a) => Value::list(a.iter().map(j_to_v).collect()),
        J::Object(o) => {
            let mut m = OrderedMap::new();
            for (k, v) in o.iter() {
                m.insert(k.clone(), j_to_v(v));
            }
            Value::map(m)
        }
    }
}

fn test_json() -> Value {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("..");
    p.push("build");
    p.push("test");
    p.push("test.json");
    let txt = fs::read_to_string(&p).unwrap_or_else(|e| panic!("read {:?}: {e}", p));
    let j: J = serde_json::from_str(&txt).expect("parse test.json");
    j_to_v(&j)
}

// ---- value helpers -----------------------------------------------------

// Raw field extraction from corpus entries: preserves a stored JSON null so a
// field declared `null` (e.g. `in: null`, `{val:null}`) reaches the subject as
// Value::Null and is not silently dropped (Group A null-unification only
// applies to the public get_prop API under test, not to test-harness plumbing).
// Mirrors the canonical TS runner reading entry fields by direct property access.
fn vget(v: &Value, key: &str) -> Value {
    lookup(v, &Value::str(key))
}

fn vget_path(v: &Value, keys: &[&str]) -> Value {
    let mut cur = v.clone();
    for k in keys {
        cur = vget(&cur, k);
    }
    cur
}

fn as_i64_opt(v: &Value) -> Option<i64> {
    match v {
        Value::Num(n) => Some(*n as i64),
        _ => None,
    }
}

fn as_str_opt(v: &Value) -> Option<String> {
    match v {
        Value::Str(s) => Some(s.clone()),
        _ => None,
    }
}

// fixJSON: deep-replace JSON null (and undefined) with NULLMARK (when
// null_flag). Matches `JSON.parse(JSON.stringify(val, replacer))` with the
// null->NULLMARK replacer used by ts/test/runner.ts.
fn fix_json(v: &Value, null_flag: bool) -> Value {
    match v {
        Value::Null | Value::Noval => {
            if null_flag {
                Value::str(NULLMARK)
            } else {
                v.clone()
            }
        }
        Value::List(l) => Value::list(l.borrow().iter().map(|x| fix_json(x, null_flag)).collect()),
        Value::Map(m) => {
            let mut nm = OrderedMap::new();
            for (k, x) in m.borrow().iter() {
                nm.insert(k.clone(), fix_json(x, null_flag));
            }
            Value::map(nm)
        }
        Value::Func(_) => {
            // JSON.stringify drops functions (object key) / -> null (array elem).
            // At the comparison boundary, treat as null-ish.
            if null_flag {
                Value::str(NULLMARK)
            } else {
                Value::Null
            }
        }
        other => other.clone(),
    }
}

// match check for the `match` field of a test entry (substring / regex / etc).
fn matchval(check: &Value, base: &Value) -> bool {
    if check == base {
        return true;
    }
    if let Value::Str(cs) = check {
        let bstr = stringify(base, None, false);
        if let Some(rem) = cs.strip_prefix('/').and_then(|s| s.strip_suffix('/')) {
            if let Ok(re) = voxgig_struct::re::Regex::new(rem) {
                return re.is_match(&bstr);
            }
        }
        return bstr
            .to_lowercase()
            .contains(&stringify(check, None, false).to_lowercase());
    }
    false
}

// ---- the test loop -----------------------------------------------------

struct Run {
    failures: Vec<String>,
    passed: usize,
}

impl Run {
    fn new() -> Self {
        Run {
            failures: Vec::new(),
            passed: 0,
        }
    }

    /// Run a test set: `label` for messages, `null_flag` matches the TS
    /// `flags.null` (`runset` => true, `runsetflags({null:false})` => false),
    /// `subject` takes the (cloned) `vin` and returns the result Value.
    fn run_set<F>(&mut self, set: &Value, null_flag: bool, label: &str, mut subject: F)
    where
        F: FnMut(Value) -> Value,
    {
        let fixed = fix_json(set, null_flag);
        let testset = vget(&fixed, "set");
        let entries = match testset.as_list() {
            Some(l) => l.borrow().clone(),
            None => {
                self.failures.push(format!("{label}: no `set` array"));
                return;
            }
        };
        for (i, entry) in entries.iter().enumerate() {
            // resolveEntry: missing `out` + null_flag => NULLMARK
            let out0 = vget(entry, "out");
            let expected = if out0.is_noval() && null_flag {
                Value::str(NULLMARK)
            } else {
                out0
            };
            let err_expected = vget(entry, "err");
            let match_spec = vget(entry, "match");

            // `vin` = clone(entry.in) (deep). The subject gets a shallow
            // Rc-clone of it, so any in-place mutation it makes (setpath,
            // setprop, …) is visible through `vin` afterwards.
            let vin = clone(&vget(entry, "in"));
            let res = fix_json(&subject(vin.clone()), null_flag);

            if !err_expected.is_noval() {
                self.failures.push(format!(
                    "{label}#{i}: expected error [{}] but got {}",
                    stringify(&err_expected, Some(80), false),
                    stringify(&res, Some(80), false),
                ));
                continue;
            }

            let mut matched = false;
            if !match_spec.is_noval() {
                // base = { in: entry.in (original), args: [vin (post-call)], out: res }
                let mut base = OrderedMap::new();
                base.insert("in".to_string(), vget(entry, "in"));
                base.insert("args".to_string(), Value::list(vec![vin.clone()]));
                base.insert("out".to_string(), res.clone());
                let base = Value::map(base);
                if let Some(why) = match_check(&match_spec, &base) {
                    self.failures.push(format!(
                        "{label}#{i}: match failed ({why}); got {}",
                        stringify(&res, Some(160), false)
                    ));
                    continue;
                }
                matched = true;
            }

            if res == expected {
                self.passed += 1;
                continue;
            }
            if matched
                && (expected == Value::str(NULLMARK) || expected.is_noval() || expected.is_null())
            {
                self.passed += 1;
                continue;
            }

            self.failures.push(format!(
                "{label}#{i}: in={} -> got {}, want {}",
                stringify(&vget(entry, "in"), Some(120), false),
                stringify(&res, Some(120), false),
                stringify(&expected, Some(120), false),
            ));
        }
    }
}

impl Run {
    /// Like `run_set`, but the subject may return `Err(message)` — matched
    /// (substring / regex, case-insensitive) against the entry's `err` field.
    fn run_set_fallible<F>(&mut self, set: &Value, null_flag: bool, label: &str, mut subject: F)
    where
        F: FnMut(Value) -> Result<Value, String>,
    {
        let fixed = fix_json(set, null_flag);
        let testset = vget(&fixed, "set");
        let entries = match testset.as_list() {
            Some(l) => l.borrow().clone(),
            None => {
                self.failures.push(format!("{label}: no `set` array"));
                return;
            }
        };
        for (i, entry) in entries.iter().enumerate() {
            let out0 = vget(entry, "out");
            let expected = if out0.is_noval() && null_flag {
                Value::str(NULLMARK)
            } else {
                out0
            };
            let err_expected = vget(entry, "err");
            let match_spec = vget(entry, "match");
            let vin = clone(&vget(entry, "in"));
            let result = subject(vin.clone());

            match result {
                Err(msg) => {
                    if err_expected.is_noval() {
                        self.failures
                            .push(format!("{label}#{i}: unexpected error: {msg}"));
                        continue;
                    }
                    let want = match &err_expected {
                        Value::Bool(true) => {
                            self.passed += 1;
                            continue;
                        }
                        Value::Str(s) => s.clone(),
                        other => stringify(other, None, false),
                    };
                    let ok = if let Some(rem) =
                        want.strip_prefix('/').and_then(|s| s.strip_suffix('/'))
                    {
                        voxgig_struct::re::Regex::new(rem)
                            .map(|re| re.is_match(&msg))
                            .unwrap_or(false)
                    } else {
                        msg.to_lowercase().contains(&want.to_lowercase())
                    };
                    if ok {
                        self.passed += 1;
                    } else {
                        self.failures.push(format!(
                            "{label}#{i}: error mismatch: got [{}] want [{}]",
                            msg, want
                        ));
                    }
                }
                Ok(v) => {
                    if !err_expected.is_noval() {
                        self.failures.push(format!(
                            "{label}#{i}: expected error [{}] but got value {}",
                            stringify(&err_expected, Some(80), false),
                            stringify(&fix_json(&v, null_flag), Some(80), false)
                        ));
                        continue;
                    }
                    let res = fix_json(&v, null_flag);
                    let mut matched = false;
                    if !match_spec.is_noval() {
                        let mut base = OrderedMap::new();
                        base.insert("in".to_string(), vget(entry, "in"));
                        base.insert("args".to_string(), Value::list(vec![vin.clone()]));
                        base.insert("out".to_string(), res.clone());
                        let base = Value::map(base);
                        if let Some(why) = match_check(&match_spec, &base) {
                            self.failures
                                .push(format!("{label}#{i}: match failed ({why})"));
                            continue;
                        }
                        matched = true;
                    }
                    if res == expected
                        || (matched && (expected == Value::str(NULLMARK) || expected.is_nullish()))
                    {
                        self.passed += 1;
                    } else {
                        self.failures.push(format!(
                            "{label}#{i}: in={} -> got {}, want {}",
                            stringify(&vget(entry, "in"), Some(120), false),
                            stringify(&res, Some(120), false),
                            stringify(&expected, Some(120), false),
                        ));
                    }
                }
            }
        }
    }
}

/// Walk `check`; every leaf must equal/match `getpath(base, path)`. Returns
/// `Some(reason)` on the first mismatch, `None` if all leaves match.
fn match_check(check: &Value, base: &Value) -> Option<String> {
    fn rec(check: &Value, base: &Value, path: &mut Vec<String>) -> Option<String> {
        match check {
            Value::Map(cm) => {
                for (k, cv) in cm.borrow().iter() {
                    path.push(k.clone());
                    let r = rec(cv, base, path);
                    path.pop();
                    if r.is_some() {
                        return r;
                    }
                }
                None
            }
            Value::List(cl) => {
                for (i, cv) in cl.borrow().iter().enumerate() {
                    path.push(i.to_string());
                    let r = rec(cv, base, path);
                    path.pop();
                    if r.is_some() {
                        return r;
                    }
                }
                None
            }
            leaf => {
                let bv = get_path(
                    base,
                    &Value::list(path.iter().cloned().map(Value::Str).collect()),
                    None,
                );
                if leaf == &bv {
                    return None;
                }
                if let Value::Str(s) = leaf {
                    if s == UNDEFMARK && bv.is_noval() {
                        return None;
                    }
                    if s == EXISTSMARK && !bv.is_nullish() {
                        return None;
                    }
                }
                if matchval(leaf, &bv) {
                    return None;
                }
                Some(format!(
                    "{}: {} <=> {}",
                    path.join("."),
                    stringify(leaf, Some(40), false),
                    stringify(&bv, Some(40), false)
                ))
            }
        }
    }
    let mut path = Vec::new();
    rec(check, base, &mut path)
}

// ---- adapters helpers --------------------------------------------------

fn b(v: bool) -> Value {
    Value::Bool(v)
}

fn inject_def_from_value(v: &Value) -> InjectDef {
    let mut d = InjectDef::default();
    if let Value::Map(_) = v {
        let key = vget(v, "key");
        if !key.is_noval() {
            d.key = Some(key);
        }
        let meta = vget(v, "meta");
        if !meta.is_noval() {
            d.meta = Some(meta);
        }
        let base = vget(v, "base");
        if let Value::Str(s) = base {
            d.base = Some(s);
        }
        let dparent = vget(v, "dparent");
        if !dparent.is_noval() {
            d.dparent = Some(dparent);
        }
        let dpath = vget(v, "dpath");
        if let Value::Str(s) = dpath {
            d.dpath = Some(s.split('.').map(|x| x.to_string()).collect());
        } else if let Value::List(l) = &dpath {
            d.dpath = Some(
                l.borrow()
                    .iter()
                    .map(|x| as_str_opt(x).unwrap_or_default())
                    .collect(),
            );
        }
    }
    d
}

// ---- the test -----------------------------------------------------------

#[test]
fn corpus() {
    let spec = test_json();
    let s = vget(&spec, "struct");
    let mut run = Run::new();

    macro_rules! set {
        ($cat:expr, $name:expr) => {
            vget_path(&s, &[$cat, $name])
        };
    }

    // -------- minor --------------------------------------------------
    run.run_set(&set!("minor", "isnode"), true, "minor-isnode", |v| {
        b(is_node(&v))
    });
    run.run_set(&set!("minor", "ismap"), true, "minor-ismap", |v| {
        b(is_map(&v))
    });
    run.run_set(&set!("minor", "islist"), true, "minor-islist", |v| {
        b(is_list(&v))
    });
    run.run_set(&set!("minor", "iskey"), false, "minor-iskey", |v| {
        b(is_key(&v))
    });
    run.run_set(&set!("minor", "strkey"), false, "minor-strkey", |v| {
        Value::str(str_key(v))
    });
    run.run_set(&set!("minor", "isempty"), false, "minor-isempty", |v| {
        b(is_empty(&v))
    });
    run.run_set(&set!("minor", "isfunc"), true, "minor-isfunc", |v| {
        b(is_func(&v))
    });
    run.run_set(&set!("minor", "clone"), false, "minor-clone", |v| clone(&v));
    run.run_set(&set!("minor", "filter"), true, "minor-filter", |vin| {
        let val = vget(&vin, "val");
        let check = as_str_opt(&vget(&vin, "check")).unwrap_or_default();
        filter(&val, move |n| match check.as_str() {
            "gt3" => matches!(&n.1, Value::Num(x) if *x > 3.0),
            "lt3" => matches!(&n.1, Value::Num(x) if *x < 3.0),
            _ => false,
        })
    });
    run.run_set(&set!("minor", "flatten"), true, "minor-flatten", |vin| {
        flatten(&vget(&vin, "val"), as_i64_opt(&vget(&vin, "depth")))
    });
    run.run_set(&set!("minor", "escre"), true, "minor-escre", |v| {
        Value::str(esc_re(&v))
    });
    run.run_set(&set!("minor", "escurl"), true, "minor-escurl", |v| {
        Value::str(esc_url(&v))
    });
    run.run_set(
        &set!("minor", "stringify"),
        true,
        "minor-stringify",
        |vin| {
            let mut val = vget(&vin, "val");
            if val == Value::str(NULLMARK) {
                val = Value::str("null");
            }
            Value::str(stringify(&val, as_i64_opt(&vget(&vin, "max")), false))
        },
    );
    run.run_set(&set!("minor", "jsonify"), false, "minor-jsonify", |vin| {
        let flags_v = vget(&vin, "flags");
        let flags = if flags_v.is_noval() {
            None
        } else {
            let indent = as_i64_opt(&vget(&flags_v, "indent")).unwrap_or(2).max(0) as usize;
            let offset = as_i64_opt(&vget(&flags_v, "offset")).unwrap_or(0).max(0) as usize;
            Some(JsonFlags { indent, offset })
        };
        Value::str(jsonify(&vget(&vin, "val"), flags.as_ref()))
    });
    run.run_set(&set!("minor", "pathify"), true, "minor-pathify", |vin| {
        let pathv = vget(&vin, "path");
        let path = if pathv == Value::str(NULLMARK) {
            Value::Noval
        } else {
            pathv.clone()
        };
        let mut ps = pathify(&path, as_i64_opt(&vget(&vin, "from")), None);
        ps = ps.replace("__NULL__.", "");
        if pathv == Value::str(NULLMARK) {
            ps = ps.replace('>', ":null>");
        }
        Value::str(ps)
    });
    run.run_set(&set!("minor", "items"), true, "minor-items", |v| items(&v));
    run.run_set(&set!("minor", "getelem"), false, "minor-getelem", |vin| {
        let alt = vget(&vin, "alt");
        get_elem(&vget(&vin, "val"), &vget(&vin, "key"), alt)
    });
    run.run_set(&set!("minor", "getprop"), false, "minor-getprop", |vin| {
        let alt = vget(&vin, "alt");
        get_prop(&vget(&vin, "val"), &vget(&vin, "key"), alt)
    });
    run.run_set(&set!("minor", "setprop"), true, "minor-setprop", |vin| {
        set_prop(vget(&vin, "parent"), &vget(&vin, "key"), vget(&vin, "val"))
    });
    run.run_set(&set!("minor", "delprop"), true, "minor-delprop", |vin| {
        del_prop(vget(&vin, "parent"), &vget(&vin, "key"))
    });
    run.run_set(&set!("minor", "haskey"), false, "minor-haskey", |vin| {
        b(has_key(&vget(&vin, "src"), &vget(&vin, "key")))
    });
    run.run_set(&set!("minor", "keysof"), true, "minor-keysof", |v| {
        keys_of(&v)
    });
    run.run_set(&set!("minor", "join"), false, "minor-join", |vin| {
        let val = vget(&vin, "val");
        let sep = as_str_opt(&vget(&vin, "sep"));
        let url = matches!(vget(&vin, "url"), Value::Bool(true));
        Value::str(join(&val, sep.as_deref(), url))
    });
    run.run_set(&set!("minor", "typename"), true, "minor-typename", |v| {
        Value::str(type_name(v.as_num().unwrap_or(0.0) as i64))
    });
    run.run_set(&set!("minor", "typify"), false, "minor-typify", |v| {
        Value::Num(typify(&v) as f64)
    });
    run.run_set(&set!("minor", "size"), false, "minor-size", |v| {
        Value::Num(size(&v) as f64)
    });
    run.run_set(&set!("minor", "slice"), false, "minor-slice", |vin| {
        slice(
            vget(&vin, "val"),
            as_i64_opt(&vget(&vin, "start")),
            as_i64_opt(&vget(&vin, "end")),
            false,
        )
    });
    run.run_set(&set!("minor", "pad"), false, "minor-pad", |vin| {
        Value::str(pad(
            vget(&vin, "val"),
            as_i64_opt(&vget(&vin, "pad")),
            as_str_opt(&vget(&vin, "char")),
        ))
    });
    run.run_set(&set!("minor", "setpath"), false, "minor-setpath", |vin| {
        set_path(
            &vget(&vin, "store"),
            &vget(&vin, "path"),
            vget(&vin, "val"),
            None,
        )
    });

    // -------- sentinels (Group A null-unification; UNDEF_SPEC.md) ----
    // null_flag is false so a literal JSON null survives into the subject
    // (these tests exercise getprop/getelem/haskey/isempty/isnode/stringify
    // against stored null directly; mirrors perl/t/struct.t sentinels block).
    run.run_set(
        &set!("sentinels", "getprop_unify"),
        false,
        "sentinels-getprop_unify",
        |vin| {
            let alt = vget(&vin, "alt");
            get_prop(&vget(&vin, "val"), &vget(&vin, "key"), alt)
        },
    );
    run.run_set(
        &set!("sentinels", "getelem_absent"),
        false,
        "sentinels-getelem_absent",
        |vin| {
            let alt = vget(&vin, "alt");
            get_elem(&vget(&vin, "val"), &vget(&vin, "key"), alt)
        },
    );
    run.run_set(
        &set!("sentinels", "haskey_unify"),
        false,
        "sentinels-haskey_unify",
        |vin| b(has_key(&vget(&vin, "val"), &vget(&vin, "key"))),
    );
    run.run_set(
        &set!("sentinels", "isempty_unify"),
        false,
        "sentinels-isempty_unify",
        |v| b(is_empty(&v)),
    );
    run.run_set(
        &set!("sentinels", "isnode_unify"),
        false,
        "sentinels-isnode_unify",
        |v| b(is_node(&v)),
    );
    run.run_set(
        &set!("sentinels", "stringify_null"),
        false,
        "sentinels-stringify_null",
        |v| Value::str(stringify(&v, None, false)),
    );

    // -------- walk ---------------------------------------------------
    run.run_set(&set!("walk", "basic"), true, "walk-basic", |vin| {
        let mut walkpath = |_k: &Value, val: &Value, _p: &Value, path: &[String]| -> Value {
            match val {
                Value::Str(sv) => Value::str(format!("{}~{}", sv, path.join("."))),
                _ => val.clone(),
            }
        };
        walk(vin, Some(&mut walkpath), None, None)
    });
    // walk.log — three runs (after-only / before-only / both) of a logging callback.
    {
        let log_spec = vget_path(&s, &["walk", "log"]);
        let input = clone(&vget(&log_spec, "in"));
        let want = vget(&log_spec, "out");
        let mk_log = |inp: &Value, before: bool, after: bool| -> Value {
            let lines = Rc::new(RefCell::new(Vec::<Value>::new()));
            let lc = lines.clone();
            let mut cb = move |k: &Value, v: &Value, p: &Value, path: &[String]| -> Value {
                lc.borrow_mut().push(Value::str(format!(
                    "k={}, v={}, p={}, t={}",
                    stringify(k, None, false),
                    stringify(v, None, false),
                    stringify(p, None, false),
                    pathify(
                        &Value::list(path.iter().cloned().map(Value::Str).collect()),
                        None,
                        None
                    ),
                )));
                v.clone()
            };
            let mut cb2 = {
                let lc = lines.clone();
                move |k: &Value, v: &Value, p: &Value, path: &[String]| -> Value {
                    lc.borrow_mut().push(Value::str(format!(
                        "k={}, v={}, p={}, t={}",
                        stringify(k, None, false),
                        stringify(v, None, false),
                        stringify(p, None, false),
                        pathify(
                            &Value::list(path.iter().cloned().map(Value::Str).collect()),
                            None,
                            None
                        ),
                    )));
                    v.clone()
                }
            };
            let _ = walk(
                clone(inp),
                if before { Some(&mut cb) } else { None },
                if after { Some(&mut cb2) } else { None },
                None,
            );
            let out = Value::list(lines.borrow().clone());
            out
        };
        for (label, b, a) in [
            ("after", false, true),
            ("before", true, false),
            ("both", true, true),
        ] {
            let got = mk_log(&input, b, a);
            let exp = vget(&want, label);
            if got == exp {
                run.passed += 1;
            } else {
                run.failures.push(format!(
                    "walk-log/{label}: got {}, want {}",
                    stringify(&got, Some(220), false),
                    stringify(&exp, Some(220), false)
                ));
            }
        }
    }
    // walk.depth — reconstruct `src` truncated at `maxdepth`.
    run.run_set(&set!("walk", "depth"), false, "walk-depth", |vin| {
        let top: Rc<RefCell<Value>> = Rc::new(RefCell::new(Value::Noval));
        let cur: Rc<RefCell<Value>> = Rc::new(RefCell::new(Value::Noval));
        let (t, c) = (top.clone(), cur.clone());
        let mut copy = move |k: &Value, val: &Value, _p: &Value, _path: &[String]| -> Value {
            if k.is_noval() || matches!(val, Value::List(_) | Value::Map(_)) {
                let child = if matches!(val, Value::List(_)) {
                    Value::empty_list()
                } else {
                    Value::empty_map()
                };
                if k.is_noval() {
                    *t.borrow_mut() = child.clone();
                    *c.borrow_mut() = child;
                } else {
                    let curv = c.borrow().clone();
                    set_prop(curv, k, child.clone());
                    *c.borrow_mut() = child;
                }
            } else {
                let curv = c.borrow().clone();
                set_prop(curv, k, val.clone());
            }
            val.clone()
        };
        let _ = walk(
            vget(&vin, "src"),
            Some(&mut copy),
            None,
            as_i64_opt(&vget(&vin, "maxdepth")),
        );
        let r = top.borrow().clone();
        r
    });
    // walk.copy — deep-copy via a depth-indexed scratch list.
    run.run_set(&set!("walk", "copy"), true, "walk-copy", |vin| {
        let cur: Rc<RefCell<Vec<Value>>> = Rc::new(RefCell::new(Vec::new()));
        let c = cur.clone();
        let mut walkcopy = move |k: &Value, val: &Value, _p: &Value, path: &[String]| -> Value {
            if k.is_noval() {
                let head = match val {
                    Value::Map(_) => Value::empty_map(),
                    Value::List(_) => Value::empty_list(),
                    other => other.clone(),
                };
                *c.borrow_mut() = vec![head];
                return val.clone();
            }
            let i = path.len();
            let mut v = val.clone();
            if matches!(val, Value::List(_) | Value::Map(_)) {
                v = if is_map(val) {
                    Value::empty_map()
                } else {
                    Value::empty_list()
                };
                let mut cb = c.borrow_mut();
                while cb.len() <= i {
                    cb.push(Value::Noval);
                }
                cb[i] = v.clone();
            }
            let parent_copy = c
                .borrow()
                .get(i.saturating_sub(1))
                .cloned()
                .unwrap_or(Value::Noval);
            set_prop(parent_copy, k, v);
            val.clone()
        };
        let _ = walk(vin, Some(&mut walkcopy), None, None);
        let r = cur.borrow().first().cloned().unwrap_or(Value::Noval);
        r
    });

    // -------- merge --------------------------------------------------
    for name in ["cases", "array", "integrity"] {
        run.run_set(
            &set!("merge", name),
            true,
            &format!("merge-{name}"),
            |vin| merge(&vin, None),
        );
    }
    run.run_set(&set!("merge", "depth"), true, "merge-depth", |vin| {
        merge(&vget(&vin, "val"), as_i64_opt(&vget(&vin, "depth")))
    });
    // merge.basic is a single { in, out } object (not a `set`); handle inline.
    {
        let mb = vget(&s, "merge");
        let basic = vget(&mb, "basic");
        let bin = clone(&vget(&basic, "in"));
        let bout = fix_json(&vget(&basic, "out"), true);
        let got = fix_json(&merge(&bin, None), true);
        if got == bout {
            run.passed += 1;
        } else {
            run.failures.push(format!(
                "merge-basic: got {}, want {}",
                stringify(&got, Some(200), false),
                stringify(&bout, Some(200), false)
            ));
        }
    }

    // -------- getpath ------------------------------------------------
    run.run_set(&set!("getpath", "basic"), true, "getpath-basic", |vin| {
        get_path(&vget(&vin, "store"), &vget(&vin, "path"), None)
    });
    run.run_set(
        &set!("getpath", "relative"),
        true,
        "getpath-relative",
        |vin| {
            let dpath = match vget(&vin, "dpath") {
                Value::Str(dp) => Some(dp.split('.').map(|x| x.to_string()).collect()),
                _ => None,
            };
            let d = InjectDef {
                dparent: Some(vget(&vin, "dparent")),
                dpath,
                ..Default::default()
            };
            get_path(&vget(&vin, "store"), &vget(&vin, "path"), Some(&d))
        },
    );
    run.run_set(
        &set!("getpath", "special"),
        true,
        "getpath-special",
        |vin| {
            let d = inject_def_from_value(&vget(&vin, "inj"));
            get_path(&vget(&vin, "store"), &vget(&vin, "path"), Some(&d))
        },
    );
    run.run_set(
        &set!("getpath", "handler"),
        true,
        "getpath-handler",
        |vin| {
            // getpath({ $TOP: store, $FOO: () => 'foo' }, path, { handler: (_inj, val) => val() })
            let store_inner = vget(&vin, "store");
            let mut topmap = OrderedMap::new();
            topmap.insert("$TOP".to_string(), store_inner);
            topmap.insert(
                "$FOO".to_string(),
                Value::func(|_inj: &Inj, _v: &Value, _r: &str, _st: &Value| Value::str("foo")),
            );
            let store = Value::map(topmap);
            let handler: NativeFn =
                Rc::new(|inj: &Inj, val: &Value, _r: &str, st: &Value| -> Value {
                    match val {
                        Value::Func(f) => f(inj, &Value::Noval, "", st),
                        other => other.clone(),
                    }
                });
            let d = InjectDef {
                handler: Some(handler),
                ..Default::default()
            };
            get_path(&store, &vget(&vin, "path"), Some(&d))
        },
    );

    // -------- inject -------------------------------------------------
    {
        // inject.basic is a single { in: {val, store}, out } object.
        let basic = vget_path(&s, &["inject", "basic"]);
        let bin = vget(&basic, "in");
        let bout = fix_json(&vget(&basic, "out"), true);
        let got = fix_json(
            &inject(
                clone(&vget(&bin, "val")),
                &clone(&vget(&bin, "store")),
                None,
            ),
            true,
        );
        if got == bout {
            run.passed += 1;
        } else {
            run.failures.push(format!(
                "inject-basic: got {}, want {}",
                stringify(&got, Some(200), false),
                stringify(&bout, Some(200), false)
            ));
        }
    }
    run.run_set(&set!("inject", "string"), true, "inject-string", |vin| {
        let null_mod: Modify = Rc::new(
            |val: &Value, key: &Value, parent: &Value, _inj: &Inj, _store: &Value| {
                if let Value::Str(svv) = val {
                    if svv == NULLMARK {
                        set_prop(parent.clone(), key, Value::Null);
                    } else {
                        set_prop(
                            parent.clone(),
                            key,
                            Value::str(svv.replace(NULLMARK, "null")),
                        );
                    }
                }
            },
        );
        let d = InjectDef {
            modify: Some(null_mod),
            ..Default::default()
        };
        inject(vget(&vin, "val"), &vget(&vin, "store"), Some(&d))
    });
    run.run_set(&set!("inject", "deep"), true, "inject-deep", |vin| {
        inject(vget(&vin, "val"), &vget(&vin, "store"), None)
    });

    // -------- transform ---------------------------------------------
    {
        let basic = vget_path(&s, &["transform", "basic"]);
        let bin = vget(&basic, "in");
        let bout = fix_json(&vget(&basic, "out"), true);
        let got = match transform(
            &clone(&vget(&bin, "data")),
            &clone(&vget(&bin, "spec")),
            None,
        ) {
            Ok(v) => fix_json(&v, true),
            Err(e) => Value::str(format!("ERR:{}", e)),
        };
        if got == bout {
            run.passed += 1;
        } else {
            run.failures.push(format!(
                "transform-basic: got {}, want {}",
                stringify(&got, Some(200), false),
                stringify(&bout, Some(200), false)
            ));
        }
    }
    for (name, null_flag) in [
        ("paths", true),
        ("cmds", true),
        ("ref", true),
        ("each", true),
        ("pack", true),
        ("format", false),
        ("apply", true),
    ] {
        run.run_set_fallible(
            &set!("transform", name),
            null_flag,
            &format!("transform-{name}"),
            |vin| transform(&vget(&vin, "data"), &vget(&vin, "spec"), None).map_err(|e| e.message),
        );
    }
    run.run_set(
        &set!("transform", "modify"),
        true,
        "transform-modify",
        |vin| {
            let m: Modify = Rc::new(
                |val: &Value, key: &Value, parent: &Value, _inj: &Inj, _store: &Value| {
                    if let Value::Str(svv) = val {
                        set_prop(parent.clone(), key, Value::str(format!("@{svv}")));
                    }
                },
            );
            let d = InjectDef {
                modify: Some(m),
                ..Default::default()
            };
            match transform(&vget(&vin, "data"), &vget(&vin, "spec"), Some(&d)) {
                Ok(v) => v,
                Err(_) => Value::Noval,
            }
        },
    );

    // -------- validate -----------------------------------------------
    for name in ["basic", "invalid"] {
        run.run_set_fallible(
            &set!("validate", name),
            false,
            &format!("validate-{name}"),
            |vin| validate(&vget(&vin, "data"), &vget(&vin, "spec"), None).map_err(|e| e.message),
        );
    }
    for name in ["child", "one", "exact"] {
        run.run_set_fallible(
            &set!("validate", name),
            true,
            &format!("validate-{name}"),
            |vin| validate(&vget(&vin, "data"), &vget(&vin, "spec"), None).map_err(|e| e.message),
        );
    }
    run.run_set_fallible(
        &set!("validate", "special"),
        true,
        "validate-special",
        |vin| {
            let d = inject_def_from_value(&vget(&vin, "inj"));
            validate(&vget(&vin, "data"), &vget(&vin, "spec"), Some(&d)).map_err(|e| e.message)
        },
    );

    // -------- select -------------------------------------------------
    for name in ["basic", "operators", "edge", "alts"] {
        run.run_set(
            &set!("select", name),
            true,
            &format!("select-{name}"),
            |vin| select(&vget(&vin, "obj"), &vget(&vin, "query")),
        );
    }

    // -------- primary / SDK ------------------------------------------
    // A tiny mock SDK (mirrors ts/test/sdk.ts): check(ctx) ->
    //   { zed: 'ZED' + (opts.foo ?? '') + '_' + (ctx.meta?.bar ?? '0') }
    fn sdk_check(opts: &Value, ctx: &Value) -> Value {
        let foo = get_prop(opts, &Value::str("foo"), Value::Noval);
        let foo_s = if foo.is_nullish() {
            String::new()
        } else {
            voxgig_struct::value::js_string(&foo)
        };
        let bar = get_path(ctx, &Value::str("meta.bar"), None);
        let bar_s = if bar.is_nullish() {
            "0".to_string()
        } else {
            voxgig_struct::value::js_string(&bar)
        };
        Value::map_of([("zed".to_string(), Value::str(format!("ZED{foo_s}_{bar_s}")))])
    }
    {
        let check = vget_path(&spec, &["primary", "check"]);
        // resolve clients from DEF.client (options are inject()'d against {} — a no-op here)
        let def_clients = vget_path(&check, &["DEF", "client"]);
        let mut clients: OrderedMap<Value> = OrderedMap::new();
        if let Value::Map(m) = &def_clients {
            for (cn, cdef) in m.borrow().iter() {
                let opts = vget_path(cdef, &["test", "options"]);
                let opts = inject(clone(&opts), &Value::empty_map(), None);
                clients.insert(cn.clone(), opts);
            }
        }
        let basic = vget(&check, "basic");
        let testset = vget(&basic, "set");
        if let Some(l) = testset.as_list() {
            for (i, entry) in l.borrow().iter().enumerate() {
                let ctx = vget(entry, "ctx");
                let client = vget(entry, "client");
                let opts = match &client {
                    Value::Str(c) => clients.get(c).cloned().unwrap_or(Value::empty_map()),
                    _ => Value::empty_map(),
                };
                let res = fix_json(&sdk_check(&opts, &ctx), true);
                let want = fix_json(&vget(entry, "out"), true);
                if res == want {
                    run.passed += 1;
                } else {
                    run.failures.push(format!(
                        "check-basic#{i}: got {}, want {}",
                        stringify(&res, Some(120), false),
                        stringify(&want, Some(120), false)
                    ));
                }
            }
        }
    }

    // -------- report -------------------------------------------------
    if !run.failures.is_empty() {
        let n = run.failures.len();
        let mut msg = format!("\n{} corpus check(s) failed ({} passed):\n", n, run.passed);
        for f in run.failures.iter().take(60) {
            msg.push_str("  - ");
            msg.push_str(f);
            msg.push('\n');
        }
        if n > 60 {
            msg.push_str(&format!("  ... and {} more\n", n - 60));
        }
        panic!("{msg}");
    }
    eprintln!("corpus: {} checks passed", run.passed);
}

// Function values embedded in data: `get_elem` with a callable `alt`, and
// `$APPLY` / a user `$FORMAT` formatter — see rs/README.md "Function values".
#[test]
fn function_values() {
    // get_elem: absent element + callable alt -> alt is invoked
    assert_eq!(
        get_elem(
            &Value::empty_list(),
            &Value::Num(1.0),
            Value::func(|_i: &Inj, _v: &Value, _r: &str, _s: &Value| Value::Num(2.0)),
        ),
        Value::Num(2.0)
    );
    // present element wins over the callable alt
    assert_eq!(
        get_elem(
            &Value::list(vec![Value::Num(9.0)]),
            &Value::Num(0.0),
            Value::func(|_i: &Inj, _v: &Value, _r: &str, _s: &Value| Value::Num(2.0)),
        ),
        Value::Num(9.0)
    );

    // $APPLY: ['`$APPLY`', applyFn, child] — applyFn called with (inj, val=resolved, "", store)
    let spec = Value::list(vec![
        Value::str("`$APPLY`"),
        Value::func(|_i: &Inj, v: &Value, _r: &str, _s: &Value| {
            // v is the resolved child; double a number
            match v {
                Value::Num(n) => Value::Num(n * 2.0),
                other => other.clone(),
            }
        }),
        Value::Num(21.0),
    ]);
    let out = transform(&Value::empty_map(), &spec, None).unwrap();
    assert_eq!(out, Value::Num(42.0));

    // $FORMAT with a user function: applied per node, receives (inj, val, "", store)
    let spec = Value::list(vec![
        Value::str("`$FORMAT`"),
        Value::func(|_i: &Inj, v: &Value, _r: &str, _s: &Value| match v {
            Value::Str(s) => Value::str(format!("[{s}]")),
            other => other.clone(),
        }),
        Value::str("hi"),
    ]);
    let out = transform(&Value::empty_map(), &spec, None).unwrap();
    assert_eq!(out, Value::str("[hi]"));
}

// quiet unused-import warnings for the staged bits
#[allow(dead_code)]
fn _unused() {
    let _ = (UNDEFMARK, EXISTSMARK);
    let _ = Rc::new(RefCell::new(0));
    let _ = Value::Noval;
}
