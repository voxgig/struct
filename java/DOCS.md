# Struct for Java — Comprehensive Guide

> A **port** of the canonical TypeScript implementation. Behaviour is
> defined by [`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
> and pinned by the shared corpus; this port matches it. The in-depth
> companion to [`README.md`](./README.md) (quick-start + signature
> reference) and the language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  Java-specific semantics and types.
- **[Explanation](#4-explanation--port-specifics)** — the model, the
  port's role, and Java-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

> **Status nuance.** The top-level [`README.md`](../README.md) lists Java
> under *Partial*, but the port now defines the **full canonical API** (all
> 40 functions, the `Injection` state machine, `SKIP`/`DELETE`, the mode
> constants, all 11 transform commands, the validate checkers and select
> operators) and `python3 ../tools/check_parity.py` reports it `ok`. Treat
> "Partial" as a stale label; the parity tool and the source are ground
> truth.

---

## 1. Tutorial

### Install

Build from the [`java/`](.) directory (not yet a published artifact):

```bash
cd java
mvn -DskipTests compile     # or: make build
```

Group / artifact `com.voxgig:struct-java`; single class
`voxgig.struct.Struct` (`import voxgig.struct.Struct;`). The library proper
has **zero runtime dependencies** — it hand-rolls its own JSON printer
(`jsonify`). Gson is **test scope only**, to load the shared corpus.

### Your first program

Every method is `static` on `Struct`. The data model is JSON-shaped
`Object`: `Map<String,Object>` for maps, `List<Object>` for lists, plus
`String` / `Number` / `Boolean` / `null` scalars. The `jm` / `jt` builders
return mutable `LinkedHashMap` / `ArrayList`:

```java
Object config = Struct.merge(Struct.jt(
    Struct.jm("db", Struct.jm("host", "localhost", "port", 5432), "debug", false), // defaults
    Struct.jm("db", Struct.jm("host", "db.internal"), "debug", true)));            // overrides

Struct.getpath(config, "db.host");   // "db.internal"
Struct.getpath(config, "db.port");   // 5432  (survived the deep merge)
```

> `merge` / `setpath` / `walk` (and `select`, which tags child nodes with
> `$KEY`) write **back into** their input nodes, so feed them mutable
> containers — `jm` / `jt`, `LinkedHashMap` / `ArrayList`, or
> `Struct.clone(...)` first. `Map.of(...)` is immutable and will throw if
> mutated; it is fine only as read-only input to cloning operations
> (`transform`, `validate`, which clone `data`/`spec` internally).

### Build up the rest of the API

Each call has the same meaning in every port; only the syntax changes. See
[`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the language-neutral
walkthrough; the Java-flavoured version:

```java
// Reshape by example — the spec mirrors the output you want.
Struct.transform(
    Map.of("user", Map.of("first", "Ada", "last", "Lovelace"), "age", 36),
    Map.of("name", "`user.first`", "surname", "`user.last`", "years", "`age`"));
// { name: "Ada", surname: "Lovelace", years: 36 }

// Validate by example — leaves are type checkers; throws on mismatch.
Struct.validate(Map.of("name", "Ada", "age", 36),
                Map.of("name", "`$STRING`", "age", "`$INTEGER`"));

// Walk the tree — replace values on ascent (after callback).
Struct.walk(tree, null, (key, val, parent, path) -> val == null ? "DEFAULT" : val);

// Select children by query — each match tagged with its $KEY (mutates
// child nodes, so build them mutable).
Struct.select(Struct.jm("a", Struct.jm("age", 30), "b", Struct.jm("age", 25)),
              Map.of("age", 30));
// [ { age: 30, $KEY: "a" } ]
```

---

## 2. How-to guides

### Use the instance facade (for stubbing in tests)
```java
import voxgig.struct.Struct.StructUtility;
StructUtility su = new StructUtility();
su.getpath(Map.of("a", Map.of("b", 1)), "a.b");   // 1
```
`Struct.StructUtility` mirrors the canonical `StructUtility` class — every
function is an instance method, sentinels/constants are instance fields —
for consumers that want to swap the implementation.

### Collect all validation errors instead of throwing
```java
List<Object> errs = new ArrayList<>();
Struct.validate(payload, spec, Map.of("errs", errs));
if (!errs.isEmpty()) { /* report them */ }
```
Supply an `errs` list in the options map; `validate` (and `transform`)
accumulate into it instead of throwing.

### Write a custom transform function (`$APPLY`)
```java
List<Object> spec = new ArrayList<>();
spec.add("`$APPLY`");
spec.add((Function<Object,Object>) v -> 1 + ((Number) v).intValue());  // the function
spec.add(1);                                                           // its argument value
Struct.transform(new LinkedHashMap<>(), spec);   // 2
```
The spec is `["`$APPLY`", fn, value]`: a `java.util.function.Function`
inlined as element 1 (not a name — `injectorArgs` type-checks it as
`T_function`), with element 2 the value/sub-spec it receives. Note `path`
inside a `WalkApply` callback is reused — copy it (`new ArrayList<>(path)`)
to retain it past the call.

### Serialise deterministically
```java
Struct.jsonify(value);                       // pretty (2-space), insertion-ordered keys
Struct.jsonify(value, Map.of("indent", 0));  // compact — flags are a Map (indent/offset)
Struct.stringify(value, 80);                 // truncated human form, for logs
```

For more task recipes (rename fields, `$EACH`, `$MERGE`, `$FORMAT`, `$ONE`,
`$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The Java signatures, with examples, are in
[`README.md` → Function reference](./README.md#function-reference); the
canonical public surface (40 names) is the `export { … }` block in
[`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts),
which `../tools/check_parity.py` checks this port against.

Java-specific points the signatures don't show:

- **`Object` at the boundaries.** Inputs/outputs are untyped JSON-shaped
  `Object`; `isnode`/`ismap`/`islist` are plain `boolean` (no type-guard
  narrowing), so a downcast still needs `instanceof` or a cast.
- **`UNDEF`, not `null`, marks absent.** `Struct.UNDEF` is a singleton
  `Object` for TS `undefined`; Group A readers return it (or your `alt`) for
  a missing slot, while a stored `null` is a distinct JSON value (see
  [`null` versus absent](#null-versus-absent)).
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getElem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` (`Function`) when the element is absent.
- **Overloads stand in for optional params** (no default args): e.g.
  `walk(val, apply)` / `walk(val, before, after[, maxdepth])`,
  `getprop(val, key[, alt])`, `transform(data, spec[, options])`, and the
  same for `validate` / `inject` / `merge` / `slice` / `pathify` /
  `jsonify` / `stringify` / `flatten`. Options ride in a `Map` (`extra`,
  `modify`, `errs`, `meta`, `handler`).
- **Type flags combine bitwise.** `typify("hi")` is `T_scalar | T_string`;
  test with `0 != (Struct.T_string & t)`. `typify(Struct.UNDEF)` is
  `T_noval`; `typify(null)` is `T_scalar | T_null`; `typename(t)` names the
  highest set bit.

### Casing

Single-word canonical names stay lowercase (`getprop`, `setprop`, `getpath`,
`setpath`, `isnode`, `escre`, `escurl`, `keysof`, `pathify`, `jsonify`,
`stringify`); only genuinely multi-word names are camelCased (`getElem`,
`getDef`, `delProp`, `hasKey`, `strKey`, `joinUrl`, plus the regex layer
`reCompile` / `reTest` / `reFind` / `reFindAll` / `reReplace` / `reEscape`).
Parity is checked case/underscore-insensitively. (`getProp` / `escapeRegex`
/ `escapeUrl` do **not** exist as methods — read by their real names above.)

---

## 4. Explanation & port specifics

This is a port: the canonical TS is the source of truth and the shared
corpus in [`../build/test/`](../build/test/) is the contract. Answer
behaviour questions by reading the canonical TS, not by polling ports; a
behaviour change starts there and flows to every port (see
[`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `null` versus absent

Java has only `null`, so the port introduces `Struct.UNDEF` (a singleton
`Object`) to carry TypeScript's `undefined` and keep the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) intact:

- **Group A — readers** (`getprop`, `getElem`, `hasKey`, `isempty`,
  `isnode`): a stored `null` reads as *no value* (you get `alt` or `false`);
  a truly missing slot returns `UNDEF`.
- **Group B — value processors** (`setprop`, `clone`, `walk`, `merge`,
  `inject`, `transform`, `validate`, `select`, …): `null` is preserved
  *literally*.

The corpus marks a real null `"__NULL__"` (and uses `"__UNDEF__"` /
`"__EXISTS__"` in match assertions); the runner round-trips these. This is
the single most common source of port bugs — get it right.

### Lists and maps are reference-stable

Maps are `LinkedHashMap<String,Object>` (insertion-ordered, as canonical
`jsonify` requires); lists are `ArrayList<Object>`. Both are mutable and
shared by reference, so the canonical "lists are mutable in place" property
holds **without** the `ListRef` wrapper that Go and PHP need — `walk`,
`merge`, `inject`, and `setpath` rely on it.

### Regex

The uniform six-function layer (`reCompile` / `reTest` / `reFind` /
`reFindAll` / `reReplace` / `reEscape`) wraps `java.util.regex.Pattern`, a
**backtracking** engine and a strict superset of the **RE2 subset** the
corpus stays inside — it allows backreferences and lookaround, but those
don't port, so don't use them. Two sharp edges align with the other
backtracking/ECMA ports (Python, PHP, Perl, Ruby, JS, .NET): catastrophic
backtracking on shapes like `^(a+)+$`, and zero-width
`reReplace("a*", "abc", "X")` returning `"XXbXcX"` (RE2 ports like Go return
`"XbXcX"`). See [`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd java
mvn -DskipTests compile     # build the library      (make build)
mvn test                    # run the shared corpus suite (make test)
make lint                   # compile + checkstyle:check + spotbugs:check
```

`mvn test` drives the shared corpus from
[`../build/test/`](../build/test/) via the runner in
[`src/test/`](./src/test/) (`Runner.java`, `StructCorpusTest.java`), loading
the `.jsonic` cases with Gson and writing per-file pass counts to
`target/corpus-scoreboard.json` (committed baseline:
[`test-baseline.json`](./test-baseline.json)). The library is
[`src/Struct.java`](./src/Struct.java); `sourceDirectory` is `src/` (flat —
no `src/main/java`).

**Toolchain:** source/target level **17** (runs on JDK 21); test deps JUnit
**6.1** + Gson (test scope); lint Checkstyle + SpotBugs.

**To change behaviour:** this is a port — never diverge from the canonical
alone. Edit the canonical TS + corpus first, port the change into
`src/Struct.java`, `mvn test` until the scoreboard is green, then re-run
`python3 ../tools/check_parity.py`. Full checklist in
[`../AGENTS.md`](../AGENTS.md).
