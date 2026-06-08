# Struct for Perl — Comprehensive Guide

> A **port** of the canonical TypeScript implementation. Behaviour is
> defined by TypeScript and pinned by the shared corpus; this port mirrors
> it case for case. This guide is the in-depth companion to
> [`README.md`](./README.md) (quick-start + signature reference) and the
> language-neutral [`../DOCS.md`](../DOCS.md).

Four parts, each with a different job:

- **[Tutorial](#1-tutorial)** — install and learn the whole API hands-on.
- **[How-to guides](#2-how-to-guides)** — recipes for specific tasks.
- **[Reference](#3-reference)** — signatures live in
  [`README.md`](./README.md#function-reference); this section adds the
  Perl-specific semantics.
- **[Explanation](#4-explanation--port-specifics)** — the model, the
  port's role, and Perl-specific behaviour.

Then: [Build, test, extend](#build-test-and-extend).

---

## 1. Tutorial

### Install

There is **no install step and no build step** — `Voxgig::Struct` is a
pure-Perl module with zero third-party runtime dependencies (only core
`Scalar::Util`, `List::Util`, and `B`). Point `@INC` at `lib/` and use it:

```bash
cd perl
make test            # prove -Ilib t/
```

Tested with Perl 5.38 (the module requires `use 5.018`). Entry point:
[`lib/Voxgig/Struct.pm`](./lib/Voxgig/Struct.pm).

### Your first program

The port exposes a **functional interface**: there is no `Exporter` list,
so every function is called fully qualified under `Voxgig::Struct::`. Names
keep the canonical lowercase spelling (`getpath`, `merge`, …) so the
function table is identical across every port.

```perl
use Voxgig::Struct;

# parse_json builds insertion-ordered maps (see the quirk below).
my $config = Voxgig::Struct::merge([
  Voxgig::Struct::parse_json('{"db":{"host":"localhost","port":5432}}'),
  Voxgig::Struct::parse_json('{"db":{"host":"db.internal"}}'),
]);

Voxgig::Struct::getpath($config, 'db.host');   # 'db.internal'
Voxgig::Struct::getpath($config, 'db.port');   # 5432  (survived the deep merge)
```

### Build up the rest of the API

Each call below has the same meaning in every port; only the syntax
changes. Read [`../DOCS.md`](../DOCS.md#1-tutorial-a-guided-tour) for the
full language-neutral walkthrough; the Perl-flavoured version (aliasing the
package to keep it readable):

```perl
*S:: = \*Voxgig::Struct::;   # local alias; or just type Voxgig::Struct::

# Reshape by example — the spec mirrors the output you want.
S::transform(
  S::jm(user => S::jm(first => 'Ada', last => 'Lovelace'), age => 36),
  S::jm(name => '`user.first`', surname => '`user.last`', years => '`age`'),
);
# { name => 'Ada', surname => 'Lovelace', years => 36 }

# Validate by example — leaves are type checkers; dies on mismatch.
S::validate(S::jm(name => 'Ada', age => 36),
            S::jm(name => '`$STRING`', age => '`$INTEGER`'));

# Walk the tree — replace values on ascent.
S::walk($tree, undef, sub {
  my ($key, $val) = @_;
  return S::is_jnull($val) ? 'DEFAULT' : $val;
});

# Select children by query — each match tagged with its $KEY.
S::select(S::jm(a => S::jm(age => 30), b => S::jm(age => 25)), S::jm(age => 30));
# [ { age => 30, '$KEY' => 'a' } ]
```

Use `jm` (insertion-ordered map literal) and `jt` (list literal) to build
inputs: a bare Perl `{ ... }` is an *unordered* hash, so reach for `jm`
whenever map key order matters (it almost always does — see below).

---

## 2. How-to guides

### Collect all validation errors instead of dying
```perl
my $errs = [];
Voxgig::Struct::validate($payload, $spec, { errs => $errs });
warn "@$errs" if @$errs;
```
Pass an `errs` arrayref in the options hashref; `validate`/`transform`
collect into it instead of calling `die`.

### Write a custom transform function (`$APPLY`)
```perl
Voxgig::Struct::transform(
  Voxgig::Struct::jm(items => Voxgig::Struct::jt(1, 2, 3)),
  Voxgig::Struct::jm(total => Voxgig::Struct::jm('`$APPLY`' => 'sum')),
  { extra => Voxgig::Struct::jm(sum => sub {
      my ($resolved, $store, $cinj) = @_;
      my $items = Voxgig::Struct::getpath($store, '$TOP.items');
      my $t = 0; $t += $_ for @$items; return $t;
  }) },
);
```
Register the coderef under `extra`; reference it by name in the spec. A
custom function may return the `SKIP` / `DELETE` sentinels (or `NONE`) to
omit/remove the current key.

### Keep a `walk` path past the callback
```perl
my @seen;
Voxgig::Struct::walk($tree, sub {
  my ($key, $val, $parent, $path) = @_;
  push @seen, [ @$path ];   # the path arrayref is reused — copy to retain it
  return $val;
});
```

### Distinguish a JSON null from an absent value
```perl
Voxgig::Struct::is_jnull($v)   # true only for the $JNULL singleton
Voxgig::Struct::is_none($v)    # true only for the NONE ("absent") sentinel
# bare Perl undef also means "absent" to Group A readers
```

### Serialise deterministically
```perl
Voxgig::Struct::jsonify($value);        # compact, insertion-ordered keys
Voxgig::Struct::jsonify($value, 2);     # pretty, 2-space indent
Voxgig::Struct::stringify($value, 80);  # truncated human form, for logs
```

For more task recipes (merge configs, rename fields, `$EACH`, `$MERGE`,
`$FORMAT`, `$ONE`, `$EXACT`, …) see the language-neutral
[How-to guides](../DOCS.md#2-how-to-guides) — the spec syntax is identical;
only the host literals differ.

---

## 3. Reference

The full signatures and per-function examples are in
[`README.md` → Function reference](./README.md#function-reference). The
canonical public surface is defined by the TypeScript `export { … }` block;
[`../tools/check_parity.py`](../tools/check_parity.py) checks this port
against it.

Perl-specific points the signatures don't show:

- **Functional interface, no exports.** Nothing is exported; call every
  function as `Voxgig::Struct::name(...)`. The names are canonical
  lowercase (`getpath`, `setprop`, `keysof`, …). The three injection
  helpers keep canonical camelCase: `checkPlacement`, `injectorArgs`,
  `injectChild`.
- **`getprop` vs `getelem`.** `getprop` works on maps and lists; `getelem`
  is list-specific, supports `-1`-from-the-end indexing, and *invokes* a
  callable `alt` (a coderef) when the element is absent.
- **`items` is overloaded** — `items($node)` returns `[[k, v], …]`;
  `items($node, $coderef)` maps each `[k, v]` pair through the coderef.
- **`join` shadows the builtin.** `Voxgig::Struct::join` is the library
  function; the source uses `CORE::join` internally for Perl's builtin.
- **Type flags** combine bitwise: `typify('hi')` is `T_scalar | T_string`;
  test with `0 < (T_string & $t)`. `typify(undef)` and `typify(NONE)` are
  `T_noval`; `typify($JNULL)` is `T_null`; `typify($JTRUE)` is `T_boolean`.
- **Booleans, null, absence are singletons.** JSON `true`/`false` are
  `$Voxgig::Struct::JTRUE` / `$JFALSE` (blessed, overload `bool`/`0+`/`""`);
  JSON `null` is `$JNULL`; "absent" is `$NONE` (predicate `is_none`).
- **Transform/validate/select commands are named subs**
  (`transform_COPY`, `validate_STRING`, `select_CMP`, …), wired into the
  injection store by `transform`/`validate`/`select`; you reference them by
  their `$NAME` in a spec, not by calling them directly.

---

## 4. Explanation & port specifics

### A faithful port

TypeScript is the source of truth. The shared corpus in
[`../build/test/`](../build/test/) is generated from the canonical code,
and this port is held to it. A behaviour question is answered by reading
the canonical TypeScript and the corpus, not by reading this port; a change
to canonical behaviour starts in TypeScript and flows out here (see
[`../AGENTS.md`](../AGENTS.md)).

### Insertion-ordered maps — the key quirk

Perl hashes **randomise key order**, but the canonical contract requires
JSON object key order to survive every operation (it is observable through
`keysof`, `items`, and `jsonify`). So the port ships an in-tree tie class,
`Voxgig::Struct::OrderedHash` (a `Tie::IxHash`-style implementation, kept
in-tree to preserve zero-deps), at the top of the module. It implements the
full `Tie::Hash` protocol plus a fast `Keys()` accessor used on the hot
path. Every map the library builds (`jm`, `parse_json`, clones, transform
output) is tied to it. Consequence: a bare `{ ... }` literal is unordered —
use `jm(...)` (or `parse_json`) whenever order matters. The bundled
`parse_json` exists precisely because `Cpanel::JSON::XS` / `JSON::PP`
return order-randomised plain hashes.

### `undef`, JSON `null`, and `NONE` (Group A/B)

Perl `undef` is overloaded in everyday code, so the port keeps three
distinct things — the [Group A/B rule](../DOCS.md#null-versus-absent-group-ab)
in Perl form (full text in [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md)):

- **`undef` / `$NONE` = absent.** Group A readers (`getprop`, `getelem`,
  `haskey`, `isempty`, `isnode`) treat absence — and a stored `$JNULL` —
  as "no value", returning the `alt` or false. `$NONE` (`is_none`) is the
  internal "absent" sentinel that propagates through injection.
- **`$JNULL` = the JSON null scalar.** `typify($JNULL)` is `T_null`, and
  Group B processors (`clone`, `merge`, `walk`, `setprop`, …) preserve it
  literally. It is a blessed singleton whose `""` overload is `'null'`.

Because Perl scalars don't distinguish `"0.0"` from `0.0`, `parse_json`
forces numbers to carry `SVf_IOK`/`SVf_NOK`; `_is_number_sv` /
`_is_string_sv` probe those flags so `getpath` keeps TypeScript's
`typeof path === 'number'` branch reachable.

### Regex

The uniform six-function API (`re_compile` / `re_test` / `re_find` /
`re_find_all` / `re_replace` / `re_escape`) wraps Perl's built-in
PCRE-family engine (backtracking). Stay inside the **RE2 subset** —
Perl *allows* backreferences, lookaround, and recursion, but those don't
port to the RE2/NFA ports (Go, Rust, C, …). Two sharp edges align with the
ECMA/backtracking family: catastrophic backtracking on pathological shapes,
and zero-width `re_replace("a*", "abc", "X")` returning `"XXbXcX"` (Go/RE2
returns `"XbXcX"`). Both are detailed in
[`README.md` → Regex](./README.md#regex) and
[`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md). Pass character
strings (`use utf8;` for literals).

---

## Build, test, and extend

```bash
cd perl
make test            # prove -Ilib t/        (the shared corpus suite)
make lint            # perlcritic --gentle lib t
make inspect         # print the Perl + module version
```

`perlcritic` is soft-skipped locally when it is not on `PATH`; CI hardens
this (it is required when `CI=true`). There is no build step (`make build`
just says so). Per REPORT.md, the runner exercises 121 corpus subtests
(700+ individual cases), loading the shared corpus from
[`../build/test/`](../build/test/) (`test.json`) via the in-tree
insertion-ordered `parse_json`. Tests live in [`t/`](./t/):
`t/struct.t` (corpus runner), `t/regex_pathological.t` (regex panel), and
`t/00-load.t` (load/sanity).

**To change behaviour:** this is a port, so behaviour changes start in the
canonical TypeScript, not here. Edit the canonical source, adjust the
corpus case in `../build/test/*.jsonic`, then mirror the logic in
[`lib/Voxgig/Struct.pm`](./lib/Voxgig/Struct.pm), run `make test` until
green, and re-run [`../tools/check_parity.py`](../tools/check_parity.py).
The full cross-port checklist is in [`../AGENTS.md`](../AGENTS.md).
