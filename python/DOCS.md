# Struct for Python — Comprehensive Guide

> A faithful **port** of the canonical TypeScript implementation. Behaviour
> is defined by TypeScript and pinned by the shared corpus; this port
> matches it in idiomatic Python. This guide is the in-depth companion to
> [`README.md`](./README.md) (the quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  Python semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model, the port's
  role, and Python-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

```bash
cd python
pip install -e .
```

Package `voxgig_struct`; single module
[`voxgig_struct/voxgig_struct.py`](./voxgig_struct/voxgig_struct.py).

Without installing, put the source directory on `sys.path`:

```python
import sys
sys.path.insert(0, '/path/to/struct/python')
from voxgig_struct import getpath, transform, validate
```

### Your first program

```python
from voxgig_struct import getpath, merge

config = merge([
    {'db': {'host': 'localhost', 'port': 5432}, 'debug': False},  # defaults
    {'db': {'host': 'db.internal'}, 'debug': True},               # overrides
])

getpath(config, 'db.host')   # 'db.internal'
getpath(config, 'db.port')   # 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Python-flavoured version:

```python
import voxgig_struct as S

# Reshape by example — the spec mirrors the output you want.
S.transform(
    {'user': {'first': 'Ada', 'last': 'Lovelace'}, 'age': 36},
    {'name': '`user.first`', 'surname': '`user.last`', 'years': '`age`'},
)
# {'name': 'Ada', 'surname': 'Lovelace', 'years': 36}

# Validate by example — leaves are type checkers; raises on mismatch.
S.validate({'name': 'Ada', 'age': 36}, {'name': '`$STRING`', 'age': '`$INTEGER`'})

# Walk the tree — replace values on ascent (after-callback, keyword arg).
S.walk(tree, after=lambda key, val, parent, path: 'DEFAULT' if val is None else val)

# Select children by query — each match tagged with its $KEY.
S.select({'a': {'age': 30}, 'b': {'age': 25}}, {'age': 30})
# [{'age': 30, '$KEY': 'a'}]
```

---

## 2. How-to guides

### Inject the API as an object (for stubbing in tests)
```python
from voxgig_struct import StructUtility
su = StructUtility()
su.getpath({'a': {'b': 1}}, 'a.b')   # 1
```
Every function is also a member of `StructUtility`, which is convenient
when a consumer wants to swap the implementation.

### Substitute references into a template (no reshaping)
```python
from voxgig_struct import inject
inject({'greeting': 'hello `name`'}, {'name': 'Ada'})
# {'greeting': 'hello Ada'}
```
`inject` is the substitution engine `transform` is built on; use it
directly when your spec *is* the output shape and you only need reference
expansion.

### Replace every null/empty in a tree
```python
from voxgig_struct import walk, isempty
walk(tree, after=lambda k, v, parent, path: '∅' if isempty(v) else v)
```
Pass callbacks by keyword: `before=` runs on descent, `after=` on ascent,
and `maxdepth=` bounds the recursion.

### Pick records out of a collection
```python
from voxgig_struct import select
select(users, {'role': 'admin'})   # matching maps, each tagged $KEY
select(some_list, {})              # all children (empty query matches all)
```

### Serialise deterministically
`jsonify` pretty-prints by default (indent 2); pass `{'indent': 0}` for compact.
`stringify` is the quote-light human form (keys sorted), for logs.

```python
from voxgig_struct import jsonify, stringify
jsonify(value)                    # pretty, 2-space indent (default)
jsonify(value, {'indent': 0})     # compact, insertion-ordered keys
stringify(value, 40)              # truncated human form, for logs
```

<!-- example: minor/jsonify#brace -->
```python
jsonify({'a': 1, 'b': [2, 3]})
# {
#   "a": 1,
#   "b": [
#     2,
#     3
#   ]
# }
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

### Build a URL from parts (Python extra)
```python
from voxgig_struct import joinurl
joinurl(['http:', '/foo/', '/bar'])   # 'http:/foo/bar' — collapses repeated '/'
```
`joinurl` and `replace` are Python convenience **extras**, not part of the
canonical set (see [Explanation](#4-explanation--port-specifics)).

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full Python signatures, with an example for every function, are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface is re-exported from
[`voxgig_struct/__init__.py`](./voxgig_struct/__init__.py); the parity tool
[`../tools/check_parity.py`](../tools/check_parity.py) checks that surface
against the canonical TypeScript `export` block.

Python-specific points the signatures don't show:

- **`None` is the only nil.** Inputs and outputs are "JSON-shaped"
  `dict` / `list` / `str` / `int` / `float` / `bool` / `None`. There is no
  static type narrowing; `isnode` / `ismap` / `islist` are plain `bool`
  predicates.
- **`UNDEF` sentinel.** Internally the port uses `UNDEF` (defined as `None`)
  to mean "absent". Optional arguments default to `UNDEF` rather than a
  bespoke marker, so `getprop(node, key)` returns `None` for a missing key
  exactly as the canonical returns `undefined`.
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` when the element is absent.
- **`items(node, apply=None)`** returns `[(key, val), …]` pairs; pass
  `apply` to map each pair through a function.
- **`walk` takes keyword arguments** — `before=`, `after=`, `maxdepth=` —
  where canonical TypeScript uses positional optionals. The trailing
  `key` / `parent` / `path` / `pool` parameters are recursion state;
  callers pass only `(val, …)`.
- **Type flags** combine bitwise: `typify('hi')` is `T_scalar | T_string`;
  test with `0 < (T_string & t)`. `typify(None)` is `T_scalar | T_null`.

---

## 4. Explanation & port specifics

### A port, not the source of truth

Behaviour is defined by the canonical TypeScript
([`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts))
and pinned by the shared corpus in [`../build/test/`](../build/test/). A
behaviour question is answered by reading the canonical, not this module; a
change to behaviour starts there and flows out to every port (see
[`../AGENTS.md`](../AGENTS.md)).

### `None`, `null`, and `UNDEF`

Python has only `None`, so it cannot natively distinguish the JSON `null`
scalar from "absent" — yet the library keeps them distinct. The port
bridges this with the internal `UNDEF` sentinel, and both `null` and
"absent" surface as `None` at the user-facing API. The
[Group A/B rule](../design/UNDEF_SPEC.md) still applies:

- **Group A — readers** (`getprop`, `getelem`, `haskey`, `isempty`,
  `isnode`): a stored `None` is treated as *no value*.
- **Group B — value processors** (`setprop`, `clone`, `walk`, `merge`,
  `inject`, `transform`, `validate`, `select`, …): `None` is preserved
  literally.

Because the host can't represent the two cases apart, the corpus uses the
string sentinel `"__NULL__"` for a real null (distinct from absent). When a
read/merge/clone test fails, check the Group A/B handling first.

### Lowercase, non-PEP8 names

Function names match the canonical TypeScript exactly — `getpath`,
`setpath`, `getprop`, … — deliberately **not** the PEP8 `get_path`. Parity
across ports beats local style here; the parity tool checks names
case/underscore-insensitively, but the source keeps the canonical casing so
call sites read identically across languages.

### Python-specific extras

Beyond the canonical set, the port ships two convenience helpers:
`replace(s, from_pat, to_str)` and `joinurl(parts)` (= `join(parts, '/',
True)`). They are *extras* for Python consumers, not part of the canonical
public surface, and are not what the parity tool checks.

### Regex

The Python port wraps the stdlib `re` module behind the uniform
six-function API (`re_compile` / `re_test` / `re_find` / `re_find_all` /
`re_replace` / `re_escape`). Stay inside the **RE2 subset** — `re` *allows*
backreferences and lookaround, but those won't port to the Go / Rust / C /
Lua / Zig engines. Two sharp edges (catastrophic backtracking on patterns
like `^(a+)+$`; zero-width `re_replace` returning `"XXbXcX"`) are detailed
in [`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd python
pip install -e .
make test           # python3 -m unittest discover -s tests
make lint           # ruff check + ruff format --check + mypy
```

Tests live in [`tests/`](./tests/); the runner
([`tests/runner.py`](./tests/runner.py)) loads the shared corpus from
[`../build/test/`](../build/test/) and asserts the same way every port's
runner does. The library has zero third-party runtime dependencies; dev
tooling needs `ruff>=0.9` and `mypy>=1.14`.

**To fix a port bug** (this port disagrees with the corpus): reproduce with
`make test`, read the failing corpus case, then change *this* module to
match the canonical TypeScript — never edit the corpus to make Python pass.
Re-run `make test` and `make lint`.

**Changing canonical behaviour starts in TypeScript, not here.** Edit the
canonical source and corpus first, then propagate to this port and re-run
`python3 ../tools/check_parity.py` plus the shared corpus suite. The full
checklist is in [`../AGENTS.md`](../AGENTS.md).
