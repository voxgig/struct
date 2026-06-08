# Struct for Java

> Java port of the canonical TypeScript implementation.
>
> **Status: complete.**  Full TS-canonical parity: all 40 functions,
> 15 type bit-flags, 3 mode constants (`M_KEYPRE`/`M_KEYPOST`/`M_VAL`),
> `SKIP`/`DELETE` sentinel marker maps, and the `Injection` state
> machine. `inject()`/`transform()`/`validate()`/`select()` all dispatch
> through the canonical injector machinery (the 11 transform commands,
> the validate checkers, and the 4 select operators).
>
> Passes the full shared corpus. Run locally with `mvn test` from
> `java/`. Per-file pass counts are written to
> `target/corpus-scoreboard.json`; the committed baseline lives at
> `test-baseline.json`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).  For the in-depth guide (tutorial, recipes,
explanation), see [`DOCS.md`](./DOCS.md).

> **Maturity note.** The top-level README lists Java as a *partial* port.
> That label is about project maturity (and the JVM family lagging the
> canonical by a release), **not** missing API: the full canonical surface
> is present and the parity check reports Java `ok`.


## Install

In the monorepo:

```bash
cd java
mvn package        # or `make build`
```

Group / artifact: `com.voxgig:struct-java`.  Single class:
`voxgig.struct.Struct` (all functions are static methods).

```java
import voxgig.struct.Struct;
```


## Quick start

```java
import voxgig.struct.Struct;
import java.util.Map;

Map<String, Object> store = Map.of(
    "db", Map.of("host", "localhost", "port", 5432)
);

Object host = Struct.getpath(store, "db.host");   // "localhost"

// Reshape by example.
Object out = Struct.transform(
    Map.of("user", Map.of("first", "Ada"), "age", 36),
    Map.of("name", "`user.first`", "years", "`age`")
);
// { name=Ada, years=36 }
```


## Naming convention

The core functions keep the canonical **lowercase** names exactly
(`getpath`, `setpath`, `getprop`, `setprop`, `isnode`, `ismap`, `escre`,
`escurl`, `keysof`, …) — same as most ports, not Java-style camelCase.
Only the regex layer (`reCompile`/`reTest`/`reFind`/`reFindAll`/
`reReplace`/`reEscape`) and the three injection helpers
(`checkPlacement`/`injectorArgs`/`injectChild`) use camelCase.


## Function reference

All functions are `public static` on `voxgig.struct.Struct`. The full,
example-by-example reference is in [`DOCS.md`](./DOCS.md); the canonical
semantics for every function are in the
[top-level reference](../DOCS.md#3-reference).

`Struct.StructUtility` is a nested instance facade (every function as an
instance method), useful for injecting the API as an object; `walk` has
`(val, apply)`, `(val, before, after)`, and `(val, before, after, maxdepth)`
overloads:

```java
public interface WalkApply {
    Object apply(Object key, Object val, Object parent, List<String> path);
}
public static Object walk(Object val, WalkApply before, WalkApply after, int maxdepth)
```


## Constants

### Type bit-flags

All 15 are present as `int` constants on `Struct`:

```java
Struct.T_any        Struct.T_noval     Struct.T_boolean
Struct.T_decimal    Struct.T_integer   Struct.T_number
Struct.T_string     Struct.T_function  Struct.T_symbol
Struct.T_null       Struct.T_list      Struct.T_map
Struct.T_instance   Struct.T_scalar    Struct.T_node
```

### Sentinels & mode flags

`Struct.SKIP` / `Struct.DELETE` (marker maps); `Struct.M_KEYPRE` /
`M_KEYPOST` / `M_VAL` and `MODENAME`.


## Notes

### Object model

Maps are `LinkedHashMap<String,Object>` (insertion-ordered, matching the
canonical key order) and lists are `ArrayList<Object>` — both
reference-stable, so the "lists are mutable in place" property holds with
no wrapper.

### `null` conventions

Java has only `null`. As in Go, `null` stands in for both JSON null and
"absent"; the shared Group A/B rule (see [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md))
decides which a given function means, and the corpus uses the `__NULL__`
sentinel where it must disambiguate.

### Tests

A Gson-based corpus runner drives the shared `.jsonic` fixtures
(`src/test/`), with a committed `test-baseline.json`. Gson is a
**test-scope** dependency only; the library proper has no third-party
runtime dependency (it hand-rolls its JSON printer).


## Regex

Uniform six-function regex API (see `/REGEX_API.md`). The Java port
wraps `java.util.regex.Pattern`.

### API

| Function | Maps to |
|---|---|
| `reCompile(pattern)`              | `Pattern.compile(pattern)` (throws `PatternSyntaxException` on bad pattern) |
| `reTest(pattern, input)`          | `Pattern.compile(pattern).matcher(input).find()` |
| `reFind(pattern, input)`          | first match as `String[]` of `[whole, group1, …]` or `null` |
| `reFindAll(pattern, input)`       | `List<String[]>` |
| `reReplace(pattern, input, repl)` | `matcher.replaceAll(repl)` |
| `reEscape(s)`                     | escape regex metacharacters |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/REGEX.md`.
Java's regex supports backreferences and lookaround; using them will
not be portable.

### Sharp edges

- **Catastrophic backtracking.** `java.util.regex` is backtracking;
  the discovery panel sees P1 (`^(a+)+$` over 22 a's plus `!`) in
  ~13 ms here. Other shapes can be worse. Prefer flat patterns.
- **Zero-width `replace`.** `reReplace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/REGEX_PATHOLOGICAL.md`.
- **`System.out` encoding.** When printing match results that contain
  non-ASCII characters, `System.out`'s default `PrintStream` uses the
  platform's default charset, not UTF-8. The discovery panel sees
  `caf?` in stdout though the in-memory `String` is correct UTF-16.
  Pass `-Dfile.encoding=UTF-8` (or use `PrintStream(System.out, true,
  StandardCharsets.UTF_8)`) when this matters. Orthogonal to the
  regex itself.

See `/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd java
mvn package
make test           # mvn test — runs the shared .jsonic corpus
```

Tests live in [`src/test/`](./src/test/).
</content>
