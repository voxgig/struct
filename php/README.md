# Struct for PHP

> Full-parity PHP port of the canonical TypeScript implementation.
> All functionality is exposed as static methods on `Voxgig\Struct\Struct`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../design/REPORT.md).


## Install

```bash
composer require voxgig/struct
```

In the monorepo:

```bash
cd php
composer install
```

Namespace: `Voxgig\Struct`.  All API is on the `Struct` class.


## Quick start

```php
<?php
require 'vendor/autoload.php';

use Voxgig\Struct\Struct;

$store = [
    'db'   => ['host' => 'localhost'],
    'user' => ['first' => 'Ada', 'last' => 'Lovelace'],
    'age'  => 36,
];

echo Struct::getpath($store, 'db.host'), PHP_EOL;
// localhost

print_r(Struct::transform($store, [
    'name'    => '`user.first`',
    'surname' => '`user.last`',
    'years'   => '`age`',
]));
// Array ( [name] => Ada [surname] => Lovelace [years] => 36 )

Struct::validate($store, [
    'user' => [
        'first' => '`$STRING`',
        'last'  => '`$STRING`',
    ],
    'age' => '`$INTEGER`',
]);
```


## Function reference

Source: [`src/Struct.php`](./src/Struct.php).  All methods are
`public static`.

### Predicates

```php
Struct::isnode($val)      // map or list
Struct::ismap($val)       // associative array
Struct::islist($val)      // numerically-indexed array
Struct::iskey($key)       // non-empty string or int
Struct::isempty($val)     // null/''/[]
Struct::isfunc($val)      // callable
```

<!-- example: minor/isnode#map -->
```php
Struct::isnode(['a' => 1]);          // true
```
<!-- => true -->

<!-- example: minor/ismap#map -->
```php
Struct::ismap(['a' => 1]);           // true
```

<!-- => true -->

```php
Struct::ismap([1, 2]);                // false
```

<!-- example: minor/islist#list -->
```php
Struct::islist([1, 2]);               // true
```

<!-- => true -->

<!-- example: minor/iskey#str -->
```php
Struct::iskey('name');                // true
```

<!-- => true -->

```php
Struct::iskey('');                    // false
```

<!-- example: minor/isempty#empty -->
```php
Struct::isempty([]);                  // true
```

<!-- => true -->

```php
Struct::isempty(null);                // true
Struct::isfunc(fn() => 1);            // true
```

### Type inspection

```php
Struct::typify($value): int          // bit-field
Struct::typename($t): string         // human name
```

<!-- example: minor/typify#int -->
```php
Struct::typify(1);                    // T_scalar | T_number | T_integer  (201326720)
```

<!-- => 201326720 -->

```php
Struct::typify(42);                   // T_scalar | T_number | T_integer
Struct::typify('hi');                 // T_scalar | T_string
```

<!-- example: minor/typename#map -->
```php
Struct::typename(8192);               // 'map'  (8192 === T_map)
```

<!-- => "map" -->

```php
Struct::typename(Struct::typify('hi'));  // 'string'
```

### Size, slice, pad

```php
Struct::size($val): int
Struct::slice($val, $start = null, $end = null, $mutate = false)
Struct::pad($str, $padding = null, $padchar = null): string
```

<!-- example: minor/size#three -->
```php
Struct::size([1, 2, 3]);               // 3
```
<!-- => 3 -->

`slice` keeps the first *N*; a negative `$start` drops the last *|start|*
items, and `$end` is exclusive:

<!-- example: minor/slice#mid -->
```php
Struct::slice([1, 2, 3, 4, 5], 1, 4);  // [2, 3, 4]
```
<!-- => [2, 3, 4] -->

<!-- example: minor/slice#strhead -->
```php
Struct::slice('abcdef', -3);           // 'abc'  (drops the last 3)
```
<!-- => "abc" -->

<!-- example: minor/pad#right -->
```php
Struct::pad('a', 3);                   // 'a  '
```
<!-- => "a  " -->

```php
Struct::pad('hi', 5);                  // 'hi   '
Struct::pad('hi', -5, '*');            // '***hi'
```

### Property access

```php
Struct::getprop($val, $key, $alt = null)
Struct::setprop(&$parent, $key, $val)        // by reference!
Struct::delprop($parent, $key)               // by value; returns the parent
Struct::getelem($val, $key, $alt = null)
Struct::getdef($val, $alt)
Struct::haskey($val, $key): bool
Struct::keysof($val): array
Struct::items($val): array
Struct::strkey($key): string
```

<!-- example: minor/getprop#hit -->
```php
Struct::getprop(['a' => 1], 'a');                  // 1
```
<!-- => 1 -->

```php
Struct::getprop([], 'b', 'fallback');              // 'fallback'
```

<!-- example: minor/setprop#set -->
```php
$node = ['a' => 1];
Struct::setprop($node, 'b', 2);
// $node === ['a' => 1, 'b' => 2]
```

<!-- => {"a": 1, "b": 2} -->

<!-- example: minor/delprop#del -->
```php
Struct::delprop(['a' => 1, 'b' => 2], 'a');        // ['b' => 2]
```

<!-- => {"b": 2} -->

<!-- example: minor/getelem#neg -->
```php
Struct::getelem([10, 20, 30], -1);                 // 30
```

<!-- => 30 -->

<!-- example: minor/haskey#hit -->
```php
Struct::haskey(['a' => 1], 'a');                   // true
```

<!-- => true -->

<!-- example: minor/keysof#sorted -->
```php
Struct::keysof(['b' => 4, 'a' => 5]);              // ['a', 'b']  (sorted)
```
<!-- => ["a", "b"] -->

<!-- example: minor/items#map -->
```php
Struct::items(['a' => 1, 'b' => 2]);
// [['a', 1], ['b', 2]]
```

<!-- => [["a", 1], ["b", 2]] -->

<!-- example: minor/strkey#num -->
```php
Struct::strkey(2.2);                               // '2'
```

<!-- => "2" -->

### Path operations

```php
Struct::getpath($store, $path, $injdef = null)
Struct::setpath($store, $path, $val, $injdef = null)   // by value; returns the updated immediate parent
Struct::pathify($val, $startin = null, $endin = null): string
```

<!-- example: getpath/basic#deep -->
```php
Struct::getpath(['a' => ['b' => ['c' => 42]]], 'a.b.c');  // 42
```
<!-- => 42 -->

```php
Struct::getpath(['a' => [10, 20]], 'a.1');                // 20

// setpath takes $store BY VALUE and returns the updated immediate parent,
// so $store itself is NOT mutated — assign the return value.
$store = [];
$parent = Struct::setpath($store, 'db.host', 'localhost');
// $store stays []; $parent === (object)['host' => 'localhost']
```

<!-- example: minor/setpath#nested -->
```php
Struct::setpath(['a' => 1, 'b' => 2], 'b', 22);           // ['a' => 1, 'b' => 22]
```

<!-- => {"a": 1, "b": 22} -->

<!-- example: minor/pathify#parts -->
```php
Struct::pathify(['a', 'b', 'c']);                          // 'a.b.c'
```

<!-- => "a.b.c" -->

### Tree operations

```php
Struct::walk($val, $before = null, $after = null, $maxdepth = null)
Struct::merge($val, $maxdepth = null)
Struct::clone($val)
Struct::cloneWrap($val)        // with ListRef wrapping
Struct::cloneUnwrap($val)
Struct::flatten($list, $depth = null)
Struct::filter($val, $check)
```

```php
Struct::walk($tree, null, function ($key, $val, $parent, $path) {
    return $val === null ? 'DEFAULT' : $val;
});
```

Last input wins; maps deep-merge; lists merge by index:

<!-- example: merge#basic -->
```php
Struct::merge([
    ['a' => 1, 'b' => 2, 'k' => [10, 20], 'x' => ['y' => 5, 'z' => 6]],
    ['b' => 3, 'd' => 4, 'e' => 8, 'k' => [11], 'x' => ['y' => 7]],
]);
// ['a' => 1, 'b' => 3, 'd' => 4, 'e' => 8, 'k' => [11, 20], 'x' => ['y' => 7, 'z' => 6]]
```

<!-- => {"a": 1, "b": 3, "d": 4, "e": 8, "k": [11, 20], "x": {"y": 7, "z": 6}} -->

<!-- example: minor/clone#deep -->
```php
Struct::clone(['a' => ['b' => [1, 2]]]);   // ['a' => ['b' => [1, 2]]]  (a deep copy)
```

<!-- => {"a": {"b": [1, 2]}} -->

<!-- example: minor/flatten#nested -->
```php
Struct::flatten([1, [2, [3]]]);            // [1, 2, [3]]  (one level by default)
```

<!-- => [1, 2, [3]] -->

```php
Struct::flatten([1, [2, [3, [4]]]]);       // [1, 2, [3, [4]]]
```

`filter` passes each `[key, value]` pair to the check and returns the
matching **values** (not the pairs):

<!-- example: minor/filter#gt3 -->
```php
Struct::filter([1, 2, 3, 4, 5], fn($kv) => $kv[1] > 3);
// [4, 5]
```
<!-- => [4, 5] -->

### String / URL / JSON

```php
Struct::escre($s): string
Struct::escurl($s): string
Struct::join($arr, $sep = null, $url = null): string
Struct::joinurl($parts): string
Struct::jsonify($val, $flags = null): string
Struct::stringify($val, $maxlen = null, $pretty = null): string
Struct::replace($s, $from, $to): string
```

<!-- example: minor/escre#dots -->
```php
Struct::escre('a.b+c');                   // 'a\\.b\\+c'
```

<!-- => "a\\.b\\+c" -->

<!-- example: minor/escurl#space -->
```php
Struct::escurl('hello world?');           // 'hello%20world%3F'
```

<!-- => "hello%20world%3F" -->

<!-- example: minor/join#sep -->
```php
Struct::join(['a', 'b', 'c'], '/');       // 'a/b/c'
```

<!-- => "a/b/c" -->

```php
Struct::joinurl(['http:', '/foo/']);      // 'http:/foo/'
```

`jsonify` pretty-prints by default (indent 2); pass `(object)['indent' => 0]`
for the compact form:

<!-- example: minor/jsonify#map -->
```php
Struct::jsonify(['a' => 1]);
// {
//   "a": 1
// }
```
<!-- => "{\n  \"a\": 1\n}" -->

<!-- example: minor/jsonify#brace -->
```php
Struct::jsonify(['a' => 1, 'b' => [2, 3]]);
// {
//   "a": 1,
//   "b": [
//     2,
//     3
//   ]
// }
```
<!-- => "{\n  \"a\": 1,\n  \"b\": [\n    2,\n    3\n  ]\n}" -->

<!-- example: minor/jsonify#compact -->
```php
Struct::jsonify(['a' => 1, 'b' => 2], (object)['indent' => 0]);  // '{"a":1,"b":2}'
```
<!-- => "{\"a\":1,\"b\":2}" -->

`stringify` is the compact, quote-light form — keys are sorted and object
braces are kept; the second argument caps the length (the `...` counts):

<!-- example: minor/stringify#brace -->
```php
Struct::stringify(['a' => 1, 'b' => [2, 3]]);   // '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

<!-- example: minor/stringify#max -->
```php
Struct::stringify('verylongstring', 5);          // 've...'
```
<!-- => "ve..." -->

### Inject / transform / validate / select

```php
Struct::inject($val, $store, $injdef = null)
Struct::transform($data, $spec, $injdef = null)
Struct::validate($data, $spec, $injdef = null)
Struct::select($children, $query): array
```

<!-- example: inject#basic -->
```php
// Backtick refs in strings are replaced by store values.
Struct::inject(['x' => '`a`', 'y' => 2], ['a' => 1]);   // ['x' => 1, 'y' => 2]
```

<!-- => {"x": 1, "y": 2} -->

```php
Struct::inject(
    ['greeting' => 'hello `name`'],
    ['name' => 'Ada']
);
// ['greeting' => 'hello Ada']

Struct::transform(
    ['hold' => ['x' => 1], 'top' => 99],
    ['a' => '`hold.x`', 'b' => '`top`']
);
// ['a' => 1, 'b' => 99]
```

A transform command like `$EACH` appears in **value** position — as the first
element of a list `['`$EACH`', path, subspec]` — mapping the sub-spec over every
entry at `path`:

<!-- example: transform/each#basic -->
```php
Struct::transform(
    ['v' => 1, 'a' => [['q' => 13], ['q' => 23]]],
    ['x' => ['y' => ['`$EACH`', 'a', ['q' => '`$COPY`', 'r' => '`.q`', 'p' => '`...v`']]]]
);
// ['x' => ['y' => [['q' => 13, 'r' => 13, 'p' => 1], ['q' => 23, 'r' => 23, 'p' => 1]]]]
```
<!-- => {"x": {"y": [{"q": 13, "r": 13, "p": 1}, {"q": 23, "r": 23, "p": 1}]}} -->

Putting a command in **key** position (or, for `$APPLY`, directly under a map)
is an error — commands must be list values:

<!-- example: transform/apply#badkey -->
```php
Struct::transform([], ['x' => '`$APPLY`']);
// throws \Exception: $APPLY: invalid placement in parent map, expected: list.
```
<!-- throws: invalid placement in parent map -->

<!-- example: validate#shape -->
```php
// Validate against a shape (throws on mismatch).
Struct::validate(['name' => 'Ada', 'age' => 36], ['name' => '`$STRING`', 'age' => '`$INTEGER`']);
// ['name' => 'Ada', 'age' => 36]
```

<!-- => {"name": "Ada", "age": 36} -->

```php
Struct::validate(['name' => 'Ada'], ['name' => '`$STRING`']);
// throws \Exception on mismatch (or accumulates if you pass
// an errs collector on the $injdef object)
```

<!-- example: select#query -->
```php
// Find children matching a query.
Struct::select(
    ['a' => ['name' => 'Alice', 'age' => 30], 'b' => ['name' => 'Bob', 'age' => 25]],
    ['age' => 30]
);
// [['name' => 'Alice', 'age' => 30, '$KEY' => 'a']]
```

<!-- => [{"name": "Alice", "age": 30, "$KEY": "a"}] -->

### Builders

```php
Struct::jm(...$kv): object   // builds a stdClass map
Struct::jt(...$v): array
```

```php
Struct::jm('a', 1, 'b', 2);   // (object)['a' => 1, 'b' => 2]  (stdClass)
Struct::jt(1, 2, 3);          // [1, 2, 3]
```

### Injection helpers

```php
Struct::checkPlacement($modes, $ijname, $parentTypes, $inj): bool
Struct::injectorArgs($argTypes, $args)
Struct::injectChild($child, $store, $inj)
```

### `ListRef`

Wrapper class giving a list reference semantics across calls that
would otherwise copy it.  Used internally; you only need it when
writing custom `Modify` callbacks that mutate lists.

```php
use Voxgig\Struct\ListRef;
$ref = new ListRef([1, 2, 3]);
```


## Constants

### Sentinels

```php
Struct::SKIP
Struct::DELETE
```

### Type bit-flags

```php
Struct::T_any        Struct::T_noval     Struct::T_boolean
Struct::T_decimal    Struct::T_integer   Struct::T_number
Struct::T_string     Struct::T_function  Struct::T_symbol
Struct::T_null       Struct::T_list      Struct::T_map
Struct::T_instance   Struct::T_scalar    Struct::T_node
```

### Walk / inject phase flags

```php
Struct::M_KEYPRE   Struct::M_KEYPOST   Struct::M_VAL
Struct::MODENAME
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

### `UNDEF` is a string sentinel

PHP has no separate "undefined" keyword.  Internally the port uses
the string `'__UNDEFINED__'` (`Struct::UNDEF`) as a sentinel for
absent values.  User-facing APIs accept `null` and return `null`,
so you usually do not see it directly.

### Arrays are value types

PHP arrays copy on assignment.  Two adaptations preserve canonical
"reference-stable list" semantics:

1. `setprop` takes its parent **by reference** (`&$parent`) and mutates
   in place. `setpath` and `delprop` take their argument **by value** and
   **return** the updated structure — assign the result.
2. The `ListRef` class wraps a list when it must be shared across
   calls (notably during `merge` and `inject`).

### Maps and lists in PHP

PHP has only the array type, which can be associative ("map") or
numerically indexed ("list").  `struct` distinguishes them with
`Struct::ismap` / `Struct::islist`.  An array with non-sequential
numeric keys is treated as a map.

### Method casing

PHP method names match canonical lowercase: `getpath`, `setpath`,
`getprop`.  This breaks PSR-12 camelCase, but parity beats style.

### `validate` error reporting

`Struct::validate`:

- returns the value on success;
- throws a plain `\Exception` carrying all accumulated errors (joined with
  ` | `, prefixed `Invalid data:`) by default;
- accumulates into a passed errors array when you supply one.

### Test status

85/85 tests pass, 1022 assertions.


## Regex

Uniform six-function regex API (see `/design/REGEX_API.md`). The PHP port
wraps PCRE (`preg_*`).

### API

| Function | Maps to |
|---|---|
| `re_compile(pattern)`              | delimited PCRE pattern (validated via `preg_match`) |
| `re_test(pattern, input)`          | `preg_match` → bool |
| `re_find(pattern, input)`          | `preg_match` with captures, returns `[whole, group1, ...]` or `null` |
| `re_find_all(pattern, input)`      | `preg_match_all(..., PREG_SET_ORDER)` |
| `re_replace(pattern, input, repl)` | `preg_replace` (or `preg_replace_callback` for callable repl) |
| `re_escape(s)`                     | `preg_quote(s)` equivalent |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/design/REGEX.md`.
PCRE supports backreferences and lookaround; using them will not be
portable.

### Sharp edges

- **`re_compile` validates eagerly.** Invalid patterns throw
  `InvalidArgumentException` at compile time. This is a recent fix:
  the wrapper used to swallow PCRE warnings via `@preg_match` and
  return `false` silently from `re_test`/`re_find`. Callers can now
  distinguish "no match" from "bad pattern".
- **Catastrophic backtracking.** PCRE is a backtracking engine but has
  a JIT and a backtrack limit; the discovery panel runs P1/P2 in a few
  ms here. Larger inputs or pathological shapes can hit
  `pcre.backtrack_limit` and return `false`. Stay inside the RE2 subset
  and prefer flat patterns.
- **Zero-width `replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"` — the ECMA convention shared by all PCRE/ECMA/.NET/Java/Onigmo engines plus the in-tree Thompson ports. Go (RE2) returns `"XbXcX"` instead; see `/design/REGEX_PATHOLOGICAL.md`.

See `/design/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Build and test

```bash
cd php
composer install
make test
```

Tests live in [`tests/`](./tests/) and consume fixtures from
[`../build/test/`](../build/test/).
