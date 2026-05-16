# Struct for Perl

> Perl port of the canonical TypeScript implementation.
> Status: complete — full canonical parity, 700+ corpus cases passing.

For motivation, language-neutral concepts, and the cross-language
parity matrix, see the [top-level README](../README.md).


## Install

Inside the monorepo:

```bash
cd pl
make test
```

Tested with Perl 5.38. Module: [`lib/Voxgig/Struct.pm`](./lib/Voxgig/Struct.pm).

Zero runtime third-party dependencies — only core `Scalar::Util`,
`List::Util` and `B`. The insertion-ordered hash type lives in-tree
as the `Voxgig::Struct::OrderedHash` tie class at the top of the
module.


## Quick start

```perl
use Voxgig::Struct;

my $store = Voxgig::Struct::parse_json('{"db":{"host":"localhost"}}');
my $val   = Voxgig::Struct::getpath($store, 'db.host');
# $val eq "localhost"
```


## Function reference

Source: [`lib/Voxgig/Struct.pm`](./lib/Voxgig/Struct.pm).

Functions live in the `Voxgig::Struct::` namespace. The port keeps the
canonical TS names (`isnode`, `getpath`, `keysof`, …) rather than
`snake_case`ing them — this means the function-name table is the same
across every Voxgig port.

### Core types

The Perl port uses plain Perl scalars / array refs / hash refs to model
JSON values, with two refinements:

| JSON type | Perl form                                  |
|-----------|--------------------------------------------|
| object    | `HASH` ref, tied to `Voxgig::Struct::OrderedHash` so map key insertion order is preserved (matches the canonical TS contract). |
| array     | `ARRAY` ref.                               |
| string    | plain scalar with `SVf_POK` only.          |
| number    | plain scalar with `SVf_IOK` or `SVf_NOK` set. The in-tree JSON parser sets this so `getpath` can distinguish `"0.0"` (string path) from `0.0` (numeric path), matching TS's `typeof path` branch. |
| true / false | `$Voxgig::Struct::JTRUE` / `$Voxgig::Struct::JFALSE` — blessed scalar singletons that overload booleans, `0+`, and `""` so they behave correctly in arithmetic, comparison, and stringification. |
| null      | `$Voxgig::Struct::JNULL` — distinct from Perl `undef` (which represents "absent"). |

### Sentinels

`SKIP` and `DELETE` are insertion-ordered hashes blessed
`Voxgig::Struct::Sentinel`; `setprop` recognises them and either
preserves or removes the slot.

### JSON parser

`Voxgig::Struct::parse_json($text)` returns a structure that uses the
type rules above (in particular, `Voxgig::Struct::OrderedHash`-tied maps and
flag-marked numbers). `Cpanel::JSON::XS` / `JSON::PP` are not used
because they don't preserve insertion order.

### What's wired

- All 25 **minor utilities**: `isnode`, `ismap`, `islist`, `iskey`,
  `isempty`, `isfunc`, `size`, `slice`, `pad`, `typify`, `getelem`,
  `getprop`, `strkey`, `keysof`, `haskey`, `items`, `flatten`,
  `filter`, `escre`, `escurl`, `join`, `jsonify`, `stringify`,
  `pathify`, `clone`, `delprop`, `setprop`, `typename`, `getdef`.
- Major utilities: `walk`, `merge`, `setpath`, `getpath`.
- `inject` (three-phase key processing) with `_injectstr` (full
  and partial backtick refs) and `_injecthandler` (default command
  dispatcher).
- `transform` and the 11 transform commands: `$DELETE`, `$COPY`,
  `$KEY`, `$META`, `$ANNO`, `$MERGE`, `$EACH`, `$PACK`, `$REF`,
  `$FORMAT`, `$APPLY` (plus the `FORMATTER` table for $FORMAT:
  `identity`, `upper`, `lower`, `string`, `number`, `integer`,
  `concat`).
- `validate` and the 15 validate checkers: `$STRING`, `$NUMBER`,
  `$INTEGER`, `$DECIMAL`, `$BOOLEAN`, `$NULL`, `$NIL`, `$MAP`,
  `$LIST`, `$FUNCTION`, `$INSTANCE`, `$ANY`, `$CHILD`, `$ONE`,
  `$EXACT`.
- `select` and the 4 select operators: `$AND`, `$OR`, `$NOT`,
  `$CMP` (with `$GT`, `$LT`, `$GTE`, `$LTE`, `$LIKE`).
- Type constants (`T_any`, `T_noval`, `T_boolean`, …, `T_node`),
  mode constants (`M_KEYPRE` / `M_KEYPOST` / `M_VAL`), modename
  table, sentinels (`SKIP`, `DELETE`), boolean singletons
  (`JTRUE`, `JFALSE`), null singleton (`JNULL`), absence sentinel
  (`NONE`).
- Injection helpers: `Injection` state (built as a hashref with
  `_inj_child` / `_inj_descend` / `_inj_setval`), `checkPlacement`,
  `injectorArgs`, `injectChild`.
- Builder helpers: `jm` (insertion-ordered map literal), `jt`
  (list literal).

## Regex

Uniform six-function regex API (see `/REGEX_API.md`). The Perl port
wraps Perl's built-in regex engine.

### API

| Function | Maps to |
|---|---|
| `re_compile(pattern, flags?)`         | `qr/$pattern/` |
| `re_test(pattern, input)`             | `$input =~ $re` |
| `re_find(pattern, input)`             | first match as `[whole, $1, ...]` or `undef` |
| `re_find_all(pattern, input)`         | all matches, one arrayref per match |
| `re_replace(pattern, input, repl)`    | `s/$re/$repl/g` (callable or template) |
| `re_escape(s)`                        | `quotemeta` equivalent |

### Dialect

Patterns must stay inside the **RE2 subset** documented in `/REGEX.md`.
Perl's regex supports backreferences, lookaround, recursion — none of
which are portable to the Go / Rust / C / Lua / Zig ports.

### Sharp edges

- **Catastrophic backtracking.** Perl's regex engine is backtracking
  but ships with optimisations (trie engine for alternation, etc.).
  The discovery panel runs P1/P2 in microseconds here, but other
  pathological shapes can still blow up. Stay flat.
- **Zero-width `replace`.** `re_replace("a*", "abc", "X")` returns
  `"XXbXcX"`, the canonical ECMA convention.
- **UTF-8 handling.** Pass character strings (use `use utf8;` for
  literals, or `decode_utf8` for bytes). Encoding round-trip bugs in
  caller code can manifest as `cafÃ©` style mojibake at print time —
  the regex itself preserves character semantics.

See `/REGEX_PATHOLOGICAL.md` for the cross-port pathological-input panel.


## Tests

```bash
make test
```

The runner loads `../build/test/test.json` (the cross-port corpus)
and exercises each set the wired functions are responsible for.
