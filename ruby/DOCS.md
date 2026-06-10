# Struct for Ruby — Comprehensive Guide

> A faithful **port** of the canonical TypeScript implementation. Behaviour
> is defined there and mirrored here, case for case. This guide is the
> in-depth companion to [`README.md`](./README.md) (the quick-start +
> signature reference) and the language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  Ruby semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  place in the project, and Ruby-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

In the monorepo:

```bash
cd ruby
bundle install
```

The library is a single file, [`voxgig_struct.rb`](./voxgig_struct.rb),
exposing module `VoxgigStruct`. There is no build step; require it
directly:

```ruby
require_relative 'voxgig_struct'
```

Every public function is a module method, called as `VoxgigStruct.getpath(…)`.

### Your first program

```ruby
require_relative 'voxgig_struct'

config = VoxgigStruct.merge([
  { 'db' => { 'host' => 'localhost', 'port' => 5432 }, 'debug' => false }, # defaults
  { 'db' => { 'host' => 'db.internal' },               'debug' => true },  # overrides
])

VoxgigStruct.getpath(config, 'db.host')   # 'db.internal'
VoxgigStruct.getpath(config, 'db.port')   # 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Ruby-flavoured version:

```ruby
S = VoxgigStruct

# Reshape by example — the spec mirrors the output you want.
S.transform(
  { 'user' => { 'first' => 'Ada', 'last' => 'Lovelace' }, 'age' => 36 },
  { 'name' => '`user.first`', 'surname' => '`user.last`', 'years' => '`age`' },
)
# { 'name' => 'Ada', 'surname' => 'Lovelace', 'years' => 36 }

# Validate by example — leaves are type checkers; raises on mismatch.
S.validate({ 'name' => 'Ada', 'age' => 36 }, { 'name' => '`$STRING`', 'age' => '`$INTEGER`' })

# Walk the tree — replace values on ascent.
S.walk(tree, nil, ->(key, val, parent, path) { val.nil? ? 'DEFAULT' : val })

# Select children by query — each match tagged with its $KEY.
S.select({ 'a' => { 'age' => 30 }, 'b' => { 'age' => 25 } }, { 'age' => 30 })
# [ { 'age' => 30, '$KEY' => 'a' } ]
```

Map keys are strings throughout — the corpus is JSON-shaped, so write
`{ 'db' => … }`, not `{ db: … }`.

---

## 2. How-to guides

### Collect all validation errors instead of raising
Pass an injection-definition map carrying an `errs` collector as the
fourth argument; `validate` appends to it instead of raising:

```ruby
errs = []
VoxgigStruct.validate(payload, spec, { 'errs' => errs })
warn errs.inspect unless errs.empty?
```

### Write a custom transform function (`$APPLY`)
```ruby
sum = ->(resolved, store, inj) { resolved.is_a?(Array) ? resolved.sum : resolved }
VoxgigStruct.transform(
  { 'items' => [1, 2, 3] },
  { 'total' => ['`$APPLY`', sum, '`items`'] },
)
# { 'total' => 6 }
```
`$APPLY` appears in **value** position as a list
`['`$APPLY`', <function>, <childspec>]` — the callable goes inline at
index 1 (it is *not* looked up by name from `extra`), and the third element
is a child spec that is injected first and handed to the callback as
`resolved`. Placing `$APPLY` in key position
(`{ '`$APPLY`' => … }`) raises `$APPLY: invalid placement as key`. The
callback is invoked as `(resolved, store, inj)` and its return value becomes
the key's value.

### Keep a `walk` path past the callback
```ruby
seen = []
VoxgigStruct.walk(tree, ->(key, val, parent, path) {
  seen << path.dup   # the path array is reused — dup to retain it
  val
})
```

### Serialise deterministically
`jsonify` pretty-prints by default (indent 2); pass `{ 'indent' => 0 }` for compact.
`stringify` is the quote-light human form (keys sorted), for logs.

<!-- example: minor/jsonify#brace -->
```ruby
VoxgigStruct.jsonify({ 'a' => 1, 'b' => [2, 3] })
# {
#   "a": 1,
#   "b": [
#     2,
#     3
#   ]
# }
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

<!-- example: minor/stringify#brace -->
```ruby
VoxgigStruct.stringify({ 'a' => 1, 'b' => [2, 3] })   # '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

`jsonify`'s second argument is a flags **Hash** (`'indent'`, `'offset'`),
not a positional indent.

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ (Ruby hashes with string keys, `->` lambdas).

---

## 3. Reference

The full Ruby surface, with an example for every function, is in
[`README.md` → Function reference](./README.md#function-reference). The
public surface is the set of `def self.…` module methods in
[`voxgig_struct.rb`](./voxgig_struct.rb); the canonical contract those map
to is the `export { … }` block in
[`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts),
which [`../tools/check_parity.py`](../tools/check_parity.py) checks this
port against (case/underscore-insensitively).

Ruby-specific points the signatures don't show:

- **Methods, not a wrapper object.** The API is a flat set of module
  methods on `VoxgigStruct` (`VoxgigStruct.getpath`). There is no
  `StructUtility`-style instance class — that wrapper is TypeScript-only.
- **`Injection` is the one public class.** It carries inject/transform
  state (`descend`, `child`, `setval`) and is what you reach for when
  writing a custom injector; the high-level calls construct it for you.
- **`getprop` vs `getelem`.** `getprop` reads maps and lists; `getelem` is
  list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` when the element is absent.
- **`walk` extra parameters** (`key:`, `parent:`, `path:`, `pool:`) are
  keyword recursion state; callers pass only positional
  `(val, before = nil, after = nil, maxdepth = nil)`.
- **Type flags** combine bitwise: `typify('hi')` is `T_scalar | T_string`;
  test with `0 < (T_string & t)`. `typify(UNDEF)` is `T_noval` (not a
  scalar); `typify(nil)` is `T_scalar | T_null`.
- **Extras beyond the canonical 48.** This port also exposes `joinurl`,
  `replace`, and the `select` operators (`AND`/`OR`/`NOT`/`CMP`).

---

## 4. Explanation & port specifics

### This is a port, not the source of truth

Behaviour is defined by the canonical TypeScript
([`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts))
and pinned by the shared corpus in [`../build/test/`](../build/test/). When
the Ruby output and the corpus disagree, the Ruby port is wrong — fix it
here to match; never edit the corpus to make Ruby pass. A genuine
behaviour change starts in the canonical TS and flows out to every port
(see [`../AGENTS.md`](../AGENTS.md#standard-workflows)).

### `nil` versus `UNDEF`

Ruby has `nil` but no separate "absent" value, so the port adds one — the
[Group A/B rule](../DOCS.md#null-versus-absent-group-ab) in Ruby form:

- `UNDEF` (`Object.new.freeze`) = **absent**. `getprop` on a missing key
  returns it; the test runner converts it back to `nil` at the boundary.
  Group A readers (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
  treat a stored `nil` as absent too.
- `nil` = the JSON null scalar; `typify(nil)` is `T_scalar | T_null`, and
  Group B processors (`clone`, `merge`, `walk`, …) preserve it literally.
  Internally `setval` keeps the UNDEF/`nil` distinction so a deliberately
  stored null is never confused with a vacated slot.

If your data source returns `nil` for "not set", decide which you mean
before handing it to `struct`.

### Insertion-ordered maps come free

Map key order is observable through `keysof`, `items`, and `jsonify`, and
must match insertion order. Ruby `Hash` preserves insertion order
natively, so — unlike the C, Rust, Perl, or Swift ports — this port needs
no in-tree ordered-map wrapper. Just don't reorder keys to satisfy a diff.

### Regex

The uniform six-function regex layer (`re_compile` / `re_test` / `re_find`
/ `re_find_all` / `re_replace` / `re_escape`) wraps Ruby's built-in
`Regexp`, which runs the **Onigmo** backtracking engine. Onigmo *allows*
backreferences and lookaround, but those don't port — stay inside the
**RE2 subset**. Because Onigmo is a backtracking engine, its edges align
with the other backtracking ports (JS, Python, PHP, Perl): zero-width
`re_replace("a*", "abc", "X")` yields `"XXbXcX"` (RE2 ports return
`"XbXcX"`), and nested quantifiers can still backtrack catastrophically on
some shapes. Both are detailed in [`README.md` → Regex](./README.md#regex)
and [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd ruby
bundle install
make test         # ruby test_voxgig_struct.rb  (runs the shared corpus suite)
make lint         # bundle exec rubocop
make audit        # bundler-audit check --update  (needs gem install bundler-audit)
```

Dev tooling is test-only (the library itself has zero runtime deps):
minitest `~> 5.25` and RuboCop `~> 1.69`. Tests live in
[`test_voxgig_struct.rb`](./test_voxgig_struct.rb) and load the shared
corpus from [`../build/test/`](../build/test/), the same fixtures every
port runs.

**To fix a port bug:** reproduce with `make test`, read the failing corpus
case, compare the Ruby logic to the canonical TS for that function, fix the
Ruby to match, then `make test` and `make lint` green.

**To change canonical behaviour:** do it in the TypeScript first, adjust
`../build/test/*.jsonic`, then propagate here and re-run
[`../tools/check_parity.py`](../tools/check_parity.py) plus this port's
tests. The full checklist is in [`../AGENTS.md`](../AGENTS.md).
