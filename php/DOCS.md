# Struct for PHP — Comprehensive Guide

> A faithful PHP port of the **canonical** TypeScript implementation. Behaviour
> is defined by TypeScript and pinned by the shared corpus; this port matches it
> case for case. This guide is the in-depth companion to
> [`README.md`](./README.md) (quick-start + method reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — method signatures live in
  [`README.md`](./README.md#function-reference); this section adds the exact
  PHP semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model and the
  PHP-specific behaviour (value-type arrays, `ListRef`, `UNDEF`, PCRE).

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

```bash
composer require voxgig/struct
```

Package `voxgig/struct`; namespace `Voxgig\Struct`; requires PHP 8.x. Every
function is a `public static` method on the `Voxgig\Struct\Struct` class — there
is no instance/utility wrapper class in this port. Working from a clone (you'll
do this to run the corpus or extend the port):

```bash
cd php
composer install
```

### Your first program

```php
<?php
require 'vendor/autoload.php';

use Voxgig\Struct\Struct;

$config = Struct::merge([
    ['db' => ['host' => 'localhost', 'port' => 5432], 'debug' => false], // defaults
    ['db' => ['host' => 'db.internal'], 'debug' => true],                // overrides
]);

Struct::getpath($config, 'db.host');   // 'db.internal'
Struct::getpath($config, 'db.port');   // 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax changes.
Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the full
language-neutral walkthrough; the PHP-flavoured version:

```php
use Voxgig\Struct\Struct;

// Reshape by example — the spec mirrors the output you want.
Struct::transform(
    ['user' => ['first' => 'Ada', 'last' => 'Lovelace'], 'age' => 36],
    ['name' => '`user.first`', 'surname' => '`user.last`', 'years' => '`age`'],
);
// ['name' => 'Ada', 'surname' => 'Lovelace', 'years' => 36]

// Validate by example — leaves are type checkers; throws on mismatch.
Struct::validate(['name' => 'Ada', 'age' => 36], ['name' => '`$STRING`', 'age' => '`$INTEGER`']);

// Walk the tree — replace values on ascent.
Struct::walk($tree, null, fn($key, $val, $parent, $path) => $val === null ? 'DEFAULT' : $val);

// Select children by query — each match tagged with its $KEY.
Struct::select(['a' => ['age' => 30], 'b' => ['age' => 25]], ['age' => 30]);
// [['age' => 30, '$KEY' => 'a']]
```

---

## 2. How-to guides

### Set a deep value (mutation is by return value, not by reference)
```php
$store = [];
$store = Struct::setpath($store, 'service.db.host', 'db.internal');
// ['service' => ['db' => ['host' => 'db.internal']]]
```
`setpath` and `delprop` take their store **by value** and return the updated
structure — assign the result. The single exception is `setprop`, which takes
its parent **by reference** (`&$parent`) and mutates in place.

### Collect all validation errors instead of throwing
```php
$injdef = new \stdClass();
$injdef->errs = [];
Struct::validate($payload, $spec, $injdef);
if (count($injdef->errs) > 0) {
    // report $injdef->errs
}
```
Supply an `errs` property on the `$injdef` object and `validate` accumulates
into it instead of throwing. Internally the array is shared via an
`ArrayObject` and unwrapped back to a plain array on return.

### Write a custom transform function (`$APPLY`)
```php
use Voxgig\Struct\ListRef;

// The function is the SECOND element of an `$APPLY` LIST; the third element
// is the child spec whose injected result is passed to it.
$sum = fn($resolved, $store, $cinj) =>
    array_sum($resolved instanceof ListRef ? $resolved->list : (array) $resolved);

Struct::transform(['items' => [1, 2, 3]], ['total' => ['`$APPLY`', $sum, '`items`']]);
// ['total' => 6]
```
`$APPLY` must appear in **list-value** position — `['`$APPLY`', $fn, $child]` —
not as a map key: `['total' => ['`$APPLY`' => 'sum']]` is rejected with
`$APPLY: invalid placement in parent map, expected: list` (see the
`transform/apply#badkey` example in `README.md`). The callback is invoked as
`$fn($resolved, $store, $cinj)`, where `$resolved` is the injected child value
(lists arrive wrapped in a `ListRef`). It may return the `Struct::SKIP` /
`Struct::DELETE` sentinels to omit/remove the current key.

### Keep a `walk` path past the callback
```php
$seen = [];
Struct::walk($tree, fn($key, $val, $parent, $path) => $val, null);
// inside the callback: $seen[] = array_values($path);
```
The `$path` array is backed by a per-depth slot in a shared pool that is reused
across siblings — clone it (`array_values($path)`) inside the callback if you
need to retain it past the visit.

### Serialise deterministically
`jsonify` pretty-prints by default (indent 2); pass `(object)['indent' => 0]` for compact.
`stringify` is the quote-light human form (keys sorted), for logs.

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

<!-- example: minor/stringify#brace -->
```php
Struct::stringify(['a' => 1, 'b' => [2, 3]]);   // '{a:1,b:[2,3]}'
```
<!-- => "{a:1,b:[2,3]}" -->

`jsonify` reads its options off a flags object (`indent`, `offset`).

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical; only
the host literals differ.

---

## 3. Reference

The full PHP method list, with examples for every function, is in
[`README.md` → Function reference](./README.md#function-reference). The public
surface is the set of `public static` methods on `Voxgig\Struct\Struct`; the
canonical name list and casing live in [`../DOCS.md`](../DOCS.md#3-reference) and
the parity tool [`../tools/check_parity.py`](../tools/check_parity.py) checks the
port against it (case/underscore-insensitively).

PHP-specific points the signatures don't show:

- **Casing is canonical lowercase** (`getpath`, `setpath`, `getprop`), which
  deliberately breaks PSR-12 camelCase — parity beats style. `phpcs` is
  configured to allow it.
- **Maps vs lists are both the array type.** `ismap` is an associative array (or
  `stdClass`); `islist` is a sequential 0-based array. An **empty** array reads
  as a list, and an array with non-sequential numeric keys reads as a map.
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem` is
  list-specific, supports `-1`-from-the-end indexing, and *invokes* a callable
  `$alt` when the element is absent (`getprop`/`getdef` do not).
- **`items` is overloaded** — `items($node)` returns `[key, val]` pairs;
  `items($node, $fn)` maps each pair through `$fn`.
- **`walk` extra parameters** (`$key`, `$parent`, `$path`) are recursion state;
  callers pass only `($val, $before, $after, $maxdepth)`.
- **Type flags** combine bitwise: `Struct::typify('hi')` is
  `T_scalar | T_string`; test with `0 < (Struct::T_string & $t)`.
  `typify(Struct::undef())` is `T_noval`; `typify(null)` is `T_scalar | T_null`.

---

## 4. Explanation & port specifics

### Faithful-port role

TypeScript is the source of truth; the shared corpus in
[`../build/test/`](../build/test/) is generated from it and this port is held to
that corpus. A behaviour question is answered by reading the canonical TS, not by
reading `Struct.php`. A canonical change starts in TypeScript, flows to the
corpus, then to this port (see [`../AGENTS.md`](../AGENTS.md)).

### Arrays are value types — `ListRef` and `&$parent`

This is the defining quirk of the PHP port. PHP arrays are value types
(copy-on-write): passing one into a function, or storing it in injection state,
gives the callee a *copy*, so a mutation is not visible to the original holder.
The canonical merge/walk/inject/setpath machinery relies on lists being shared
by reference. Two adaptations reproduce that, mirroring the Go port:

1. **`Voxgig\Struct\ListRef`** — a small object (reference type) wrapping a
   `public array $list`, implementing `ArrayAccess`, `Countable`, and
   `IteratorAggregate`. When a list must be shared across calls (during `merge`,
   `inject`, `transform`, `setpath`, `walk`), it is wrapped in a `ListRef` so
   mutations via `setprop`/`delprop`/`setval` propagate through every alias.
   `cloneWrap`/`cloneUnwrap` add and remove the wrappers; `jsonify`/`stringify`
   unwrap transparently. You only handle `ListRef` directly when writing custom
   `modify` callbacks that mutate lists.
2. **`setprop(mixed &$parent, …)`** takes its parent by reference and mutates in
   place. Note that `setpath` and `delprop` do **not** use `&` — they mutate
   through the `ListRef` wrapper where applicable and otherwise return the
   updated value, so assign the result.

### `null` versus absent, and the `UNDEF` sentinel

PHP has no separate "undefined" keyword, so the port uses a private sentinel
object returned by `Struct::undef()` to mean "absent" internally (the public
`Struct::UNDEF` string `'__UNDEFINED__'` is a legacy marker kept for
compatibility). User-facing APIs accept and return `null`, so you rarely see the
sentinel directly.

This port already follows **Group A** null semantics (see
[`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md) and [`../REPORT.md`](../design/REPORT.md)):

- **Group A readers** (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
  treat a stored `null` as *no value* — you get the `$alt` or `false`.
- **Group B value-processors** (`setprop`, `clone`, `walk`, `merge`, `inject`,
  `transform`, `validate`, `select`, …) preserve `null` literally. Internally
  `_getprop` reads the raw stored value (including null), distinct from the
  null-normalising public `getprop`.

### `validate` error reporting

`Struct::validate` returns the data on success. By default it throws a plain
`\Exception` whose message lists the accumulated errors (`'Invalid data: …'`).
Supply an `errs` collector on the `$injdef` object to accumulate instead of
throwing (see the how-to above). Separately, `re_compile` throws
`\InvalidArgumentException` on an invalid pattern.

### Regex

The uniform six-function API (`re_compile` / `re_test` / `re_find` /
`re_find_all` / `re_replace` / `re_escape`) wraps PHP's PCRE (`preg_*`). PCRE is
a backtracking engine and a strict superset of the **RE2 subset** all ports
target — it *allows* backreferences and lookaround, but those don't port, so
stay in-subset. `re_compile` validates eagerly and throws on a bad pattern
(callers can distinguish "no match" from "bad pattern"). Two sharp edges align
with the ECMA/backtracking engine family:

- **Catastrophic backtracking** — pathological patterns can hit
  `pcre.backtrack_limit` and return `false` on large inputs. Prefer flat
  patterns.
- **Zero-width `re_replace`** — `re_replace('a*', 'abc', 'X')` returns
  `'XXbXcX'`, the ECMA convention (Go's RE2 returns `'XbXcX'`).

Both are detailed in [`README.md` → Regex](./README.md#regex) and the
cross-port panel [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).

---

## Build, test, and extend

```bash
cd php
composer install
make test        # vendor/bin/phpunit
make lint        # vendor/bin/phpcs (PSR-12) + vendor/bin/phpstan analyse
make audit       # composer audit (supply-chain)
make inspect     # print PHP + project version
make bench       # WALK_BENCH=1 walk micro-benchmark
```

Dev tooling: PHPUnit ^12, PHPStan ^2.1, PHP_CodeSniffer ^3.13 (config in
[`phpcs.xml.dist`](./phpcs.xml.dist) / [`phpstan.neon.dist`](./phpstan.neon.dist)).
There is no build step. Tests live in [`tests/`](./tests/) (PHPUnit suite
configured in [`phpunit.xml`](./phpunit.xml)); the runner loads the shared
corpus from [`../build/test/`](../build/test/). The port passes the shared corpus
suite (85/85, 1022 assertions — see [`../REPORT.md`](../design/REPORT.md)).

**To change behaviour:** do it in canonical TypeScript first, adjust the corpus,
then port the change here, run `make test` and `make lint`, and re-run
[`../tools/check_parity.py`](../tools/check_parity.py). The full checklist is in
[`../AGENTS.md`](../AGENTS.md).
