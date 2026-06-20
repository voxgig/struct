# Voxgig Struct

> Uniform JSON-shaped data structure manipulations, in many languages.

`struct` is the data manipulation primitive used inside the Voxgig
SDKs.  Every Voxgig SDK -- whatever its host language -- needs to look
up values inside nested JSON, merge configurations, transform data
between shapes, and validate that incoming data matches an expected
shape.  Rewriting that work for each language drifts: behaviours
diverge, edge cases get patched in one place but not another, and the
semantics of "the same" call become subtly different.

`struct` solves that by defining one canonical API, in one canonical
implementation (TypeScript), and porting it to every language a
Voxgig SDK runs in.  The same names, the same arguments, the same
return values, and the same JSON-driven test corpus run against every
port.  When you call `getpath(store, 'a.b.c')` in Python, Go, PHP, or
Lua, you get the same answer.


## Per-language documentation

Each implementation directory has its own `README.md` covering
installation, full function signatures (using that language's
syntax), and language-specific notes:

| Language   | Status     | README                                |
|------------|------------|---------------------------------------|
| TypeScript | Canonical  | [`typescript/README.md`](./typescript/README.md)      |
| JavaScript | Complete   | [`javascript/README.md`](./javascript/README.md)      |
| Python     | Complete   | [`python/README.md`](./python/README.md)              |
| Go         | Complete   | [`go/README.md`](./go/README.md)                      |
| PHP        | Complete   | [`php/README.md`](./php/README.md)                    |
| Ruby       | Complete   | [`ruby/README.md`](./ruby/README.md)                  |
| Lua        | Complete   | [`lua/README.md`](./lua/README.md)                    |
| Rust       | Complete   | [`rust/README.md`](./rust/README.md)                  |
| C          | Complete   | [`c/README.md`](./c/README.md)                        |
| C#         | Complete   | [`csharp/README.md`](./csharp/README.md)              |
| Zig        | Complete   | [`zig/README.md`](./zig/README.md)                    |
| Java       | Partial    | [`java/README.md`](./java/README.md)                  |
| Kotlin     | Partial    | [`kotlin/README.md`](./kotlin/README.md)              |
| C++        | Complete   | [`cpp/README.md`](./cpp/README.md)                    |
| Perl       | Complete   | [`perl/README.md`](./perl/README.md)                  |
| Swift      | Complete   | [`swift/README.md`](./swift/README.md)                |
| Clojure    | Complete   | [`clojure/README.md`](./clojure/README.md)            |

"Partial" (Java, Kotlin) denotes project maturity / release-lag — the
JVM family trails the canonical by a release — **not** missing API: both
report full canonical parity under `tools/check_parity.py`. See each
port's `README.md` for details.

Each port directory also carries a `DOCS.md` (the comprehensive,
four-part guide) and an `AGENTS.md` (notes for AI coding agents).

The cross-language parity matrix lives in [`REPORT.md`](design/REPORT.md).

For the in-depth, language-neutral guide — tutorial, how-to recipes, full
reference, and design explanation — see [`DOCS.md`](./DOCS.md). If you (or
an AI coding agent) are going to *modify* this repository, start with
[`AGENTS.md`](./AGENTS.md).


## Motivation

Voxgig SDKs work with structured data: configuration trees, API
request and response payloads, validation specs, transform recipes.
These are JSON-shaped: nested maps and lists of scalars.  The same
operations come up over and over:

- "Give me the value at path `service.db.host`."
- "Merge these three config maps, last one wins, but deep-merge maps."
- "Walk this tree and replace any `null` value with a default."
- "Take this template, and populate it from this data store."
- "Check that this incoming record matches the expected shape."

The naive answer is "use the host language's stdlib".  But:

- The host language may not have a deep merge.  Or its deep merge
  may have different rules than the next language's deep merge.
- "Get a value at a path" is one line in JavaScript and ten in C++.
- The semantics of `null` versus "absent" versus "empty" differ
  between languages, between JSON parsers, and between developers on
  the same team.
- Once you have transforms and validation, you really do not want to
  reimplement them per language.

`struct` is the answer: one API, one set of semantics, one JSON test
corpus, ported faithfully to every language Voxgig SDKs support.  An
SDK can rely on the same primitive operations everywhere.  A bug fix
in the canonical TypeScript flows through to every other port.

The shared test corpus (`build/test/*.jsonic`) is the contract.  Any
implementation passes only if it matches the canonical answers
case-for-case.


## Concepts

A few terms recur throughout the API.

- **Node**: a map (object) or list (array).  Anything that can have
  children.
- **Key**: a non-empty string (for maps) or an integer index (for
  lists).
- **Path**: a sequence of keys, written as a dotted string
  (`'a.b.0.c'`) or an array (`['a','b',0,'c']`).
- **Store**: the source data for an injection or path lookup.
- **Spec**: a by-example data structure that drives `transform` and
  `validate`.  The spec mirrors the desired output shape.
- **Injection**: substituting backtick-quoted references inside a
  spec with values pulled from a store, e.g. ``` `a.b` ``` becomes the
  value at path `a.b` in the store.
- **Sentinel**: a special marker value with no in-band JSON
  representation.  `SKIP` means "don't write this key", `DELETE`
  means "remove this key".

By-example design: the shape of the output is described by data that
*looks like* the output.  A transform spec for `{name, age}` is itself
a map with keys `name` and `age`.  A validate spec is the same shape
as the data it accepts, with type tokens (e.g. ``` `$STRING` ```) at
the leaves.


## Quick start

Pick your language's `DOCS.md` for installation instructions.  Once
installed, the calls below all mean the same thing.

### Look up a value at a path

JavaScript / TypeScript:

```js
const { getpath } = require('@voxgig/struct')
getpath({ db: { host: 'localhost', port: 5432 } }, 'db.host')
// => 'localhost'
```

Python:

```python
from voxgig_struct import getpath
getpath({'db': {'host': 'localhost', 'port': 5432}}, 'db.host')
# => 'localhost'
```

Go:

```go
voxgigstruct.GetPath(map[string]any{
    "db": map[string]any{"host": "localhost", "port": 5432},
}, "db.host")
// => "localhost"
```

### Merge a chain of maps

```js
merge([
  { a: 1, b: 2, x: { y: 5, z: 6 } },
  { b: 3,       x: { y: 7 }       },
])
// => { a: 1, b: 3, x: { y: 7, z: 6 } }
```

Last input wins for scalars; maps deep-merge; lists are merged by
index.

### Transform by example

```js
transform(
  { user: { first: 'Ada', last: 'Lovelace' }, age: 36 },
  { name: '`user.first`', surname: '`user.last`', years: '`age`' }
)
// => { name: 'Ada', surname: 'Lovelace', years: 36 }
```

### Validate by example

```js
validate(
  { name: 'Ada', age: 36 },
  { name: '`$STRING`', age: '`$INTEGER`' }
)
// => { name: 'Ada', age: 36 }   // ok
```

### Walk a tree

```js
// walk takes optional before/after callbacks; pass the same callback as
// `after` to replace values post-descent.
walk(tree, undefined, (key, val, parent, path) => {
  return val === null ? 'DEFAULT' : val
})
```


## Common recipes

These map directly to the per-language API.  Substitute the function
names that match your language's casing convention.

| Goal                                       | Function                       |
|--------------------------------------------|--------------------------------|
| Read a deep value, with a default          | `getpath`, `getprop`, `getdef` |
| Set a deep value, creating intermediate    | `setpath`                      |
| Test a value's shape                       | `isnode`, `ismap`, `islist`, `iskey`, `isempty`, `isfunc` |
| Get a type bitcode for a value             | `typify`                       |
| Get a human type name                      | `typename`                     |
| Sorted keys of a node                      | `keysof`                       |
| Iterate `[key, value]` pairs               | `items`                        |
| Deep copy                                  | `clone`                        |
| Deep merge a list of maps                  | `merge`                        |
| Walk a tree applying a function            | `walk`                         |
| Slice / pad / flatten / filter             | `slice`, `pad`, `flatten`, `filter` |
| Substitute references in a spec            | `inject`                       |
| Build an output by example                 | `transform`                    |
| Check a value against a shape              | `validate`                     |
| Pick records out of a node by query        | `select`                       |
| Build a JSON string                        | `jsonify`, `stringify`         |
| Escape for regex / URL                     | `escre`, `escurl`              |
| Join URL parts                             | `join`                         |


## Language-neutral API reference

This is the canonical API surface, defined in TypeScript at
[`typescript/src/StructUtility.ts`](./typescript/src/StructUtility.ts).  Every port
exposes equivalents.  The casing varies by language convention
(`getpath` in TS/JS/Py/Ruby/PHP/Lua/Perl/Java/Kotlin/Swift; `GetPath`
in Go/C#; `get_path` in Rust; `voxgig_getpath` in C).

### Minor utilities (29)

| Function                            | Returns         | Description                                                                 |
|-------------------------------------|-----------------|-----------------------------------------------------------------------------|
| `typename(t)`                       | string          | Human name (`"string"`, `"map"`, ...) for a type bit-flag from `typify`.    |
| `getdef(val, alt)`                  | any             | Returns `val` unless it is undefined, in which case returns `alt`.          |
| `isnode(val)`                       | bool            | True if `val` is a node -- either a map or a list.                          |
| `ismap(val)`                        | bool            | True if `val` is a map (object with string keys).                           |
| `islist(val)`                       | bool            | True if `val` is a list (array with integer indices).                       |
| `iskey(key)`                        | bool            | True if `key` is a non-empty string or an integer index.                    |
| `isempty(val)`                      | bool            | True if `val` is undefined, `null`, an empty string, list, or map.          |
| `isfunc(val)`                       | bool            | True if `val` is a callable function.                                       |
| `size(val)`                         | int             | Length for lists/strings; key count for maps; integer part for numbers.     |
| `slice(val, start?, end?, mutate?)` | any             | Sub-section of a list, string, or bounded number; negative indices count from the end. |
| `pad(str, width?, char?)`           | string          | Pad `str` to `width` with `char`; negative width pads on the left.          |
| `typify(val)`                       | int (bitfield)  | Type bit-code (e.g. `T_scalar | T_string`) describing the value.            |
| `getelem(list, key, alt?)`          | any             | List lookup by integer key, with `-1` counting from the end; `alt` if absent. |
| `getprop(node, key, alt?)`          | any             | Safe property lookup on a map or list; returns `alt` if missing.            |
| `strkey(key)`                       | string          | Coerce a key to a canonical string form (`""` for invalid keys).            |
| `keysof(node)`                      | string[]        | Sorted list of a node's keys (string indices for lists).                    |
| `haskey(node, key)`                 | bool            | True if the key is present and its value is defined.                        |
| `items(node)`                       | `[key, val][]`  | Entries of a map or list as `[key, value]` pairs.                           |
| `flatten(list, depth?)`             | list            | Concatenate nested lists down to `depth` levels.                            |
| `filter(node, predicate)`           | list            | Keep entries for which `predicate([key, val])` is truthy.                   |
| `escre(s)`                          | string          | Escape regex metacharacters in a string.                                    |
| `escurl(s)`                         | string          | URL-encode a string.                                                        |
| `join(arr, sep?, urlmode?)`         | string          | Join string parts with `sep`; in URL mode, collapse repeated separators.    |
| `jsonify(val, flags?)`              | string          | Strict JSON serialisation of a value; pretty-printed (indent 2) by default, pass `flags` `{indent:0}` for compact output. |
| `stringify(val, maxlen?)`           | string          | Compact, human-friendly string form of a value, truncated to `maxlen`.      |
| `pathify(val, from?, to?)`          | string          | Render a path (string or array) as a canonical dotted string.               |
| `clone(val)`                        | any             | Deep copy of a JSON-shaped value.                                           |
| `delprop(parent, key)`              | parent          | Remove a key from a map or list (returns the mutated parent).               |
| `setprop(parent, key, val)`         | parent          | Set a key on a map or list to `val` (returns the mutated parent).           |

### Major utilities (8)

| Function                                       | Returns         | Description                                                                 |
|------------------------------------------------|-----------------|-----------------------------------------------------------------------------|
| `walk(val, before?, after?, maxdepth?)`        | node            | Depth-first walk of a tree, calling `before` on descend and `after` on ascend at each node and leaf, with replacement. |
| `merge(list, maxdepth?)`                       | any             | Deep-merge a list of maps, last-wins for scalars; lists are merged by index.|
| `getpath(store, path, injdef?)`                | any             | Look up the value at a dotted path (or array path) inside `store`.          |
| `setpath(store, path, val)`                    | store           | Set `val` at a deep path inside `store`, creating missing parents.          |
| `inject(val, store, modify?)`                  | any             | Substitute `` `path` `` references inside `val` with values from `store`.   |
| `transform(data, spec, extra?, modify?)`       | any             | Build a result by example: `spec` mirrors output shape, with refs into `data`. |
| `validate(data, spec, extra?, collecterrs?)`   | any             | Check `data` against a by-example shape; returns `data` on success, throws or collects on mismatch. |
| `select(children, query)`                      | match[]         | Pick records from a node whose fields match the query, with `$KEY` operators. |

### Builders (2)

| Function       | Returns | Description                                                  |
|----------------|---------|--------------------------------------------------------------|
| `jm(...args)`  | map     | Build a map (JSON object) from alternating key/value pairs.  |
| `jt(...args)`  | list    | Build a list (JSON array/tuple) from positional args.        |

### Injection helpers (3)

These are exposed for callers that write custom injectors or modify
hooks; most users will not need them directly.

| Function                                    | Description                                                                |
|---------------------------------------------|----------------------------------------------------------------------------|
| `checkPlacement(inj, parent, ...)`          | Validate where an injection result may be placed (root vs branch vs leaf). |
| `injectorArgs(inj, store)`                  | Extract the argument list passed to a transform-command injector.          |
| `injectChild(inj, store, key)`              | Recurse `inject` into a child of the current node, sharing the state.      |

### Sentinels

| Symbol     | Description                                                                                |
|------------|--------------------------------------------------------------------------------------------|
| `SKIP`     | Returned from a transform/inject step to omit the current key from the output.             |
| `DELETE`   | Returned from a transform/inject step to delete the current key from the parent.           |

### Type bit-flags (15)

Returned by `typify(val)` and named by `typename(t)`.  Combine with
bitwise operators to test composite types (e.g. `T_node | T_map`).

| Constant      | Description                                                  |
|---------------|--------------------------------------------------------------|
| `T_any`       | Wildcard / "no constraint" type.                             |
| `T_noval`     | Property absent / undefined; **not** a scalar.               |
| `T_boolean`   | Boolean scalar.                                              |
| `T_decimal`   | Non-integer numeric scalar.                                  |
| `T_integer`   | Integer numeric scalar.                                      |
| `T_number`    | Any numeric scalar (set together with `T_integer`/`T_decimal`). |
| `T_string`    | String scalar.                                               |
| `T_function`  | Callable function value.                                     |
| `T_symbol`    | Symbolic atom (for languages that have them).                |
| `T_null`      | The actual JSON null value (distinct from absent).           |
| `T_list`      | List node (array).                                           |
| `T_map`       | Map node (object).                                           |
| `T_instance`  | Class instance (non-plain object).                           |
| `T_scalar`    | Set on every scalar type, alongside its specific flag.       |
| `T_node`      | Set on every node type (`T_list`, `T_map`, `T_instance`).    |

### Walk / inject mode flags

| Constant      | Description                                                  |
|---------------|--------------------------------------------------------------|
| `M_KEYPRE`    | Phase tag: about to descend into a child by key.             |
| `M_KEYPOST`   | Phase tag: returned from descending into a child by key.     |
| `M_VAL`       | Phase tag: visiting the value of a leaf.                     |
| `MODENAME`    | Lookup table mapping mode flags to human-readable names.     |

### Transform commands (used inside spec strings)

Quote the command in backticks inside a `transform` spec, e.g. `` `$COPY` ``.

| Command    | Description                                                                |
|------------|----------------------------------------------------------------------------|
| `$DELETE`  | Remove the current key from the output.                                    |
| `$COPY`    | Copy the matching value from `data` at the current path.                   |
| `$KEY`     | Insert the current key under another name in the output.                   |
| `$META`    | Attach or read metadata about the current path.                            |
| `$ANNO`    | Annotate the current node with extra fields from the spec.                 |
| `$MERGE`   | Deep-merge several sub-specs into the current node.                        |
| `$EACH`    | Apply a sub-spec to every entry of a list or map.                          |
| `$PACK`    | Repack a node by rewriting its keys / shape.                               |
| `$REF`     | Resolve a named reference inside the spec.                                 |
| `$FORMAT`  | Render a templated string using values from `data`.                        |
| `$APPLY`   | Call a function (from `extra`) on the current value and substitute result. |

### Validate checkers (used inside spec strings)

Quote the checker in backticks inside a `validate` spec, e.g. `` `$STRING` ``.

| Checker     | Description                                                              |
|-------------|--------------------------------------------------------------------------|
| `$MAP`      | The value must be a map.                                                 |
| `$LIST`     | The value must be a list.                                                |
| `$STRING`   | The value must be a string.                                              |
| `$NUMBER`   | The value must be a number (integer or decimal).                         |
| `$INTEGER`  | The value must be an integer.                                            |
| `$DECIMAL`  | The value must be a non-integer number.                                  |
| `$BOOLEAN`  | The value must be a boolean.                                             |
| `$NULL`     | The value must be JSON null.                                             |
| `$NIL`      | The value must be absent or null (lenient null check).                   |
| `$FUNCTION` | The value must be a callable function.                                   |
| `$INSTANCE` | The value must be a class instance (non-plain object).                   |
| `$ANY`      | The value matches anything (placeholder for "no constraint").            |
| `$CHILD`    | Apply a sub-spec to every direct child of the current node.              |
| `$ONE`      | The value must match exactly one of a list of alternative sub-specs.     |
| `$EXACT`    | The value must equal a literal value exactly (no shape coercion).        |

### Regex API (6)

A uniform six-function regex layer wraps each host engine so internal
call sites read the same in every port. Patterns must stay inside the
**RE2 subset** (no backreferences, no lookaround). Full spec:
[`REGEX_API.md`](design/REGEX_API.md), [`REGEX.md`](design/REGEX.md);
cross-engine edge cases:
[`REGEX_PATHOLOGICAL.md`](design/REGEX_PATHOLOGICAL.md).

| Function                                  | Returns        | Description                                                                 |
|-------------------------------------------|----------------|-----------------------------------------------------------------------------|
| `re_compile(pattern, flags?)`             | regex          | Compile a pattern (or return it as-is if already compiled); caching is port-defined. |
| `re_test(pattern, input)`                 | bool           | True if `pattern` matches anywhere in `input`.                              |
| `re_find(pattern, input)`                 | match \| null  | First match as `[whole, capture1, ...]`, or null if none.                  |
| `re_find_all(pattern, input)`             | match[]        | All non-overlapping matches, left to right, each shaped like `re_find`.    |
| `re_replace(pattern, input, replacement)` | string         | Replace every match; `replacement` is a string (with `$&`/`$1`..`$9`) or a callback. |
| `re_escape(s)`                            | string         | Escape regex metacharacters in `s` (alias of `escre`).                     |


## Design notes

- **By-example over DSL.**  A transform/validate spec looks like the
  output it describes.  No second language to learn.
- **Tolerant of "absent".**  Functions return a defined alternative
  (`alt`) rather than throwing on missing keys.  Each language port
  handles its own undefined/null distinction; see per-language docs.
- **Lists are mutable and reference-stable.**  In languages where
  this is not native (Go, PHP), the port introduces a wrapper
  (`ListRef`).
- **JSON null is not undefined.**  Most JSON parsers conflate them;
  `struct` distinguishes them.  The shared test corpus uses the
  string `"__NULL__"` to stand in for JSON null where the test
  language can't represent it directly.
- **The TypeScript implementation is canonical.**  Disagreement
  between a port and the test corpus is a port bug.
- **Zig keeps `allocator` first.**  The Zig port follows the
  language's universal convention of putting `allocator` as the
  first parameter, so its signatures look like
  `getpath(allocator, path, store)` rather than the canonical
  `getpath(store, path)`.  Argument order *after* the allocator is
  also Zig-side; see [`zig/DOCS.md`](./zig/DOCS.md).


## Repository layout

```
.
├── README.md         # this file
├── DOCS.md           # comprehensive language-neutral guide
├── AGENTS.md         # guidance for AI coding agents (+ CLAUDE.md pointer)
├── design/           # reports & specs: REPORT, NOTES, REGEX*, UNDEF*
├── build/test/       # shared JSON test corpus (.jsonic)
├── typescript/  javascript/  python/   # canonical + JS-family ports
├── go/  ruby/  php/                     # other complete ports
├── lua/  csharp/  zig/  rust/  c/  perl/  kotlin/  cpp/  swift/  clojure/
├── java/                                # partial port
└── LICENSE
```

Each language directory contains:

- the implementation source,
- a test runner that consumes `build/test/*.jsonic`,
- a `Makefile` with at minimum `make test` and `make lint` targets,
- a `README.md` with the per-language quick-start. Cross-port quirks
  go in the top-level [`NOTES.md`](design/NOTES.md).

`make lint` runs that language's industry-standard code-quality tooling
(linter + formatter check):

| Language   | Lint / static analysis            | Format check          |
|------------|-----------------------------------|-----------------------|
| TypeScript | ESLint (`typescript-eslint`)      | Prettier              |
| JavaScript | ESLint                            | Prettier              |
| Python     | Ruff, mypy                        | Ruff format           |
| Go         | golangci-lint, `go vet`           | `gofmt`               |
| Ruby       | RuboCop                           | RuboCop               |
| PHP        | PHP_CodeSniffer (PSR-12), PHPStan | PHP_CodeSniffer       |
| Rust       | Clippy                            | `cargo fmt`           |
| Java       | Checkstyle, SpotBugs              | Checkstyle            |
| C++        | clang-tidy                        | clang-format          |
| Lua        | luacheck                          | StyLua                |
| Zig        | `zig build` (compiler)            | `zig fmt`             |
| C#         | Roslyn analyzers                  | `dotnet format`       |
| Kotlin     | detekt                            | ktlint                |
| Clojure    | namespace compile check           | (clj-kondo optional)  |

Run everything with `make lint` at the repo root, or one language with
`make lint-<lang>` (e.g. `make lint-go`).

Beyond linting there are two more analysis stages:

- **`make audit`** — per-language dependency / supply-chain scanning:
  `npm audit` (typescript/javascript), `pip-audit` + Bandit (python),
  `govulncheck` + `gosec` (go), `bundler-audit` (ruby),
  `composer audit` (php), `cargo audit` (rust),
  `dotnet list --vulnerable` (csharp).
- **`make scan`** — repo-wide static analysis: secret scanning
  ([gitleaks]), SAST ([Semgrep]), known-vulnerability scanning across all
  lockfiles ([osv-scanner]), GitHub-workflow linting ([actionlint]), shell
  linting ([shellcheck]), spell checking ([cspell]), markdown linting
  ([markdownlint]), and a cross-port API-parity check
  (`tools/check_parity.py`).

`make analyze` runs all three (`lint` + `audit` + `scan`).  CI runs these
in [`.github/workflows/lint.yml`](./.github/workflows/lint.yml) and
[`.github/workflows/security.yml`](./.github/workflows/security.yml).

[gitleaks]: https://github.com/gitleaks/gitleaks
[Semgrep]: https://semgrep.dev/
[osv-scanner]: https://google.github.io/osv-scanner/
[actionlint]: https://github.com/rhysd/actionlint
[shellcheck]: https://www.shellcheck.net/
[cspell]: https://cspell.org/
[markdownlint]: https://github.com/DavidAnson/markdownlint


## License

MIT.  See [`LICENSE`](./LICENSE).
