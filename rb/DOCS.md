# Struct for Ruby

> Full-parity Ruby port of the canonical TypeScript implementation.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

In the monorepo:

```bash
cd rb
bundle install
```

The library is a single file: [`voxgig_struct.rb`](./voxgig_struct.rb).
Module: `VoxgigStruct`.

### A first transform

```ruby
require_relative 'voxgig_struct'

data = {
  'user' => { 'first' => 'Ada', 'last' => 'Lovelace' },
  'age'  => 36,
}

spec = {
  'name'    => '`user.first`',
  'surname' => '`user.last`',
  'years'   => '`age`',
}

puts VoxgigStruct.transform(data, spec).inspect
# {"name"=>"Ada", "surname"=>"Lovelace", "years"=>36}
```

### Validate

```ruby
VoxgigStruct.validate(out, {
  'name'    => '`$STRING`',
  'surname' => '`$STRING`',
  'years'   => '`$INTEGER`',
})
```


## How-to recipes

### Read a deep value safely

```ruby
VoxgigStruct.getpath('db.host', config)
VoxgigStruct.getprop(node, 'count', 0)
VoxgigStruct.getdef(maybe, 'fallback')
```

### Set a deep value

```ruby
store = {}
VoxgigStruct.setpath(store, 'db.host', 'localhost')
# store == { 'db' => { 'host' => 'localhost' } }
```

### Merge configs

```ruby
cfg = VoxgigStruct.merge([defaults, file, env])
```

### Walk a tree

```ruby
VoxgigStruct.walk(tree) do |key, val, parent, path|
  val.nil? ? 'DEFAULT' : val
end
```

### Inject and select

```ruby
VoxgigStruct.inject(
  { 'greeting' => 'hello `name`' },
  { 'name' => 'Ada' }
)

VoxgigStruct.select({ 'age' => 30 }, records)
```


## Reference

Source: [`voxgig_struct.rb`](./voxgig_struct.rb).  Module
`VoxgigStruct`.

### Method list

All 40 canonical functions, plus:

```
replace, joinurl, checkPlacement, injectorArgs, injectChild,
AND, OR, NOT, CMP   # select operators
```

### Constants

```ruby
VoxgigStruct::SKIP
VoxgigStruct::DELETE
VoxgigStruct::T_string  # ... 15 type constants
VoxgigStruct::M_KEYPRE
VoxgigStruct::M_KEYPOST
VoxgigStruct::M_VAL
VoxgigStruct::MODENAME
VoxgigStruct::UNDEF
```

### `Injection` class

Full implementation with `descend`, `child`, `setval` instance
methods.

### Tests

```bash
cd rb
make test           # 75/75 passing, 150 assertions
```


## Explanation

### `UNDEF`, `nil`, and JSON null

Ruby has `nil`.  JSON has both `null` and "absent".  The port uses:

- `nil` for JSON null.
- `VoxgigStruct::UNDEF` (a frozen sentinel object) for "absent".

`typify(nil)` returns `T_scalar | T_null`, distinct from `T_noval`
returned for `UNDEF`.  Unless you are writing custom transform
callbacks, you will only see `nil` in user-facing APIs.

### Method naming

The Ruby port uses lowercase method names (`getpath`, `setpath`,
`getprop`) matching the canonical API, not Ruby's idiomatic
snake_case.  Parity with other ports is the goal.

### Validate naming

The Ruby validate checkers use `$OBJECT` and `$ARRAY` rather than
`$MAP` and `$LIST` (matching Ruby JSON conventions).  All other
checker tokens are identical.

### Walk-based merge

`merge` is implemented as a `walk` with `before`/`after` callbacks
and a `maxdepth` parameter, matching the canonical algorithm.


## Build and test

```bash
cd rb
bundle install
make test
```

Tests live in [`test_voxgig_struct.rb`](./test_voxgig_struct.rb) and
consume fixtures from [`../build/test/`](../build/test/).
