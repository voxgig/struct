// The shared test runner comes from voxgig/omni, consumed as a local
// checkout - omni is deliberately not published to crates.io (yet).
//
// Rust resolves a path dependency at BUILD time from a literal string in
// Cargo.toml, so unlike the other ports the checkout cannot be found from
// $OMNI_HOME at run time. `Cargo.toml` names `../.omni/rust`, and `.omni` is
// a gitignored link to the checkout that `make setup-omni` creates from
// $OMNI_HOME. CI checks omni out to that path directly and needs no link at
// all. This is the same shape as go's generated `go.work`, which is
// gitignored for the same reason.
//
// It is a DEV-dependency: `cargo build` and anything published from `src/`
// never see omni - register 4.13.
//
// ---------------------------------------------------------------------------
// Why there is no omni-side shim for Rust
// ---------------------------------------------------------------------------
//
// Every other port's shim lives in omni (`go/compat/struct`, `php/compat`,
// ...) and reaches the library under test dynamically - by duck typing, or by
// reflection in go's case. Rust has neither. A shim in omni would have to
// name `voxgig_struct::Value` in its signatures, which would make omni depend
// on the library it exists to check.
//
// So the bridge lives HERE, on the consumer side, and omni's runner is driven
// directly through its `Provider` - which is already closure-based and needs
// nothing named. That is the portable answer for any statically-typed port
// without reflection: rust, and c/cpp/zig when their turn comes.

use std::cell::RefCell;
use std::rc::Rc;

use voxgig_omni::json::Json;
use voxgig_omni::runner::{make_runner, Flags, Provider, RunPack, SpecRef, Subject, SubjectArgs};
use voxgig_struct::ordered_map::OrderedMap;
use voxgig_struct::value::Value;

// ---------------------------------------------------------------------------
// The two value models
// ---------------------------------------------------------------------------

/// omni's model -> struct's.
///
/// `Json::Absent` becomes `Value::Noval`, which is this port's own no-value
/// and already typifies distinctly from `Value::Null` - so unlike go and lua,
/// nothing has to be invented for the corpus's seventeen no-argument entries
/// (register 4.12).
pub fn tostruct(j: &Json) -> Value {
    match j {
        Json::Absent => Value::Noval,
        Json::Null => Value::Null,
        Json::Bool(b) => Value::Bool(*b),
        Json::Num(n) => Value::Num(*n),
        Json::Str(s) => Value::Str(s.clone()),
        Json::List(items) => Value::list(items.iter().map(tostruct).collect()),
        Json::Map(entries) => {
            let mut map = OrderedMap::new();
            for (key, val) in entries.iter() {
                map.insert(key.clone(), tostruct(val));
            }
            Value::map(map)
        }
    }
}

/// struct's model -> omni's.
///
/// `Value::Func` has no JSON shape at all. It reaches here only when a corpus
/// entry puts a callable in data (`get_elem` with a callable `alt`, `$APPLY`),
/// and in every such case the corpus asserts on what the call RETURNED, not on
/// the callable. `Json::Absent` is the honest answer: it is what omni's own
/// model says about a value that is not JSON.
///
/// KEY ORDER. omni models a map as a `BTreeMap`, which sorts; this port's
/// `OrderedMap` preserves insertion order. Every one of the 5503 maps in the
/// shared corpus is already in sorted key order, so nothing is reordered
/// today - but an out-of-order map authored later WOULD be, silently, and
/// this is the only place that could notice.
pub fn toomni(v: &Value) -> Json {
    match v {
        Value::Noval => Json::Absent,
        Value::Null => Json::Null,
        Value::Bool(b) => Json::Bool(*b),
        Value::Num(n) => Json::Num(*n),
        Value::Str(s) => Json::Str(s.clone()),
        Value::List(items) => Json::List(items.borrow().iter().map(toomni).collect()),
        Value::Map(entries) => {
            let mut map = std::collections::BTreeMap::new();
            for (key, val) in entries.borrow().iter() {
                map.insert(key.clone(), toomni(val));
            }
            Json::Map(map)
        }
        Value::Func(_) => Json::Absent,
        Value::Sentinel(_) => Json::Absent,
    }
}

// ---------------------------------------------------------------------------
// struct's runner API, backed by omni
// ---------------------------------------------------------------------------

/// The SDK's `check` subject: `(client options, ctx) -> result`.
pub type SdkCheck = Rc<dyn Fn(&Value, &Value) -> Value>;

/// The corpus, as omni loaded it. Groups are indexed out of this and handed
/// straight back to omni, so the runner and the test file cannot disagree
/// about what the corpus says.
pub struct Run {
    pack: RunPack,
    pub spec: Json,
    pub failures: Vec<String>,
    pub passed: usize,
}

impl Run {
    /// A runner over the `struct` section of the shared corpus.
    pub fn new() -> Self {
        Self::section("struct", provider())
    }

    /// A runner over the `check` section - the client group - with a provider
    /// that resolves the subject by name and mints a sub-client per
    /// `DEF.client` entry. This port used to hand-roll that resolution itself,
    /// about thirty lines of it; omni already does it, and does it the way
    /// every other port's does.
    pub fn check(sdkcheck: SdkCheck) -> Self {
        Self::section("check", checkprovider(sdkcheck, Value::empty_map()))
    }

    fn section(name: &str, prov: Provider) -> Self {
        // `CARGO_MANIFEST_DIR` is `rust/corpus`, so the repository root is two
        // levels up - this harness is a package of its own (see Cargo.toml).
        let mut path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        path.push("..");
        path.push("..");
        path.push("build");
        path.push("test");
        path.push("test.json");

        let runner = make_runner(SpecRef::Path(path.to_string_lossy().into_owned()), prov)
            .unwrap_or_else(|e| panic!("omni: {}", e.message));
        let pack = runner
            .runner(name, None)
            .unwrap_or_else(|e| panic!("omni: {}", e.message));

        Run {
            spec: pack.spec.clone(),
            pack,
            failures: Vec::new(),
            passed: 0,
        }
    }

    /// Run one set of entries whose subject cannot fail.
    pub fn run_set<F>(&mut self, set: &Json, nullflag: bool, label: &str, subject: F)
    where
        F: FnMut(Value) -> Value + 'static,
    {
        let cell = Rc::new(RefCell::new(subject));
        self.drive(set, nullflag, label, move |args: &mut [Json]| {
            let input = tostruct(args.first().unwrap_or(&Json::Absent));
            let result = (cell.borrow_mut())(input.clone());

            // struct's functions MUTATE the node they are given - `setpath`
            // rewrites the store in place - and the corpus checks it through
            // `match.args`. The conversion above handed the subject a COPY, so
            // the mutation has to be written back into omni's own argument.
            // Eight of `minor/setpath`'s nine entries turn on this.
            if let Some(first) = args.first_mut() {
                *first = toomni(&input);
            }

            Ok(toomni(&result))
        });
    }

    /// Run one set of entries whose subject may return an error, which the
    /// corpus can then assert on with `err`.
    pub fn run_set_fallible<F>(&mut self, set: &Json, nullflag: bool, label: &str, subject: F)
    where
        F: FnMut(Value) -> Result<Value, String> + 'static,
    {
        let cell = Rc::new(RefCell::new(subject));
        self.drive(set, nullflag, label, move |args: &mut [Json]| {
            let input = tostruct(args.first().unwrap_or(&Json::Absent));
            let result = (cell.borrow_mut())(input.clone());
            if let Some(first) = args.first_mut() {
                *first = toomni(&input);
            }
            result.map(|v| toomni(&v))
        });
    }

    /// Run one set against the subject the SPEC names, resolved through the
    /// provider. This is the client path - `DEF.client`, and an entry's own
    /// `client` key - and it is the only way to exercise it.
    pub fn run_set_named(&mut self, set: &Json, nullflag: bool, label: &str) {
        let flags = Flags {
            null: nullflag,
            name: Some(label.to_string()),
        };
        let before = entrycount(set);
        match self.pack.runsetflags(set, &flags, None) {
            Ok(()) => self.passed += before,
            Err(err) => self.failures.push(err.message.replace('\n', " | ")),
        }
    }

    /// Hand one group to omni and record the outcome.
    ///
    /// Failures are ACCUMULATED rather than raised, because this port reports
    /// the whole corpus in one panic at the end - one run tells you every
    /// broken entry, not just the first. omni raises on the first failure in a
    /// group, so a group stops at its first bad entry; that is the one
    /// behaviour difference the swap introduces, and it only affects how much
    /// detail a failing run prints.
    fn drive<F>(&mut self, set: &Json, nullflag: bool, label: &str, subject: F)
    where
        F: Fn(&mut [Json]) -> Result<Json, String> + 'static,
    {
        let flags = Flags {
            null: nullflag,
            name: Some(label.to_string()),
        };
        let subject: SubjectArgs = Rc::new(subject);

        let before = entrycount(set);
        match self.pack.runsetflags_args(set, &flags, &subject) {
            Ok(()) => self.passed += before,
            Err(err) => self.failures.push(err.message.replace('\n', " | ")),
        }
    }
}

impl Default for Run {
    fn default() -> Self {
        Self::new()
    }
}

/// How many entries a group declares.
fn entrycount(set: &Json) -> usize {
    set.get("set").aslist().map(|l| l.len()).unwrap_or(0)
}

/// The `struct` section drives every group with a subject the test file
/// supplies, so this provider's hooks are never reached. It exists because
/// omni asks for one.
fn provider() -> Provider {
    Provider {
        subject: None,
        client: None,
        contextify: None,
        inject: None,
    }
}

/// The `check` section's provider: the SDK, wearing omni's shape.
///
/// `options` is what a `DEF.client` entry carried, already injected against
/// the store by omni. The default client has none, and answers "ZED_BAR0".
fn checkprovider(sdkcheck: SdkCheck, options: Value) -> Provider {
    let forsubject = Rc::clone(&sdkcheck);
    let opts = options.clone();

    Provider {
        subject: Some(Rc::new(move |name: &str| {
            if "check" != name {
                return None;
            }
            let call = Rc::clone(&forsubject);
            let opts = opts.clone();
            let subject: Subject = Rc::new(move |args: &[Json]| {
                let ctx = tostruct(args.first().unwrap_or(&Json::Absent));
                Ok(toomni(&call(&opts, &ctx)))
            });
            Some(subject)
        })),

        // A DEF.client entry becomes another provider carrying its options.
        client: Some(Rc::new(move |clientopts: &Json| {
            checkprovider(Rc::clone(&sdkcheck), tostruct(clientopts))
        })),

        // This port adds nothing to a context; the hook must exist so omni
        // installs `client` on it.
        contextify: Some(Rc::new(|val: Json| val)),

        inject: None,
    }
}
