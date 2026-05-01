# Struct for Python

> Full-parity Python port of the canonical TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


## Install

```bash
cd py
pip install -e .
```

Package: `voxgig_struct` (single module
[`voxgig_struct/voxgig_struct.py`](./voxgig_struct/voxgig_struct.py)).

Or, without installing, add the source directory to `sys.path`:

```python
import sys
sys.path.insert(0, '/path/to/struct/py')
from voxgig_struct import getpath, transform, validate
```


## Quick start

```python
from voxgig_struct import (
    getpath, setpath, merge, walk,
    inject, transform, validate, select,
)

getpath({'db': {'host': 'localhost'}}, 'db.host')
# 'localhost'

transform(
    {'user': {'first': 'Ada', 'last': 'Lovelace'}, 'age': 36},
    {'name': '`user.first`', 'surname': '`user.last`', 'years': '`age`'},
)
# {'name': 'Ada', 'surname': 'Lovelace', 'years': 36}

validate(
    {'name': 'Ada', 'age': 36},
    {'name': '`$STRING`', 'age': '`$INTEGER`'},
)
# {'name': 'Ada', 'age': 36}    (raises on mismatch)
```


## Imports

```python
from voxgig_struct import (
    # 40 canonical functions
    clone, delprop, escre, escurl, filter, flatten,
    getdef, getelem, getpath, getprop, haskey,
    inject, isempty, isfunc, iskey, islist, ismap, isnode,
    items, join, jsonify, keysof, merge,
    pad, pathify, select, setpath, setprop,
    size, slice, strkey, stringify, transform,
    typename, typify, validate, walk,

    # builders + Python aliases
    jm, jt, jo, ja,

    # extras (Python-specific convenience)
    replace, joinurl,

    # injection helpers
    Injection, StructUtility,
    checkPlacement, injectorArgs, injectChild,

    # sentinels and type constants
    SKIP, DELETE,
    T_any, T_noval, T_boolean, T_decimal, T_integer, T_number,
    T_string, T_function, T_symbol, T_null,
    T_list, T_map, T_instance, T_scalar, T_node,
    M_KEYPRE, M_KEYPOST, M_VAL,
)
```


## Function reference

Source: [`voxgig_struct/voxgig_struct.py`](./voxgig_struct/voxgig_struct.py).

### Predicates

```python
def isnode(val)            # bool — map or list
def ismap(val)             # bool — dict
def islist(val)            # bool — list
def iskey(key)             # bool — non-empty str or int
def isempty(val)           # bool — None/''/{}/[]
def isfunc(val)            # bool — callable
```

```python
isnode({'a': 1})          # True
ismap([])                 # False
islist([1])               # True
iskey('name')             # True
iskey('')                 # False
isempty(None)             # True
isempty([])               # True
isfunc(lambda: 1)         # True
```

### Type inspection

```python
def typify(value) -> int        # bit-field
def typename(t: int) -> str     # human name
```

```python
typify(42)                # T_scalar | T_number | T_integer
typify('hi')              # T_scalar | T_string
typify(None)              # T_scalar | T_null
typify({})                # T_node | T_map

typename(typify('hi'))    # 'string'
```

### Size, slice, pad

```python
def size(val) -> int
def slice(val, start=UNDEF, end=UNDEF, mutate=False) -> Any
def pad(s, padding=UNDEF, padchar=UNDEF) -> str
```

```python
size([1,2,3])             # 3
size({'a':1,'b':2})       # 2
size('abc')               # 3

slice([1,2,3,4,5], 1, 4)  # [2, 3, 4]
slice('abcdef', -3)       # 'def'

pad('hi', 5)              # 'hi   '
pad('hi', -5, '*')        # '***hi'
```

### Property access

```python
def getprop(val, key, alt=UNDEF) -> Any
def setprop(parent, key, val) -> parent
def delprop(parent, key) -> parent
def getelem(val, key, alt=UNDEF) -> Any
def getdef(val, alt) -> Any
def haskey(val, key) -> bool
def keysof(val) -> list[str]
def items(val, apply=None) -> list
def strkey(key) -> str
```

```python
getprop({'a': 1}, 'a')                # 1
getprop({'a': 1}, 'b', 'def')         # 'def'

setprop({'a': 1}, 'b', 2)             # {'a': 1, 'b': 2}
delprop({'a': 1, 'b': 2}, 'a')        # {'b': 2}
getelem([1,2,3], -1)                  # 3
getdef(None, 'fallback')              # 'fallback'
haskey({'a': 1}, 'a')                 # True
keysof({'b': 1, 'a': 2})              # ['a', 'b']
items({'a': 1, 'b': 2})               # [('a', 1), ('b', 2)]
strkey(1)                             # '1'
```

### Path operations

```python
def getpath(store, path, injdef=UNDEF) -> Any
def setpath(store, path, val, injdef=UNDEF) -> store
def pathify(val, startin=UNDEF, endin=UNDEF) -> str
```

```python
getpath({'a': {'b': {'c': 42}}}, 'a.b.c')      # 42
getpath({'a': [10, 20]}, 'a.1')                # 20

store = {}
setpath(store, 'db.host', 'localhost')
# store == {'db': {'host': 'localhost'}}

pathify(['a', 'b', 'c'])                       # 'a.b.c'
```

### Tree operations

```python
def walk(val, before=None, after=None, maxdepth=None,
         key=None, parent=None, path=None, pool=None) -> Any
def merge(objs, maxdepth=None) -> Any
def clone(val) -> Any
def flatten(lst, depth=None) -> list
def filter(val, check) -> list
```

```python
def visit(key, val, parent, path):
    return 'DEFAULT' if val is None else val

walk(tree, after=visit)

merge([
    {'a': 1, 'b': 2, 'x': {'y': 5, 'z': 6}},
    {'b': 3,         'x': {'y': 7}        },
])
# {'a': 1, 'b': 3, 'x': {'y': 7, 'z': 6}}

clone({'a': [1, 2]})            # deep copy
flatten([1, [2, [3, [4]]]])     # [1, 2, [3, [4]]]
filter({'a': 1, 'b': 2, 'c': 3}, lambda kv: kv[1] > 1)
# [('b', 2), ('c', 3)]
```

### String / URL / JSON

```python
def escre(s) -> str
def escurl(s) -> str
def join(arr, sep=UNDEF, url=UNDEF) -> str
def joinurl(parts) -> str         # convenience: join(parts, '/', True)
def jsonify(val, flags=None) -> str
def stringify(val, maxlen=UNDEF, pretty=None) -> str
def replace(s, from_pat, to_str) -> str
```

```python
escre('a.b+c')                       # 'a\\.b\\+c'
escurl('hello world')                # 'hello%20world'
join(['a','b','c'], '/')             # 'a/b/c'
joinurl(['http:', '/foo/', '/bar']) # 'http:/foo/bar'
jsonify({'a': 1, 'b': [2, 3]})       # '{"a":1,"b":[2,3]}'
stringify({'a': 1})                  # 'a:1'
```

### Inject / transform / validate / select

```python
def inject(val, store, injdef=UNDEF) -> Any
def transform(data, spec, injdef=UNDEF) -> Any
def validate(data, spec, injdef=UNDEF) -> Any
def select(children, query) -> list
```

```python
inject(
    {'greeting': 'hello `name`'},
    {'name': 'Ada'}
)
# {'greeting': 'hello Ada'}

transform(
    {'hold': {'x': 1}, 'top': 99},
    {'a': '`hold.x`', 'b': '`top`'}
)
# {'a': 1, 'b': 99}

validate({'name': 'Ada'}, {'name': '`$STRING`'})

select(
    {'a': {'age': 30}, 'b': {'age': 25}},
    {'age': 30}
)
# [{'age': 30, '$KEY': 'a'}]
```

### Builders and aliases

```python
jm('a', 1, 'b', 2)        # {'a': 1, 'b': 2}
jt(1, 2, 3)               # [1, 2, 3]

# Aliases (Python "JSON Object" / "JSON Array")
jo(*args)   # alias for jm
ja(*args)   # alias for jt
```

### Injection helpers

```python
def checkPlacement(modes, ijname, parentTypes, inj) -> bool
def injectorArgs(argTypes, args) -> Any
def injectChild(child, store, inj) -> Injection
```


## Constants

### Sentinels

```python
SKIP        # emit nothing for this key
DELETE      # remove this key from the parent
```

### Type bit-flags

```python
T_any T_noval T_boolean T_decimal T_integer T_number T_string
T_function T_symbol T_null T_list T_map T_instance T_scalar T_node
```

### Walk / inject phase flags

```python
M_KEYPRE   M_KEYPOST   M_VAL
```


## Transform commands

```
$DELETE  $COPY    $KEY     $META    $ANNO
$MERGE   $EACH    $PACK    $REF     $FORMAT  $APPLY
```


## Validate checkers

```
$MAP   $LIST   $STRING   $NUMBER   $INTEGER   $DECIMAL  $BOOLEAN
$NULL  $NIL    $FUNCTION $INSTANCE $ANY       $CHILD    $ONE     $EXACT
```


## Notes

### `None`, `null`, and `UNDEF`

Python has only `None`.  Internally the port uses an `UNDEF` sentinel
(`= None` for ergonomics) to mean "absent".  JSON null and "absent"
both map to `None` at the user-facing API.

`typify(None)` returns `T_scalar | T_null`.  Where the test corpus
needs to disambiguate, the runner uses string sentinels `__NULL__`
and `__UNDEFMARK__`.

### Walk uses keyword arguments

Where canonical TypeScript has positional optional parameters, the
Python port uses keyword arguments.  For example:

```python
walk(tree, before=None, after=visit, maxdepth=10)
```

### Lowercase function names

Function names match canonical TypeScript exactly: `getpath`,
`setpath`, `getprop`, etc.  PEP 8 would suggest `get_path`, but
parity with other ports beats style here.

### Test status

84/84 tests pass against the shared corpus.


## Build and test

```bash
cd py
make test
```

Tests live in [`tests/`](./tests/) and read fixtures from
[`../build/test/`](../build/test/).
