
use std::cell::RefCell;
use std::rc::Rc;

use voxgig_omni::json::Json;
use voxgig_omni::runner::{make_runner, Flags, Provider, RunPack, SpecRef, Subject, SubjectArgs};
use voxgig_struct::ordered_map::OrderedMap;
use voxgig_struct::value::Value;


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

    pub fn check(sdkcheck: SdkCheck) -> Self {
        Self::section("check", checkprovider(sdkcheck, Value::empty_map()))
    }

    fn section(name: &str, prov: Provider) -> Self {
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
