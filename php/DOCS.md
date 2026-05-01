# Struct for PHP

> Full-parity PHP port of the canonical TypeScript implementation.
> All functionality is exposed as static methods on `Voxgig\Struct\Struct`.

For the language-neutral overview, motivation, and concepts, see the
[top-level README](../README.md).

These docs follow the [Diataxis](https://diataxis.fr/) framework.


## Tutorial: your first transform

### Install

Composer:

```bash
composer require voxgig/struct
```

In the monorepo:

```bash
cd php
composer install
```

### A first transform

```php
<?php
require 'vendor/autoload.php';

use Voxgig\Struct\Struct;

$data = [
    'user' => ['first' => 'Ada', 'last' => 'Lovelace'],
    'age'  => 36,
];

$spec = [
    'name'    => '`user.first`',
    'surname' => '`user.last`',
    'years'   => '`age`',
];

print_r(Struct::transform($data, $spec));
// Array ( [name] => Ada [surname] => Lovelace [years] => 36 )
```

### Validate

```php
Struct::validate($out, [
    'name'    => '`$STRING`',
    'surname' => '`$STRING`',
    'years'   => '`$INTEGER`',
]);
```


## How-to recipes

### Read a deep value safely

```php
Struct::getpath('db.host', $config);
Struct::getprop($node, 'count', 0);
Struct::getdef($maybe, 'fallback');
```

### Set a deep value

```php
$store = [];
Struct::setpath($store, 'db.host', 'localhost');
// $store === ['db' => ['host' => 'localhost']]
```

Note: PHP arrays are value types, so `setprop` accepts the parent
**by reference** (`&$parent`).

### Merge configs

```php
$cfg = Struct::merge([$defaults, $file, $env]);
```

### Walk a tree

```php
Struct::walk($tree, function ($key, $val, $parent, $path) {
    return $val === null ? 'DEFAULT' : $val;
});
```

### Inject and select

```php
Struct::inject(['greeting' => 'hello `name`'], ['name' => 'Ada']);
Struct::select(['age' => 30], $records);
```


## Reference

Source: [`src/Struct.php`](./src/Struct.php).  Namespace
`Voxgig\Struct`.  All API is on the `Struct` class as public static
methods.

### Method list (46)

All 40 canonical functions plus PHP-specific helpers:

```
typename, getdef, isnode, ismap, islist, iskey, isempty, isfunc,
size, slice, pad, typify, getelem, getprop, strkey, keysof, haskey,
items, flatten, filter, escre, escurl, join, jsonify, stringify,
pathify, clone, delprop, setprop,
walk, merge, setpath, getpath, inject, transform, validate, select,
jm, jt,
checkPlacement, injectorArgs, injectChild,

// PHP additions
replace, joinurl, cloneWrap, cloneUnwrap
```

### Constants

`Struct` exposes the canonical constants as class constants:

```php
Struct::SKIP
Struct::DELETE
Struct::T_string
Struct::M_KEYPRE
// ... etc
```

### `ListRef`

A wrapper class that gives lists reference semantics across calls
that would otherwise copy them.  Used internally; you only need it
if you write custom `Modify` callbacks that mutate lists.

```php
use Voxgig\Struct\ListRef;
$ref = new ListRef([1, 2, 3]);
```

### Tests

```bash
cd php
composer install
make test           # 82/82 passing, 920 assertions
```


## Explanation

### `UNDEF` is a string sentinel

PHP has no separate "undefined" keyword.  The port uses the string
`'__UNDEFINED__'` (`Struct::UNDEF`) as a sentinel for absent values.
Most user-facing calls accept `null` as "absent" and return `null`
when nothing is present, so you usually do not see the sentinel
directly.

### Arrays are value types

PHP arrays copy on assignment, which breaks the canonical
"reference-stable list" assumption.  Two adaptations:

1. `setprop`, `setpath`, and similar mutating calls take their
   parent **by reference** (`&$parent`).
2. The `ListRef` class wraps a list when one needs to be shared
   across calls (notably during `merge` and `inject`).

This is the same pattern the Go port uses, for the same reason.

### Maps and lists in PHP

PHP has only one container type (the array) which can be associative
("map") or numerically indexed ("list").  `struct` distinguishes the
two with the same predicates as everywhere else: `Struct::ismap`,
`Struct::islist`.  An array with non-sequential numeric keys is
treated as a map.

### Method casing

PHP method names follow the canonical lowercase: `getpath`,
`setpath`, `getprop`.  This breaks PSR-12 camelCase, but parity with
other ports beats style.

### Validate

`Struct::validate` either:

- returns the value, on success;
- throws a `\RuntimeException` with the first error, by default;
- accumulates into a passed errors array, if you supply one as the
  fourth argument.


## Build and test

```bash
cd php
composer install
make test
```

Tests in [`tests/`](./tests/) consume fixtures from
[`../build/test/`](../build/test/).
