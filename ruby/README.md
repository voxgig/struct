# Struct for Ruby

> Full-parity Ruby port of the canonical TypeScript implementation.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


## Install

In the monorepo:

```bash
cd ruby
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

<!-- example: minor/isnode#map -->
```ruby
VoxgigStruct.isnode({'a' => 1})       # true
```
<!-- => true -->

```ruby
VoxgigStruct.isnode([1])              # true
```

<!-- example: minor/ismap#map -->
```ruby
VoxgigStruct.ismap({'a' => 1})        # true
```

<!-- => true -->

```ruby
VoxgigStruct.ismap([])                # false
```

<!-- example: minor/islist#list -->
```ruby
VoxgigStruct.islist([1, 2])           # true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```ruby
VoxgigStruct.iskey('name')            # true
```

<!-- => true -->

<!-- example: minor/isempty#empty -->
```ruby
VoxgigStruct.isempty([])              # true
```

<!-- => true -->

```ruby
VoxgigStruct.isempty(nil)             # true
VoxgigStruct.isfunc(->(x) { x })      # true
```

### Type inspection

```ruby
VoxgigStruct.typify(value) -> Integer    # bit-field
VoxgigStruct.typename(t)   -> String     # human name
```

<!-- example: minor/typify#int -->
```ruby
VoxgigStruct.typify(1)                   # T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

```ruby
VoxgigStruct.typify(42)                  # T_scalar | T_number | T_integer
VoxgigStruct.typify('hi')                # T_scalar | T_string
VoxgigStruct.typify(nil)                 # T_scalar | T_null
```

<!-- example: minor/typename#map -->
```ruby
VoxgigStruct.typename(8192)              # 'map'  (8192 == T_map)
```

<!-- => "map" -->

```ruby
VoxgigStruct.typename(VoxgigStruct.typify('hi'))   # 'string'
```

### Size, slice, pad

```ruby
VoxgigStruct.size(val) -> Integer
VoxgigStruct.slice(val, start = nil, finish = nil, mutate = false)
VoxgigStruct.pad(str, padding = nil, padchar = nil) -> String
```

<!-- example: minor/size#three -->
```ruby
VoxgigStruct.size([1, 2, 3])             # 3
```
<!-- => 3 -->

`slice` keeps the first *N*; a negative `start` drops the last *|start|*
items, and `finish` is exclusive:

<!-- example: minor/slice#mid -->
```ruby
VoxgigStruct.slice([1, 2, 3, 4, 5], 1, 4)  # [2, 3, 4]
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```ruby
VoxgigStruct.slice('abcdef', -3)         # 'abc'  (drops the last 3)
```
<!-- => "abc" -->

<!-- example: minor/pad#right -->
```ruby
VoxgigStruct.pad('a', 3)                 # 'a  '
```
<!-- => "a  " -->

```ruby
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

<!-- example: minor/getprop#hit -->
```ruby
VoxgigStruct.getprop({'x' => 1}, 'x')           # 1
```
<!-- => 1 -->

```ruby
VoxgigStruct.getprop({}, 'b', 'fallback')       # 'fallback'
```

<!-- example: minor/setprop#set -->
```ruby
VoxgigStruct.setprop({'a' => 1}, 'b', 2)        # {'a'=>1, 'b'=>2}
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```ruby
VoxgigStruct.delprop({'a' => 1, 'b' => 2}, 'a') # {'b'=>2}
```

<!-- => {"b": 2} -->

<!-- example: minor/getelem#neg -->
```ruby
VoxgigStruct.getelem([10, 20, 30], -1)          # 30
```

<!-- => 30 -->

<!-- example: minor/haskey#hit -->
```ruby
VoxgigStruct.haskey({'a' => 1}, 'a')            # true
```

<!-- => true -->

<!-- example: minor/items#map -->
```ruby
VoxgigStruct.items({'a' => 1, 'b' => 2})        # [['a', 1], ['b', 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

<!-- example: minor/strkey#num -->
```ruby
VoxgigStruct.strkey(2.2)                         # '2'
```

<!-- => "2" -->

```ruby
VoxgigStruct.strkey(1)                           # '1'
VoxgigStruct.strkey('foo')                       # 'foo'
```

<!-- example: minor/keysof#sorted -->
```ruby
VoxgigStruct.keysof({'b' => 4, 'a' => 5})       # ['a', 'b']  (sorted)
```
<!-- => ["a", "b"] -->

### Path operations

```ruby
VoxgigStruct.getpath(store, path, injdef = nil)
VoxgigStruct.setpath(store, path, val, injdef = nil)
VoxgigStruct.pathify(val, startin = nil, endin = nil) -> String
```

<!-- example: getpath/basic#deep -->
```ruby
VoxgigStruct.getpath({'a' => {'b' => {'c' => 42}}}, 'a.b.c')   # 42
```
<!-- => 42 -->

```ruby
VoxgigStruct.getpath({'a' => [10, 20]}, 'a.1')                 # 20

store = {}
VoxgigStruct.setpath(store, 'db.host', 'localhost')
# store == {'db' => {'host' => 'localhost'}}
```

<!-- example: minor/setpath#nested -->
```ruby
VoxgigStruct.setpath({'a' => 1, 'b' => 2}, 'b', 22)            # {'a'=>1, 'b'=>22}
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```ruby
VoxgigStruct.pathify(['a', 'b', 'c'])           # 'a.b.c'
```

<!-- => "a.b.c" -->

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
```

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```ruby
VoxgigStruct.merge([
  { 'a' => 1, 'b' => 2, 'k' => [10, 20], 'x' => { 'y' => 5, 'z' => 6 } },
  { 'b' => 3, 'd' => 4, 'e' => 8, 'k' => [11], 'x' => { 'y' => 7 } },
])
# { 'a' => 1, 'b' => 3, 'd' => 4, 'e' => 8, 'k' => [11, 20], 'x' => { 'y' => 7, 'z' => 6 } }
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```ruby
VoxgigStruct.clone({ 'a' => { 'b' => [1, 2] } })   # { 'a' => { 'b' => [1, 2] } }  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```ruby
VoxgigStruct.flatten([1, [2, [3]]])                # [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

```ruby
VoxgigStruct.flatten([1, [2, [3, [4]]]])           # [1, 2, [3, [4]]]
```

`filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```ruby
VoxgigStruct.filter([1, 2, 3, 4, 5], ->(kv) { kv[1] > 3 })
# [4, 5]
```
<!-- => [4, 5] -->

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

<!-- example: minor/escre#dots -->
```ruby
VoxgigStruct.escre('a.b+c')                       # 'a\\.b\\+c'
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```ruby
VoxgigStruct.escurl('hello world?')               # 'hello%20world%3F'
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```ruby
VoxgigStruct.join(['a', 'b', 'c'], '/')           # 'a/b/c'
```

<!-- => "a/b/c" -->

`jsonify` pretty-prints by default (indent 2); pass `{ 'indent' => 0 }` for
the compact form:

<!-- example: minor/jsonify#map -->
```ruby
VoxgigStruct.jsonify({'a' => 1})
# {
#   "a": 1
# }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#compact -->
```ruby
VoxgigStruct.jsonify({'a' => 1, 'b' => 2}, { 'indent' => 0 })  # '{"a":1,"b":2}'
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```ruby
VoxgigStruct.stringify({'a' => 1, 'b' => [2, 3]})  # '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```ruby
VoxgigStruct.stringify('verylongstring', 5)        # 've...'
```
<!-- => "ve..." -->

### Inject / transform / validate / select

```ruby
VoxgigStruct.inject(val, store, injdef = nil)
VoxgigStruct.transform(data, spec, injdef = nil)
VoxgigStruct.validate(data, spec, injdef = nil)
VoxgigStruct.select(children, query) -> Array
```

<!-- example: inject#basic -->
```ruby
# Backtick refs in strings are replaced by store values.
VoxgigStruct.inject({ 'x' => '`a`', 'y' => 2 }, { 'a' => 1 })   # { 'x' => 1, 'y' => 2 }
```

<!-- => {"x": 1, "y": 2} -->

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
```

Transform commands drive structural ops. A command like `$EACH` appears in
**value** position — as the first element of a list
`['`$EACH`', path, subspec]` — mapping the sub-spec over every entry at
`path`:

<!-- example: transform/each#basic -->
```ruby
VoxgigStruct.transform(
  { 'v' => 1, 'a' => [{ 'q' => 13 }, { 'q' => 23 }] },
  { 'x' => { 'y' => ['`$EACH`', 'a', { 'q' => '`$COPY`', 'r' => '`.q`', 'p' => '`...v`' }] } }
)
# { 'x' => { 'y' => [{ 'q' => 13, 'r' => 13, 'p' => 1 }, { 'q' => 23, 'r' => 23, 'p' => 1 }] } }
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a
map) is an error — commands must be list values:

<!-- example: transform/apply#badkey -->
```ruby
VoxgigStruct.transform({}, { 'x' => '`$APPLY`' })
# raises: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

<!-- example: validate#shape -->
```ruby
# Validate against a shape (raises on mismatch).
VoxgigStruct.validate(
  { 'name' => 'Ada', 'age' => 36 },
  { 'name' => '`$STRING`', 'age' => '`$INTEGER`' }
)
# { 'name' => 'Ada', 'age' => 36 }
```

<!-- => {"name": "Ada", "age": 36} -->

<!-- example: select#query -->
```ruby
# Find children matching a query.
VoxgigStruct.select(
  { 'a' => { 'name' => 'Alice', 'age' => 30 }, 'b' => { 'name' => 'Bob', 'age' => 25 } },
  { 'age' => 30 }
)
# [{ 'name' => 'Alice', 'age' => 30, '$KEY' => 'a' }]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->

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

81 runs, 159 assertions, 0 failures.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The Ruby port
wraps the built-in `Regexp` (Onigmo engine).

### API

| Function | Maps to |
|---|---|
| `re_compile(pattern)`              | `Regexp.new(pattern)` |
| `re_test(pattern, input)`          | `input =~ re` |
| `re_find(pattern, input)`          | `input.match(re)` → `[whole, group1, ...]` |
| `re_find_all(pattern, input)`      | `input.scan(re)` (one row per match) |
| `re_replace(pattern, input, repl)` | `input.gsub(re, repl)` |
| `re_escape(s)`                     | `Regexp.escape(s)` |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
Onigmo supports backreferences and lookaround; using them will not be
portable to the Go / Rust / C / Lua / Zig ports.

### Sharp edges

- **Catastrophic backtracking.** Onigmo has internal mitigations for
  some classic ReDoS shapes — `^(a+)+$` against 22 a's plus `!` runs
  in microseconds here. Larger inputs or different shapes can still
  blow up; the safe rule is to stay inside the RE2 subset and avoid
  nested quantifiers.
- **Zero-width `replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd ruby
bundle install
make test
```

Tests in [`test_voxgig_struct.rb`](./test_voxgig_struct.rb) consume
fixtures from [`../build/test/`](../build/test/).
