# boru port — comprehensive guide

This document covers the boru-specific details of `voxgig/struct`. For the
language-neutral concepts, tutorial and full reference, read the top-level
[`../DOCS.md`](../DOCS.md); for the user overview, [`README.md`](./README.md).
TypeScript is canonical and the shared `build/test` corpus is the contract.

## Installation

The whole library is one module file
([`src/struct.boru`](./src/struct.boru)) with no third-party dependencies —
it imports only modules bundled with the `boru` CLI. Import it and use the
`Struct` namespace:

```boru
import "./src/struct.boru" end
```

## Representation of data

| JSON-shape thing        | boru representation                          |
|-------------------------|---------------------------------------------|
| object / map            | `flex {}` (FlexMap — mutable node)           |
| array / list            | `flex []` (FlexList — mutable node)          |
| string                  | `String`                                     |
| integer                 | `Integer`                                    |
| decimal                 | `Float`                                      |
| boolean                 | `Boolean`                                    |
| JSON `null` / undefined | `none`                                       |
| function (commands)     | a Function in a carrier (see below)          |

Nodes are **mutable and reference-stable** on purpose: `merge`, `walk`,
`inject`, `transform` and `validate` mutate nodes in place and depend on
shared references. Plain (immutable) `{}` / `[]` literals are fine as
*inputs* — `clone` produces flex nodes, and every internal node-creating
path does too.

## Calling the API

Every canonical function is a key of the `Struct` export map. boru calls
are forward-form: `Struct.getpath store path injdef`.

### Optional arguments: `NOARG`

boru has no optional parameters. Every canonical optional argument is an
explicit trailing argument; pass `Struct.NOARG` for "not given":

```boru
Struct.getpath store "a.b" Struct.NOARG        ;# getpath(store, 'a.b')
Struct.stringify v Struct.NOARG Struct.NOARG   ;# stringify(v)
Struct.slice lst 1 Struct.NOARG Struct.NOARG   ;# slice(lst, 1)
```

`none` is NOT the same as `NOARG`: `none` is a real value (JSON null /
undefined), `NOARG` means the parameter was omitted (it matters for
e.g. `pathify`, whose fallback text differs).

### Function values: carriers

A bare Function-valued name auto-dispatches when stepped, so function
values ride in carriers:

- pure callbacks (walk apply, filter predicates): a one-element list
  `[myfn/v]`;
- `isfunc`-tested values (store commands, `handler`, `modify`,
  `$FORMAT` formatters): an fn box `` {"`$FN`": myfn/v} ``.

```boru
def upcase fn [[k:Any v:Any p:Any pth:Any] [Any] [
  if (v is String) [StringUtil.upper v] [v]
]]
Struct.walk data Struct.NOARG [upcase/v] Struct.NOARG
```

Command/callback signatures match the canonical ones: transform commands
and handlers take `(inj val ref store)`; the `modify` hook takes
`(val key parent inj store)`; walk callbacks take `(key val parent path)`.

### `jm` / `jt`

boru has no variadics; both take a single list:

```boru
Struct.jm ["a" 1 "b" 2]      ;# {a:1, b:2}
Struct.jt [1 "x" true]       ;# [1, "x", true]
```

## The single-null model

boru's `none` plays both `undefined` and JSON `null`, exactly like the
Python / Dart / Lua / Elixir ports. The Group A/B rules
([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) recover the
distinction: readers (`getprop`, `haskey`, `isempty`, …) unify a stored
null with an absent slot; writers and builders (`jm`, `jt`, `setprop`)
preserve stored slots literally — `setprop parent key none` stores a
null (which every Group A reader then treats as "no value"). Remove keys
with `delprop`, or with the `Struct.DELETE` marker inside
`setpath`/`transform` specs.

## Transform / validate / select

All by-example machinery works as canonical:

```boru
Struct.transform (flex {a: 1}) (flex {x: "`a`"}) Struct.NOARG
;# {x: 1}

Struct.validate (flex {a: "A"}) (flex {a: "`$STRING`"}) Struct.NOARG
;# {a: "A"} — or raises with the collected messages

def errs (flex [])
def idf (flex {})
(idf set "errs" errs) drop
(Struct.validate data shape idf) drop      ;# collect instead of raise
```

Errors raise boru errors whose `message` is the ` | `-joined canonical
message list, so `do [...] error [var [[e] (e get "message")]]` recovers
the canonical text.

`select` takes `(children query)` and returns the matching children,
each annotated with its `$KEY`:

```boru
Struct.select (flex [{x: 1} {x: 2}]) (flex {x: {"`$GT`": 1}})
;# [{x: 2, $KEY: 1}]
```

## Testing

`make test` runs the shared corpus (1300+ invocations) through
[`test/runner-lib.boru`](./test/runner-lib.boru), a faithful port of the
reference runner (`typescript/test/runner.ts`): the same `__NULL__`
fixups, error-substring matching, `match` walking and set drivers. The
run must end `PASS <n>  FAIL 0`.

`make lint` additionally runs the boru static checker over the library
(the module checks clean — 0 errors) and a load smoke.

For engine-level idioms (bind-then-return, module-level loops,
no-short-circuit `and`, carrier rules) read
[`AGENTS.md`](./AGENTS.md) before changing the source.
