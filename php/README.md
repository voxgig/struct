# Struct for PHP

> Full-parity PHP port of the canonical TypeScript implementation.
> All functionality is exposed as static methods on `Voxgig\Struct\Struct`.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md) and
[REPORT.md](../REPORT.md).


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

```php
Struct::isnode(['a' => 1]);          // true
Struct::ismap([1, 2]);                // false
Struct::islist([1, 2]);               // true
Struct::iskey('name');                // true
Struct::iskey('');                    // false
Struct::isempty(null);                // true
Struct::isfunc(fn() => 1);            // true
```

### Type inspection

```php
Struct::typify($value): int          // bit-field
Struct::typename($t): string         // human name
```

```php
Struct::typify(42);                   // T_scalar | T_number | T_integer
Struct::typify('hi');                 // T_scalar | T_string
Struct::typename(Struct::typify('hi'));  // 'string'
```

### Size, slice, pad

```php
Struct::size($val): int
Struct::slice($val, $start = null, $end = null, $mutate = false)
Struct::pad($str, $padding = null, $padchar = null): string
```

```php
Struct::size([1, 2, 3]);               // 3
Struct::slice([1, 2, 3, 4, 5], 1, 4);  // [2, 3, 4]
Struct::pad('hi', 5);                  // 'hi   '
Struct::pad('hi', -5, '*');            // '***hi'
```

### Property access

```php
Struct::getprop($val, $key, $alt = null)
Struct::setprop(&$parent, $key, $val)        // by reference!
Struct::delprop(&$parent, $key)              // by reference!
Struct::getelem($val, $key, $alt = null)
Struct::getdef($val, $alt)
Struct::haskey($val, $key): bool
Struct::keysof($val): array
Struct::items($val): array
Struct::strkey($key): string
```

```php
Struct::getprop(['a' => 1], 'a');                  // 1
Struct::getprop([], 'b', 'fallback');              // 'fallback'

$node = ['a' => 1];
Struct::setprop($node, 'b', 2);
// $node === ['a' => 1, 'b' => 2]

Struct::getelem([1, 2, 3], -1);                    // 3
Struct::keysof(['b' => 1, 'a' => 2]);              // ['a', 'b']
Struct::items(['a' => 1, 'b' => 2]);
// [['a', 1], ['b', 2]]
```

### Path operations

```php
Struct::getpath($store, $path, $injdef = null)
Struct::setpath(&$store, $path, $val, $injdef = null)
Struct::pathify($val, $startin = null, $endin = null): string
```

```php
Struct::getpath(['a' => ['b' => ['c' => 42]]], 'a.b.c');  // 42
Struct::getpath(['a' => [10, 20]], 'a.1');                // 20

$store = [];
Struct::setpath($store, 'db.host', 'localhost');
// $store === ['db' => ['host' => 'localhost']]

Struct::pathify(['a', 'b', 'c']);                          // 'a.b.c'
```

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

Struct::merge([
    ['a' => 1, 'b' => 2],
    ['b' => 3, 'c' => 4],
]);
// ['a' => 1, 'b' => 3, 'c' => 4]

Struct::clone(['a' => [1, 2]]);
Struct::flatten([1, [2, [3, [4]]]]);
Struct::filter(['a' => 1, 'b' => 2, 'c' => 3],
    fn($kv) => $kv[1] > 1);
// [['b', 2], ['c', 3]]
```

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

```php
Struct::escre('a.b+c');                   // 'a\\.b\\+c'
Struct::escurl('hello world');            // 'hello%20world'
Struct::join(['a', 'b', 'c'], '/');       // 'a/b/c'
Struct::joinurl(['http:', '/foo/']);      // 'http:/foo'
Struct::jsonify(['a' => 1]);              // '{"a":1}'
Struct::stringify(['a' => 1]);            // 'a:1'
```

### Inject / transform / validate / select

```php
Struct::inject($val, $store, $injdef = null)
Struct::transform($data, $spec, $injdef = null)
Struct::validate($data, $spec, $injdef = null)
Struct::select($children, $query): array
```

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

Struct::validate(['name' => 'Ada'], ['name' => '`$STRING`']);
// throws \RuntimeException on mismatch (or accumulates if you pass
// an errors array as the fourth arg)

Struct::select(
    ['a' => ['age' => 30], 'b' => ['age' => 25]],
    ['age' => 30]
);
// [['age' => 30, '$KEY' => 'a']]
```

### Builders

```php
Struct::jm(...$kv): array
Struct::jt(...$v): array
```

```php
Struct::jm('a', 1, 'b', 2);   // ['a' => 1, 'b' => 2]
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

1. `setprop`, `setpath`, `delprop`, and similar mutating calls take
   their parent **by reference** (`&$parent`).
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
- throws a `\RuntimeException` carrying the first error by default;
- accumulates into a passed errors array when you supply one.

### Test status

82/82 tests pass, 920 assertions.


## Build and test

```bash
cd php
composer install
make test
```

Tests live in [`tests/`](./tests/) and consume fixtures from
[`../build/test/`](../build/test/).
