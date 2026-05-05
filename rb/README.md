# Struct for Ruby

> Full-parity Ruby port of the canonical TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


## Install

In the monorepo:

```bash
cd rb
bundle install
```

The library is a single file: [`voxgig_struct.rb`](./voxgig_struct.rb).
Module: `VoxgigStruct`.

```ruby
require_relative 'voxgig_struct'
```


## Quick start

```ruby
require_relative 'voxgig_struct'

store = {
  'db'   => { 'host' => 'localhost' },
  'user' => { 'first' => 'Ada', 'last' => 'Lovelace' },
  'age'  => 36,
}

puts VoxgigStruct.getpath(store, 'db.host')
# localhost

puts VoxgigStruct.transform(store, {
  'name'    => '`user.first`',
  'surname' => '`user.last`',
  'years'   => '`age`',
}).inspect
# {"name"=>"Ada", "surname"=>"Lovelace", "years"=>36}

VoxgigStruct.validate(store, {
  'user' => {
    'first' => '`$STRING`',
    'last'  => '`$STRING`',
  },
  'age' => '`$INTEGER`',
})
```


## Function reference

Source: [`voxgig_struct.rb`](./voxgig_struct.rb).  Module
`VoxgigStruct`.

### Predicates

```ruby
VoxgigStruct.isnode(val)      # bool — map or list
VoxgigStruct.ismap(val)       # bool — Hash
VoxgigStruct.islist(val)      # bool — Array
VoxgigStruct.iskey(key)       # bool — non-empty String or Integer
VoxgigStruct.isempty(val)     # bool
VoxgigStruct.isfunc(val)      # bool — Proc/lambda
```

```ruby
VoxgigStruct.isnode({'a' => 1})       # true
VoxgigStruct.isnode([1])              # true
VoxgigStruct.ismap([])                # false
VoxgigStruct.islist([1, 2])           # true
VoxgigStruct.iskey('name')            # true
VoxgigStruct.isempty(nil)             # true
VoxgigStruct.isfunc(->(x) { x })      # true
```

### Type inspection

```ruby
VoxgigStruct.typify(value) -> Integer    # bit-field
VoxgigStruct.typename(t)   -> String     # human name
```

```ruby
VoxgigStruct.typify(42)                  # T_scalar | T_number | T_integer
VoxgigStruct.typify('hi')                # T_scalar | T_string
VoxgigStruct.typify(nil)                 # T_scalar | T_null
VoxgigStruct.typename(VoxgigStruct.typify('hi'))   # 'string'
```

### Size, slice, pad

```ruby
VoxgigStruct.size(val) -> Integer
VoxgigStruct.slice(val, start = nil, finish = nil, mutate = false)
VoxgigStruct.pad(str, padding = nil, padchar = nil) -> String
```

```ruby
VoxgigStruct.size([1, 2, 3])             # 3
VoxgigStruct.slice([1, 2, 3, 4, 5], 1, 4)  # [2, 3, 4]
VoxgigStruct.pad('hi', 5)                # 'hi   '
VoxgigStruct.pad('hi', -5, '*')          # '***hi'
```

### Property access

```ruby
VoxgigStruct.getprop(val, key, alt = UNDEF)
VoxgigStruct.setprop(parent, key, val)
VoxgigStruct.delprop(parent, key)
VoxgigStruct.getelem(val, key, alt = UNDEF)
VoxgigStruct.getdef(val, alt)
VoxgigStruct.haskey(val, key) -> bool
VoxgigStruct.keysof(val) -> Array
VoxgigStruct.items(val) -> Array
VoxgigStruct.strkey(key) -> String
```

```ruby
VoxgigStruct.getprop({'a' => 1}, 'a')           # 1
VoxgigStruct.getprop({}, 'b', 'fallback')       # 'fallback'
VoxgigStruct.setprop({'a' => 1}, 'b', 2)        # {'a'=>1, 'b'=>2}
VoxgigStruct.delprop({'a' => 1, 'b' => 2}, 'a') # {'b'=>2}
VoxgigStruct.getelem([1, 2, 3], -1)             # 3
VoxgigStruct.haskey({'a' => 1}, 'a')            # true
VoxgigStruct.keysof({'b' => 1, 'a' => 2})       # ['a', 'b']
VoxgigStruct.items({'a' => 1, 'b' => 2})        # [['a', 1], ['b', 2]]
```

### Path operations

```ruby
VoxgigStruct.getpath(store, path, injdef = nil)
VoxgigStruct.setpath(store, path, val, injdef = nil)
VoxgigStruct.pathify(val, startin = nil, endin = nil) -> String
```

```ruby
VoxgigStruct.getpath({'a' => {'b' => {'c' => 42}}}, 'a.b.c')   # 42
VoxgigStruct.getpath({'a' => [10, 20]}, 'a.1')                 # 20

store = {}
VoxgigStruct.setpath(store, 'db.host', 'localhost')
# store == {'db' => {'host' => 'localhost'}}

VoxgigStruct.pathify(['a', 'b', 'c'])           # 'a.b.c'
```

### Tree operations

```ruby
VoxgigStruct.walk(val, before = nil, after = nil, maxdepth = nil)
VoxgigStruct.merge(val, maxdepth = nil)
VoxgigStruct.clone(val)
VoxgigStruct.flatten(list, depth = nil)
VoxgigStruct.filter(val, check)
```

```ruby
after = ->(key, val, parent, path) { val.nil? ? 'DEFAULT' : val }
VoxgigStruct.walk(tree, nil, after)

VoxgigStruct.merge([
  { 'a' => 1, 'b' => 2 },
  { 'b' => 3, 'c' => 4 },
])
# { 'a' => 1, 'b' => 3, 'c' => 4 }

VoxgigStruct.clone({'a' => [1, 2]})
VoxgigStruct.flatten([1, [2, [3, [4]]]])
VoxgigStruct.filter({'a' => 1, 'b' => 2}, ->(kv) { kv[1] > 1 })
# [['b', 2]]
```

### String / URL / JSON

```ruby
VoxgigStruct.escre(s) -> String
VoxgigStruct.escurl(s) -> String
VoxgigStruct.join(arr, sep = nil, url = nil) -> String
VoxgigStruct.joinurl(parts) -> String
VoxgigStruct.jsonify(val, flags = nil) -> String
VoxgigStruct.stringify(val, maxlen = nil, pretty = nil) -> String
VoxgigStruct.replace(s, from, to) -> String
```

```ruby
VoxgigStruct.escre('a.b+c')                       # 'a\\.b\\+c'
VoxgigStruct.escurl('hello world')                # 'hello%20world'
VoxgigStruct.join(['a', 'b', 'c'], '/')           # 'a/b/c'
VoxgigStruct.jsonify({'a' => 1})                  # '{"a":1}'
VoxgigStruct.stringify({'a' => 1})                # 'a:1'
```

### Inject / transform / validate / select

```ruby
VoxgigStruct.inject(val, store, injdef = nil)
VoxgigStruct.transform(data, spec, injdef = nil)
VoxgigStruct.validate(data, spec, injdef = nil)
VoxgigStruct.select(children, query) -> Array
```

```ruby
VoxgigStruct.inject(
  { 'greeting' => 'hello `name`' },
  { 'name' => 'Ada' }
)
# { 'greeting' => 'hello Ada' }

VoxgigStruct.transform(
  { 'hold' => { 'x' => 1 }, 'top' => 99 },
  { 'a' => '`hold.x`', 'b' => '`top`' }
)
# { 'a' => 1, 'b' => 99 }

VoxgigStruct.validate({'name' => 'Ada'}, {'name' => '`$STRING`'})

VoxgigStruct.select(
  { 'a' => { 'age' => 30 }, 'b' => { 'age' => 25 } },
  { 'age' => 30 }
)
# [{ 'age' => 30, '$KEY' => 'a' }]
```

### Builders

```ruby
VoxgigStruct.jm(*kv) -> Hash
VoxgigStruct.jt(*v)  -> Array
```

```ruby
VoxgigStruct.jm('a', 1, 'b', 2)   # {'a' => 1, 'b' => 2}
VoxgigStruct.jt(1, 2, 3)          # [1, 2, 3]
```

### `Injection` class

Full implementation with `descend`, `child`, `setval` instance
methods.  Used internally by `inject`/`transform`/`validate`; you
need it when writing custom injectors.

### Injection helpers

```ruby
VoxgigStruct.checkPlacement(modes, ijname, parentTypes, inj)
VoxgigStruct.injectorArgs(argTypes, args)
VoxgigStruct.injectChild(child, store, inj)
```

### Select operators

The Ruby `select` supports compound query operators:

```
AND   OR   NOT   CMP
```

See [`voxgig_struct.rb`](./voxgig_struct.rb) for full operator
semantics.


## Constants

### Sentinels

```ruby
VoxgigStruct::SKIP
VoxgigStruct::DELETE
VoxgigStruct::UNDEF       # frozen sentinel object for "absent"
```

### Type bit-flags

```ruby
VoxgigStruct::T_any        VoxgigStruct::T_noval     VoxgigStruct::T_boolean
VoxgigStruct::T_decimal    VoxgigStruct::T_integer   VoxgigStruct::T_number
VoxgigStruct::T_string     VoxgigStruct::T_function  VoxgigStruct::T_symbol
VoxgigStruct::T_null       VoxgigStruct::T_list      VoxgigStruct::T_map
VoxgigStruct::T_instance   VoxgigStruct::T_scalar    VoxgigStruct::T_node
```

### Walk / inject phase flags

```ruby
VoxgigStruct::M_KEYPRE
VoxgigStruct::M_KEYPOST
VoxgigStruct::M_VAL
VoxgigStruct::MODENAME
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

The Ruby port also accepts the JSON-conventional aliases `$OBJECT`
and `$ARRAY` in place of `$MAP` and `$LIST`.


## Notes

### `UNDEF`, `nil`, and JSON null

Ruby has `nil`.  The port distinguishes:

- `nil` — JSON null (a defined scalar).
- `VoxgigStruct::UNDEF` — frozen sentinel for "absent".

`typify(nil)` returns `T_scalar | T_null`; `typify(UNDEF)` returns
`T_noval`.

### Method naming

Ruby method names match canonical lowercase (`getpath`, `setpath`,
`getprop`), not Ruby's idiomatic snake_case.  Parity beats style.

### Walk-based merge

`merge` is implemented as a `walk` with `before`/`after` callbacks
and a `maxdepth` parameter, matching the canonical algorithm.

### Test status

75/75 tests pass, 150 assertions.


## Build and test

```bash
cd rb
bundle install
make test
```

Tests in [`test_voxgig_struct.rb`](./test_voxgig_struct.rb) consume
fixtures from [`../build/test/`](../build/test/).
