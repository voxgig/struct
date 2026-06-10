# Struct for Java

> Java port of the canonical TypeScript implementation.
>
> **Status: complete.**  Full TS-canonical parity: all 48 functions,
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
[REPORT.md](../design/REPORT.md).  For the in-depth guide (tutorial, recipes,
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
    Object apply(String key, Object val, Object parent, List<String> path);
}
public static Object walk(Object val, WalkApply before, WalkApply after, int maxdepth)
```

### Minor utility examples

Each call uses the mutable `jm` / `jt` builders so output ordering is
deterministic. The result of every example is also a tested corpus entry.

Predicates — `isnode` is true for maps and lists:

<!-- example: minor/isnode#map -->
```java
Struct.isnode(Struct.jm("a", 1));        // true
```
<!-- => true -->

`ismap` is true only for maps; `islist` only for lists:

<!-- example: minor/ismap#map -->
```java
Struct.ismap(Struct.jm("a", 1));         // true
```

<!-- => true -->

<!-- example: minor/islist#list -->
```java
Struct.islist(Struct.jt(1, 2));          // true
```

<!-- => true -->

`iskey` is true for non-empty strings and numbers (usable as keys):

<!-- example: minor/iskey#str -->
```java
Struct.iskey("name");                    // true
```

<!-- => true -->

`isempty` is true for null, empty strings, and empty nodes:

<!-- example: minor/isempty#empty -->
```java
Struct.isempty(Struct.jt());             // true
```

<!-- => true -->

Size of a node is its element count:

<!-- example: minor/size#three -->
```java
Struct.size(Struct.jt(1, 2, 3));         // 3
```
<!-- => 3 -->

`slice` keeps the first *N*; a negative `start` drops the last *|start|*
items, and `end` is exclusive:

<!-- example: minor/slice#mid -->
```java
Struct.slice(Struct.jt(1, 2, 3, 4, 5), 1, 4);   // [2, 3, 4]
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```java
Struct.slice("abcdef", -3, null);        // "abc"  (drops the last 3)
```
<!-- => "abc" -->

`pad` extends to the right (a negative width pads on the left):

<!-- example: minor/pad#right -->
```java
Struct.pad("a", 3, null);                // "a  "
```
<!-- => "a  " -->

`getprop` reads a key from a map or list:

<!-- example: minor/getprop#hit -->
```java
Struct.getprop(Struct.jm("x", 1), "x");  // 1
```
<!-- => 1 -->

`getelem` is list-specific and supports negative-from-the-end indexing:

<!-- example: minor/getelem#neg -->
```java
Struct.getelem(Struct.jt(10, 20, 30), -1);   // 30
```

<!-- => 30 -->

`setprop` returns the parent with the key set:

<!-- example: minor/setprop#set -->
```java
Struct.setprop(Struct.jm("a", 1), "b", 2);   // {a=1, b=2}
```

<!-- => {"a": 1, "b": 2} -->

`delprop` returns the parent with the key removed:

<!-- example: minor/delprop#del -->
```java
Struct.delprop(Struct.jm("a", 1, "b", 2), "a");   // {b=2}
```

<!-- => {"b": 2} -->

`haskey` is true when the key holds a value:

<!-- example: minor/haskey#hit -->
```java
Struct.haskey(Struct.jm("a", 1), "a");   // true
```

<!-- => true -->

`items` returns the `[key, value]` pairs of a map or list:

<!-- example: minor/items#map -->
```java
Struct.items(Struct.jm("a", 1, "b", 2));   // [[a, 1], [b, 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

`strkey` coerces a key to its canonical string form (numbers truncate):

<!-- example: minor/strkey#num -->
```java
Struct.strkey(2.2);                      // "2"
```

<!-- => "2" -->

`keysof` returns map keys sorted:

<!-- example: minor/keysof#sorted -->
```java
Struct.keysof(Struct.jm("b", 4, "a", 5));   // ["a", "b"]  (sorted)
```
<!-- => ["a", "b"] -->

`filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```java
Struct.filter(Struct.jt(1, 2, 3, 4, 5),
    item -> ((Number) item.get(1)).intValue() > 3);   // [4, 5]
```
<!-- => [4, 5] -->

`jsonify` pretty-prints by default (indent 2); pass `{ "indent": 0 }` for
the compact form:

<!-- example: minor/jsonify#map -->
```java
Struct.jsonify(Struct.jm("a", 1));
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```java
Struct.jsonify(Struct.jm("a", 1, "b", 2), Map.of("indent", 0));  // {"a":1,"b":2}
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```java
Struct.stringify(Struct.jm("a", 1, "b", Struct.jt(2, 3)));   // {a:1,b:[2,3]}
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```java
Struct.stringify("verylongstring", 5);   // ve...
```
<!-- => "ve..." -->

`getpath` reads a deep value by dot-path (arg order: `getpath(store, path)`):

<!-- example: getpath/basic#deep -->
```java
Struct.getpath(Struct.jm("a", Struct.jm("b", Struct.jm("c", 42))), "a.b.c");   // 42
```
<!-- => 42 -->

`setpath` writes a deep value, returning the (mutated) store:

<!-- example: minor/setpath#nested -->
```java
Struct.setpath(Struct.jm("a", 1, "b", 2), "b", 22);   // {a=1, b=22}
```

<!-- => {"a": 1, "b": 22} -->

`pathify` renders a path list as a dot-string:

<!-- example: minor/pathify#parts -->
```java
Struct.pathify(Struct.jt("a", "b", "c"));   // "a.b.c"
```

<!-- => "a.b.c" -->

`typify` returns a bit-field combining a kind flag with a specific type;
`typename` looks up the human-friendly name:

<!-- example: minor/typify#int -->
```java
Struct.typify(1);                        // T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

<!-- example: minor/typename#map -->
```java
Struct.typename(8192);                    // "map"  (8192 == T_map)
```

<!-- => "map" -->

`escre` escapes regex metacharacters; `escurl` percent-encodes for URLs:

<!-- example: minor/escre#dots -->
```java
Struct.escre("a.b+c");                    // "a\\.b\\+c"
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```java
Struct.escurl("hello world?");            // "hello%20world%3F"
```

<!-- => "hello%20world%3F" -->

`join` concatenates a list with a separator (the third arg is URL-collapse
mode):

<!-- example: minor/join#sep -->
```java
Struct.join(Struct.jt("a", "b", "c"), "/", false);   // "a/b/c"
```

<!-- => "a/b/c" -->

`clone` deep-copies a node:

<!-- example: minor/clone#deep -->
```java
Struct.clone(Struct.jm("a", Struct.jm("b", Struct.jt(1, 2))));   // {a={b=[1, 2]}}  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

`flatten` collapses nested lists one level by default:

<!-- example: minor/flatten#nested -->
```java
Struct.flatten(Struct.jt(1, Struct.jt(2, Struct.jt(3))));   // [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

`merge` deep-merges a list of nodes — last input wins, maps deep-merge,
lists merge by index:

<!-- example: merge#basic -->
```java
Struct.merge(Struct.jt(
    Struct.jm("a", 1, "b", 2, "k", Struct.jt(10, 20), "x", Struct.jm("y", 5, "z", 6)),
    Struct.jm("b", 3, "d", 4, "e", 8, "k", Struct.jt(11), "x", Struct.jm("y", 7))));
// {a=1, b=3, d=4, e=8, k=[11, 20], x={y=7, z=6}}
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

`inject` replaces backtick refs in strings with values from the store:

<!-- example: inject#basic -->
```java
Struct.inject(Struct.jm("x", "`a`", "y", 2), Struct.jm("a", 1));   // {x=1, y=2}
```

<!-- => {"x": 1, "y": 2} -->

`validate` checks data against a shape spec (throws on mismatch):

<!-- example: validate#shape -->
```java
Struct.validate(Struct.jm("name", "Ada", "age", 36),
    Struct.jm("name", "`$STRING`", "age", "`$INTEGER`"));   // {name=Ada, age=36}
```

<!-- => {"name": "Ada", "age": 36} -->

`select` finds children matching a query, tagging each with its `$KEY`:

<!-- example: select#query -->
```java
Struct.select(
    Struct.jm("a", Struct.jm("name", "Alice", "age", 30),
              "b", Struct.jm("name", "Bob", "age", 25)),
    Struct.jm("age", 30));
// [{name=Alice, age=30, $KEY=a}]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->


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
"absent"; the shared Group A/B rule (see [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md))
decides which a given function means, and the corpus uses the `__NULL__`
sentinel where it must disambiguate.

### Tests

A Gson-based corpus runner drives the shared `.jsonic` fixtures
(`src/test/`), with a committed `test-baseline.json`. Gson is a
**test-scope** dependency only; the library proper has no third-party
runtime dependency (it hand-rolls its JSON printer).


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The Java port
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

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
Java's regex supports backreferences and lookaround; using them will
not be portable.

### Sharp edges

- **Catastrophic backtracking.** `java.util.regex` is backtracking;
  the discovery panel sees P1 (`^(a+)+$` over 22 a's plus `!`) in
  ~13 ms here. Other shapes can be worse. Prefer flat patterns.
- **Zero-width `replace`.** `reReplace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.
- **`System.out` encoding.** When printing match results that contain
  non-ASCII characters, `System.out`'s default `PrintStream` uses the
  platform's default charset, not UTF-8. The discovery panel sees
  `caf?` in stdout though the in-memory `String` is correct UTF-16.
  Pass `-Dfile.encoding=UTF-8` (or use `PrintStream(System.out, true,
  StandardCharsets.UTF_8)`) when this matters. Orthogonal to the
  regex itself.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd java
mvn package
make test           # mvn test — runs the shared .jsonic corpus
```

Tests live in [`src/test/`](./src/test/).
</content>
