# Struct for Python

> Full-parity Python port of the canonical TypeScript implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

The package is `voxgig_struct`.  Inside the monorepo:

```bash
cd py
pip install -e .
```

Or import directly from the source tree:

```python
import sys
sys.path.insert(0, '/path/to/struct/py')
from voxgig_struct import transform, validate
```

### A first transform

```python
from voxgig_struct import transform

data = {'user': {'first': 'Ada', 'last': 'Lovelace'}, 'age': 36}

spec = {
    'name': '`user.first`',
    'surname': '`user.last`',
    'years': '`age`',
}

print(transform(data, spec))
# {'name': 'Ada', 'surname': 'Lovelace', 'years': 36}
```

### Validate

```python
from voxgig_struct import validate

validate(out, {
    'name':    '`$STRING`',
    'surname': '`$STRING`',
    'years':   '`$INTEGER`',
})
```

`validate` returns the value on success and raises on mismatch.


## How-to recipes

### Read a deep value safely

```python
from voxgig_struct import getpath, getprop, getdef

getpath(config, 'db.host')            # value or None
getprop(node, 'count', 0)             # 0 if absent
getdef(maybe, 'fallback')             # returns maybe unless None
```

### Set a deep value, creating intermediate dicts

```python
from voxgig_struct import setpath

store = {}
setpath(store, 'db.host', 'localhost')
# store == {'db': {'host': 'localhost'}}
```

### Deep-merge a chain of dicts

```python
from voxgig_struct import merge

cfg = merge([defaults, file_config, env_overrides])
```

### Walk a tree (keyword args)

```python
from voxgig_struct import walk

def visit(key, val, parent, path):
    return 'DEFAULT' if val is None else val

# walk takes optional before/after callbacks; pass after to replace
# values once their children have been visited.
walk(tree, after=visit)
```

### Inject references into a template

```python
from voxgig_struct import inject

inject(
    {'greeting': 'hello `name`', 'age': '`years`'},
    {'name': 'Ada', 'years': 36},
)
# {'greeting': 'hello Ada', 'age': 36}
```

### Select records by query

```python
from voxgig_struct import select

select(
    {'a': {'name': 'Alice', 'age': 30}, 'b': {'name': 'Bob', 'age': 25}},
    {'age': 30},
)
# [{'name': 'Alice', 'age': 30, '$KEY': 'a'}]
```


## Reference

Source: [`voxgig_struct/voxgig_struct.py`](./voxgig_struct/voxgig_struct.py).

### Top-level imports

```python
from voxgig_struct import (
    # 40+ functions
    clone, delprop, escre, escurl, filter, flatten,
    getdef, getelem, getpath, getprop, haskey,
    inject, isempty, isfunc, iskey, islist, ismap, isnode,
    items, join, joinurl, jsonify, keysof, merge,
    pad, pathify, replace, select, setpath, setprop,
    size, slice, strkey, stringify, transform,
    typename, typify, validate, walk,

    # builders + aliases
    jm, jt, jo, ja,

    # injection helpers
    Injection, StructUtility,
    checkPlacement, injectorArgs, injectChild,

    # sentinels and constants
    SKIP, DELETE,
    T_any, T_noval, T_boolean, T_decimal, T_integer, T_number,
    T_string, T_function, T_symbol, T_null,
    T_list, T_map, T_instance, T_scalar, T_node,
    M_KEYPRE, M_KEYPOST, M_VAL,
)
```

### Major functions

```python
walk(val, before=None, after=None, maxdepth=None) -> any
merge(items, maxdepth=None) -> any
getpath(store, path, injdef=UNDEF) -> any
setpath(store, path, val) -> store
inject(val, store, modify=None) -> any
transform(data, spec, extra=None, modify=None) -> any
validate(data, spec, extra=None, collecterrs=None) -> any
select(children, query) -> list
```

### Python-specific extras

- `replace(s, from_pat, to_str)` -- explicit string/regex replace
  (internal in canonical TS).
- `joinurl(parts)` -- convenience for `join(parts, '/', True)`.
- `jo(...)` / `ja(...)` -- aliases for `jm` / `jt` ("JSON
  Object", "JSON Array").

### Sentinels and constants

- `SKIP`, `DELETE` -- transform/inject control sentinels.
- `T_*` -- 15 type bit-flags, returned by `typify(val)`.
- `M_KEYPRE`, `M_KEYPOST`, `M_VAL` -- walk/inject phase tags.

### Tests

```bash
cd py
make test           # 84/84 passing against the shared corpus
```


## Explanation

### `None`, `null`, and `UNDEF`

Python has a single `None`.  JSON distinguishes "absent" from "null".
The port treats absent values the same as `None` in most cases, and
the test fixtures use the string sentinels `__NULL__` and
`__UNDEFMARK__` where the distinction must be preserved.

```python
typify(None)   # T_scalar | T_null
```

The internal `UNDEF` sentinel is `None` in Python; this is a
deliberate choice for ergonomics.  See `voxgig_struct.py`:`UNDEF`.

### Walk uses keyword arguments

Where the canonical TS has positional optional arguments, the Python
port uses keyword arguments (`before=`, `after=`, `maxdepth=`).  This
is idiomatic Python and avoids ambiguity.

### Naming convention

Python uses lowercase function names matching the TS canonical
exactly: `getpath`, `setpath`, `getprop`.  PEP 8 would have suggested
`get_path`, but parity beats style here -- the same name in every
language is the whole point.

### Lists and dicts are mutated in place

Same rule as the canonical: `merge`, `setpath`, `inject` mutate
container values in place.  Pass a `clone` first if you need an
immutable input.


## Build and test

```bash
cd py
make test
```

Tests in [`tests/`](./tests/) read fixtures from
[`../build/test/`](../build/test/).
