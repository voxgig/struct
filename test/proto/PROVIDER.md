# Test Provider — prototype

A small **data-provider** library, ported to each language, that reads the
shared corpus (`build/test/test.json`) and hands a language's test code clean,
normalized test cases. It is **not** a test runner: it never calls the function
under test and never asserts. It answers one question — *"what are the cases,
and for each, what goes in and what is expected out?"* — and offers a few pure
helpers for comparing an expectation to a result.

> Status: prototype. Implemented for `ts`, `python`, `go`, `rust` (this first
> pass). Canonical behaviour is the TypeScript version (`ts/provider.ts`); the
> others are ports of it, same as the rest of this repo.

See [`AGENTS.md`](./AGENTS.md) for how a coding agent should *use* this to write
real tests.


## 1. The corpus shape it reads

```
test.json
└── struct
    └── <function>            e.g. getpath, merge, validate, minor.isnode…
        ├── name              the function name (string)        — skip
        ├── set               vestigial empty list at fn level  — skip
        └── <group>           e.g. basic, edge, operators…
            └── set[]         the test ENTRIES (the leaf units)
└── primary
    └── check                 client-integration spec (DEF + groups)
```

A **group** is any child of a function whose value is a map containing a `set`
list. `name` (a string) and the function-level empty `set` are not groups.


## 2. The normalized `Entry`

Every raw entry map is normalized to a stable record with provenance, one
**tagged input**, and one **tagged expectation**:

```
Entry {
  function : string          # "getpath"
  group    : string          # "basic"
  index    : int             # position within the group's set[]
  id       : string | null   # explicit "<fn>/<group>#<label>" if present
  doc      : bool            # marked as a documentation example?
  client   : string | null   # named client from the group's DEF.client

  input    : Input           # tagged — see §3
  expect   : Expect          # tagged — see §4

  raw      : map             # the original entry, untouched (escape hatch)
}
```

## 3. `Input` — tagged, mirrors the runner's precedence (`ctx` → `args` → `in`)

```
Input {
  kind : IN | ARGS | CTX
  in   : <value>     # kind==IN   — the single argument (absent ⇒ native null)
  args : <list>      # kind==ARGS — explicit positional argument vector
  ctx  : <map>       # kind==CTX  — context-map invocation
}
```

Resolution (exactly the order `resolveArgs` uses):
1. raw has `ctx` → `CTX`
2. else raw has `args` → `ARGS`
3. else → `IN`, with `in = raw.in` (key absent ⇒ native null/None/nil)

The provider does **not** decide how `in`/`args`/`ctx` map onto the function's
parameters — that is function-specific knowledge the test author supplies
(`AGENTS.md` §3 lists the shapes).

## 4. `Expect` — tagged value | error | match | absent

```
Expect {
  kind  : VALUE | ERROR | MATCH | ABSENT
  value : <any>          # kind==VALUE — expected result (may be literal null)
  error : ErrorCheck     # kind==ERROR
  match : <map>          # kind==MATCH (also populated if a match block co-exists)
}

ErrorCheck { any: bool, text: string|null, regex: bool }
```

Resolution (mirrors `checkResult`/`handleError` precedence):
1. raw has `err` → `ERROR`; `error = parseErr(raw.err)`
   - `err === true` → `{any:true}`
   - `"/…/"` → `{any:false, text:<inner>, regex:true}`
   - other string → `{any:false, text:<string>, regex:false}`
2. else raw has `out` (key present, even if null) → `VALUE`, `value = raw.out`
3. else raw has `match` → `MATCH`
4. else → `ABSENT`

`ABSENT` and `VALUE(null)` both assert a nullish result — the runner defaults an
absent `out` to "expect null/undefined". They are kept distinct for fidelity.
If a `match` block is present alongside an `err`/`out`, `expect.match` is also
set so the test can apply both.


## 5. Pure comparison helpers

Side-effect-free; the test calls them to assert. They reproduce the runner's
comparison logic so each port doesn't re-derive it (and re-introduce its bugs).

```
matchval(check, base)          -> bool   # scalar primitive (see below)
equal(expected, actual)        -> bool   # deep equality, null/undef collapsed (runner default null:true)
equalStrict(expected, actual)  -> bool   # deep equality, undefined ≠ null (runner null:false functions)
structMatch(check, base)       -> Result # partial structural match; {ok, path?, expected?, actual?}
errorMatches(check, message)   -> bool   # ErrorCheck vs a thrown message
```

`equal` vs `equalStrict` mirrors the runner's per-call `null` flag: most
functions run with `null:true` (absent ≡ null ≡ `__NULL__`, use `equal`); a set
of functions run with `null:false` (absent is distinct from null, use
`equalStrict`). The flag is **not** in the corpus — it is the test author's
choice; `AGENTS.md` §4 lists the `null:false` functions.

* **`matchval(check, base)`** — `check === base`; else if `check` is a string:
  `"/re/"` ⇒ `RegExp(re).test(stringify(base))`, otherwise
  `stringify(base).toLowerCase()` *contains* `check.toLowerCase()`; else if
  `check` is a function ⇒ `true`.
* **`equal`** — recursive deep-equal after normalizing `__NULL__`→null and
  absent→null on both sides (mirrors the runner's `flags.null` round-trip).
* **`structMatch`** — walk the `check` tree; at each leaf compare
  `getpath(base, path)`: equal ⇒ ok; `__UNDEF__` ⇒ require absent; `__EXISTS__`
  ⇒ require present; else fall back to `matchval`. First failure returns its
  path + the two values.
* **`errorMatches`** — `any` ⇒ true; `regex` ⇒ `RegExp(text).test(message)`;
  else case-insensitive substring.

`stringify(x)` = `x` if it is already a string, else compact JSON. (The
canonical runner uses struct's own `stringify`; for the provider this
approximation is sufficient and documented.)


## 6. API surface (per port, idiomatic naming)

```
TestProvider.load(testfile)    -> provider     # parse test.json
provider.functions()           -> [string]     # ["minor","getpath",…]
provider.groups(fn)            -> [string]      # ["basic","relative",…]
provider.entries(fn)           -> [Entry]       # all entries across fn's groups
provider.entries(fn, group)    -> [Entry]       # one group's entries
provider.raw()                 -> map           # the parsed test.json (escape hatch)
```

Default `testfile` resolves to `build/test/test.json` relative to the repo root;
tests may pass an explicit path.
