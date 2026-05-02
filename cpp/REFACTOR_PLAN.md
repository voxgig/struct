# C++ Struct Refactor Plan — TS Parity

## Context

The C++ port at `/home/user/struct/cpp/src/voxgig_struct.hpp` (781 lines,
header-only) is the most incomplete port in the monorepo. It exposes
~18 of 40 canonical functions, has no `getpath`/`setpath`/`inject`/
`transform`/`validate`/`select` machinery, and does not currently
compile with modern g++ (`(1<<31)-1` overflow on signed int).

It uses `nlohmann::json` as the value type and an awkward dispatch
convention — every function takes `args_container&&` (a
`std::vector<nlohmann::json>`) instead of typed parameters — to
emulate the dynamic argument lists used by the test runner. Function
values are stored by **`reinterpret_cast`-ing an `intptr_t` into a JSON
integer**, which is undefined behaviour the moment the JSON is cloned,
serialised, or moved across translation units.

The corpus runner at `tests/runner.hpp` (334 lines) loads
`build/test/test.json` but only drives ~17 minor tests; the major
subsystems aren't exercised.

The Java port just landed at full TS parity (1178/1178 corpus). C++
needs the same refactor, but the main design decision is upstream of
all the steps: **what value type holds JSON-shaped data in memory?**
The answer determines almost every line of the rewrite.

## Recommended in-memory JSON data structure

### Recommendation: a custom `Value` class wrapping `std::variant`, with `shared_ptr`-backed containers and an insertion-ordered map.

```cpp
namespace voxgig::structlib {

class Value;
class Injection;
struct Sentinel { const char* tag; };  // identity-only marker

using List   = std::vector<Value>;
using Map    = boost::container::flat_map<std::string, Value>;  // or our own
using Func   = std::function<Value(Injection&, const Value&,
                                   const std::string&, const Value&)>;

class Value {
 public:
  // Variant alternatives map 1:1 onto the JSON value space plus the
  // language-runtime extras the canonical TS port needs.
  using Storage = std::variant<
    std::monostate,                  // T_noval (TS undefined)
    std::nullptr_t,                  // T_null  (JSON null)
    bool,                            // T_boolean
    int64_t,                         // T_integer
    double,                          // T_decimal
    std::string,                     // T_string
    std::shared_ptr<List>,           // T_list   — reference-stable
    std::shared_ptr<Map>,            // T_map    — reference-stable
    std::shared_ptr<Func>,           // T_function — callable values
    const Sentinel*                  // SKIP / DELETE (pointer-identity)
  >;

  Storage storage;
  // ... constructors, accessors, type predicates, == / != ...
};

}  // namespace voxgig::structlib
```

### Why each choice

1. **Custom `Value` over `nlohmann::json` directly.** The TS port
   needs to flow `Injector`/`Modify` callables through the same
   container as data, alongside SKIP/DELETE sentinels that survive
   `clone()` with byte-identity intact. `nlohmann::json` can store
   neither without the current `intptr_t` hack. A small custom class
   (~300 LoC) gives us a clean home for all of this.

2. **`std::variant` over inheritance / `void*` / `std::any`.**
   - `std::any` loses static type info and requires an `any_cast` per
     access, with no exhaustiveness check.
   - A polymorphic `Value` hierarchy adds vtables and forces
     heap allocation for every scalar (currently we'd inline them).
   - `std::variant` is a tagged union: zero per-scalar allocation,
     `std::visit` pattern-matching, compile-time alternative checks.
   - Cost: requires C++17 (the existing Makefile uses `-std=c++11` —
     this needs to bump). C++17 is mature and ubiquitous in 2026.

3. **`shared_ptr<List>` / `shared_ptr<Map>` for containers.** The
   project's top-level NOTES require lists to be "mutable and
   reference-stable" — when one `Value` holding a list is mutated,
   every other `Value` referencing the same list sees the mutation.
   `shared_ptr` gives us that for free, and it gives us cheap
   value-semantic copies (the `Value` itself is small and copyable;
   the underlying container is shared until forked by `clone()`).

4. **Insertion-ordered map.** TS objects preserve insertion order, and
   the canonical inject machinery depends on it for the
   `$`-suffix-key partition (non-`$` keys before `$`-keys).
   `std::map` is sorted, `std::unordered_map` has no order.
   `boost::container::flat_map` preserves insertion order in lookup
   but reorders on insert — wrong for us.
   **Recommendation: roll our own `OrderedMap` (≈80 LoC: a
   `std::vector<std::pair<std::string, Value>>` plus a
   `std::unordered_map<std::string, size_t>` index)**, mirroring
   what `nlohmann::ordered_json` does. We need this anyway since we're
   moving off nlohmann::json for runtime values.

5. **Distinct `std::monostate` (undefined) and `std::nullptr_t`
   (null).** TS's `undefined` and `null` are different values. The
   current C++ port collapses them via `nullptr` and a sidecar
   `__UNDEF__` marker; that breaks the `getprop`/`getelem`
   "absent vs present-but-null" semantics that several validate tests
   depend on.

6. **`const Sentinel*` for SKIP/DELETE.** Two static
   `Sentinel` instances (`SKIP_INST` / `DELETE_INST`) defined at
   namespace scope, addressed via pointer. `Value::operator==`
   compares the variant alternative first, then for `Sentinel*`
   compares the pointer directly. Identity survives `clone()` because
   `clone()` short-circuits on the variant index for sentinels.

7. **`int64_t` and `double` as separate alternatives.** Matches TS's
   `T_integer` / `T_decimal` distinction. `nlohmann::json` carries
   three numeric alternatives (signed / unsigned / double); we
   collapse to two and handle the unsigned case at parse time.

### What about keeping `nlohmann::json`?

Tempting because it's already a dependency and the existing 781 lines
use it. But:

- Function storage stays a `reinterpret_cast` hack. When `inject`
  starts cloning specs, the address baked into the JSON integer goes
  stale and the program crashes.
- `nlohmann::json::operator==` is value-equality, so SKIP/DELETE lose
  identity through any pass that constructs a fresh marker map.
- Mutating a `nlohmann::json` array via one reference doesn't
  propagate to other references — the canonical `merge`/`inject`
  reference-stability invariant fails.

We can **keep `nlohmann::json` as the JSON-text parser/serialiser**
(deserialise into `Value`, serialise from `Value`) without using it as
the runtime container. That removes the hack while reusing the parser
we already pull in.

### What about external libraries (Boost.JSON, RapidJSON, simdjson)?

- **Boost.JSON** has its own value type with similar trade-offs to
  `nlohmann::json`; same problems with callables and identity.
- **RapidJSON** is allocator-bound — the canonical port's free-form
  mutation pattern fights its design.
- **simdjson** is read-only; we need full mutation.

None of them solve the fundamental issue: the runtime container has
to hold callables alongside data with stable identity. A 300-line
custom `Value` does.

## Critical files

- **Modify**: `/home/user/struct/cpp/src/voxgig_struct.hpp` (likely
  splits into multiple headers — see below)
- **Modify**: `/home/user/struct/cpp/src/utility_decls.hpp`
- **Modify**: `/home/user/struct/cpp/Makefile` (bump to `-std=c++17`,
  add nlohmann path, add corpus runner target)
- **Add**: `/home/user/struct/cpp/src/value.hpp` (`Value`, `Sentinel`,
  `OrderedMap`, type predicates, `clone`)
- **Add**: `/home/user/struct/cpp/src/value_io.hpp` (parse / serialise
  via nlohmann::json bridge)
- **Add**: `/home/user/struct/cpp/src/injection.hpp` (`Injection`
  class, `Injector`, `Modify` typedefs)
- **Modify**: `/home/user/struct/cpp/tests/test_voxgig_struct.cpp`
- **Modify**: `/home/user/struct/cpp/tests/runner.hpp`
- **Add**: `/home/user/struct/cpp/test-baseline.json`
- **Update**: `/home/user/struct/cpp/README.md`,
  `/home/user/struct/cpp/REVIEW.md`, `/home/user/struct/REPORT.md`
- **Reference (read-only)**: `/home/user/struct/ts/src/StructUtility.ts`,
  `/home/user/struct/java/src/Struct.java`,
  `/home/user/struct/build/test/test.json`

## Refactor steps

Each step ends with `make compile_and_run_tests` green and a per-file
corpus pass count delta recorded in the commit message.

### Step 0 — Build hygiene
- Bump `Makefile` to `-std=c++17`.
- Fix `(1<<31)-1` → `(1u<<31)-1` (or `INT_MAX`) so it compiles.
- Vendor `nlohmann/json.hpp` into a known location or document fetch
  step (the env had to download it manually during exploration).

### Step 1 — Value type & sentinels (the foundation)
- Add `value.hpp`: `Value`, `OrderedMap`, `Sentinel`, `SKIP_INST`,
  `DELETE_INST`, type predicates (`isnode`, `ismap`, `islist`,
  `iskey`, `isempty`, `isfunc`), `typify`, `typename`, `typeof_t`
  bit-flag constants `T_*`.
- Add `value_io.hpp`: `Value parse_json(string)`,
  `string dump_json(Value, ...flags)` via nlohmann::json bridge.
- Add `clone(Value)` short-circuiting on sentinels.
- **Verify**: header compiles standalone; sentinel identity survives
  `clone()` round-trip in a smoke test.

### Step 2 — Replace `args_container` dispatch with typed signatures
- Every public function gains a typed signature:
  `bool isnode(const Value&)`, `Value getprop(const Value&, const Value&, const Value& alt = Value::undef())`,
  etc.
- Keep a thin `args_container` adapter only at the test-runner
  boundary so existing test wiring keeps working.
- Drop the `intptr_t` cast for callable values: `Value` now carries
  `shared_ptr<Func>` natively.
- **Verify**: existing 17 tests still compile and pass.

### Step 3 — Corpus runner & baseline scoreboard
- Port `js/test/runner.js` (or copy from `java/src/test/Runner.java`)
  to `tests/runner.hpp`. Implement `NULLMARK`/`UNDEFMARK`/`EXISTSMARK`,
  `fixJSON`, deep-equal normaliser, per-entry pass/fail capture.
- Add `tests/struct_corpus_test.cpp` that walks every `(category,
  name)` pair in `build/test/test.json` and runs it through the new
  typed signatures.
- Snapshot `cpp/test-baseline.json` with the current per-file pass
  counts (expected: most minor tests pass; everything else fails).
- **Verify**: scoreboard prints; baseline checked in.

### Step 4 — Minor utilities
Implement the remaining minor functions matching TS canonical:
`getelem`, `getdef`, `delprop`, `size`, `slice`, `pad`, `flatten`,
`filter`, `replace`, `join` (general, not just URL), `jsonify`,
`pathify`, `strkey`, `jm`, `jt`. Several already exist as drafts;
align signatures and behaviour.
- **Verify**: `minor.jsonic` strictly improves; aim for 506/506.

### Step 5 — `Injection` class skeleton
- Add `injection.hpp`: `Injection` class with the full TS field
  surface (`mode, full, keyI, keys, key, val, parent, path, nodes,
  handler, errs, meta, dparent, dpath, base, modify, prior, extra`).
- Methods: `descend`, `child(int keyI, vector<string>& keys)`,
  `setval(Value, int ancestor=0)`.
- **Sharing semantics**: `child()` shares `keys`/`errs`/`meta` by
  reference (use `shared_ptr` or raw pointer with documented
  lifetime). `path`/`nodes`/`dpath` are flattened (copied).
- `Injector` and `Modify` typedef'd as `std::function`.
- **Verify**: compiles; nothing wired yet.

### Step 6 — Mode constants, regex, helpers
- `M_KEYPRE = 1`, `M_KEYPOST = 2`, `M_VAL = 4`, `MAXDEPTH = 32`.
- `MODENAME`, `PLACEMENT` maps.
- `_invalidTypeMsg`, `_injectstr`, `_injecthandler`,
  `checkPlacement`, `injectorArgs`, `injectChild`.
- **Verify**: compiles; tests stay green.

### Step 7 — `getpath` & `setpath`
- Full TS-faithful `getpath(store, path, injdef)` matching TS
  lines 1144–1257: `R_META_PATH` (`$=`/`$~`), `$GET:`/`$REF:`/`$META:`
  prefixes, `$$` escape, ascending empty parts, `dpath` slicing,
  handler hook.
- `setpath(store, path, val, injdef)`.
- **Verify**: `getpath.jsonic` 87/87.

### Step 8 — `inject` state machine
- Replace any existing inject draft with the TS three-phase machine
  (`M_KEYPRE` → `M_VAL` → `M_KEYPOST`). Bake in `$`-suffix key
  ordering. Honour `inj.modify`. Top-level wrapper `{$TOP: val}` so
  `setval` can climb.
- **Verify**: `inject.jsonic` 41/41.

### Step 9 — Transform injectors
Implement (in dependency order):
1. `transform_DELETE`, `transform_COPY`, `transform_KEY`,
   `transform_ANNO`.
2. `transform_MERGE`.
3. `transform_FORMAT` + `FORMATTER` map (`identity`, `upper`,
   `lower`, `string`, `number`, `integer`, `concat`).
4. `transform_APPLY`.
5. `transform_EACH` — mutates `inj.keys`, builds parallel
   `tcur`/`tval`, recurses `inject`.
6. `transform_PACK` — same complexity, key-driven.
7. `transform_REF` — clones resolved spec before walking
   (immutable-list pitfall the Java port hit).

### Step 10 — `transform()` rewire
- `transform(data, spec, opts)` clones the spec, builds a store with
  `$TOP`/`$SPEC`/`$BT`/`$DS`/`$WHEN` and all `transform_*` plus
  `extraTransforms` and `$ERRS`, then dispatches via `inject`.
- **Verify**: `transform.jsonic` 187/187.

### Step 11 — Validate injectors + `_validation` modify + `_validatehandler`
- `validate_STRING`, `validate_TYPE` (generic dispatch on ref name),
  `validate_ANY`.
- `validate_CHILD` (3-phase), `validate_ONE`, `validate_EXACT`.
- `_validation` Modify: type mismatch checks, open-vs-closed maps via
  `\`$OPEN\``, exact-mode comparison, default-value copy-over.
- `_validatehandler` Injector: meta-path interception (`$=`/`$~`)
  before delegating to `_injecthandler`.

### Step 12 — `validate()` rewire
- Build store with nullified transform commands and validate_*
  injectors plus extra plus `$ERRS`. Set `meta.\`$EXACT\`` default.
  Dispatch via `transform()` with `_validation` modify and
  `_validatehandler` handler.
- **Verify**: `validate.jsonic` 131/131.

### Step 13 — `select()` rewire
- Implement `select_AND`, `select_OR`, `select_NOT`, `select_CMP`
  (`$GT`/`$LT`/`$GTE`/`$LTE`/`$LIKE`).
- `select(children, query)`: tag children with `$KEY`, walk-annotate
  query maps with `\`$OPEN\``=true, validate per child with
  `meta.\`$EXACT\``=true and store-as-extra.
- **Critical for parity**: the recursive validate inside
  select_AND/OR/NOT/CMP must include the current store as `extra` so
  nested `$`-operators stay registered. (The Java port hit and fixed
  this; mirror the fix here.)
- **Verify**: `select.jsonic` 47/47.

### Step 14 — `walk` enhancement
- Add `before` / `after` parameters and `maxdepth` to match TS.
- Path-pool optimisation can stay; the new signature wraps it.

### Step 15 — `StructUtility` instance facade
- Optional: thin wrapper class exposing each free function as a
  member, mirroring TS's `StructUtility` and Java's
  `Struct.StructUtility`.

### Step 16 — Cleanup, docs, parity report
- Remove the legacy `Utility`/`Provider`/`hash_table` machinery from
  `utility_decls.hpp` if it has no remaining caller after Step 2.
- Update `cpp/README.md` and `cpp/REVIEW.md` to reflect Complete
  status; bump `REPORT.md`.
- Add ASan / UBSan job to the Makefile (`make sanitize`).

## Risks (cross-language equivalents of issues hit during the Java port)

- **Sentinel identity through `clone()`** — must short-circuit on
  `Value`s holding `Sentinel*` so `==` identity survives.
- **`Injection.child()` reference sharing** — `keys`/`errs`/`meta`
  shared by reference, `path`/`nodes`/`dpath` flattened. Defensive
  copies of `keys` will silently break `$EACH`/`$PACK`. Use
  `std::shared_ptr` for shared fields and document the contract.
- **`R_INJECTION_FULL` regex** — optional digit suffix outside the
  capture group enables `$EACH1`/`$EACH2` ordering. Get it wrong and
  ordering tests pass for single-transform cases but fail for
  multi-transform.
- **`dpath` ascending collapse** of `'$:' + parentkey`. Silently
  breaks `$REF` and meta-path tests.
- **`setval(val, ancestor)` indexing** uses `0 - ancestor` against
  `nodes`/`path`. Negative-index `getelem` must match TS exactly.
- **`inj.modify` fires on node values**, not just leaves. Foundation
  of `_validation`. Don't add a leaf-only guard.
- **Map iteration order**: must be insertion order (use the
  `OrderedMap` recommendation, not `std::map` or `unordered_map`).
- **Number formatting in error messages**: JS renders `1.0` as `"1"`.
  The Java port added a `jsString()` helper for this; C++ needs the
  same so `_validation` "should equal" messages match the corpus.
- **Recursive validate inside select operators** must carry the store
  as `extra`. Cross-step bug from the Java port.
- **`getpath` UNDEF-vs-null distinction**: relative-path lookup
  against an absent dparent must return `Value::undef()`, not
  `nullptr_t`. Otherwise `setval` writes `null` back instead of
  delprop'ing the key.

## Verification

- **Per-step gate**: `make compile_and_run_tests` green +
  `cpp/test-baseline.json` per-file pass count strictly
  non-decreasing for files outside the step's scope.
- **Per-step target**: the file aligned with the step strictly
  improves:
  - Step 4 — `minor.jsonic`.
  - Step 7 — `getpath.jsonic`.
  - Step 8 — `inject.jsonic`.
  - Step 10 — `transform.jsonic`.
  - Step 12 — `validate.jsonic`.
  - Step 13 — `select.jsonic`.
- **Memory safety**: at the end, `make sanitize` (ASan + UBSan) on
  the corpus must report zero issues. `make check_leak` (valgrind)
  also clean.
- **End-to-end**: corpus pass count matches the Java port (1178/1178)
  on the same `test.json`.
- **Commit cadence**: one commit per step (or per sub-step inside
  step 9). Each commit includes the per-file pass-count delta in the
  message body.
- **Final commit**: pushes branch, updates `REPORT.md` row, opens no
  PR (per repo defaults; user must request one explicitly).

## Suggested ordering rationale

Steps 0–2 are setup that unblocks every later step. Steps 3+ run
strictly bottom-up: each subsystem depends on the previous one
working. The Java port followed this order and ended at 1178/1178
without churn — the same plan should land C++ in the same place.

The gating dependency is **Step 1 (Value type)**. Get the variant
alternatives, sentinel identity, and `OrderedMap` insertion-order
right, and the rest is mechanical translation from the Java port.
Get them wrong and every later step fights the runtime container.
