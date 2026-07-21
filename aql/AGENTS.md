# AGENTS.md — AQL port of `voxgig/struct`

Read the repo-root [`../AGENTS.md`](../AGENTS.md) first. This file covers
only what is specific to the AQL port. **TypeScript is canonical; the
shared `build/test/*.jsonic` corpus is the contract.** This port follows
the single-`null` model of the Python / Dart / Lua ports (AQL's `none`
plays both `undefined` and JSON `null`), not the distinct-value model of
the OCaml / Scala ports.

The port is written in the AQL *language* (not Go), and deliberately does
NOT use the engine's native `aql:struct-util` module — the whole point is
a from-scratch implementation of the canonical algorithms in AQL itself.

## How to build / test / lint

```
cd aql
make test    # aql run -no-check -no-compile test/runner.aql
make lint    # aql check src/struct.aql + a module load smoke
```

Requires only the `aql` CLI (`make test AQL=/path/to/aql` to point at a
specific binary). **Zero third-party runtime dependencies** — the library
imports only bundled `aql:` modules (`string-util`, `math-util`,
`bin-util`, `minilang` for regex, `emitlang` for JSON output,
`time-util`); the test runner additionally uses `aql:io` to read the
corpus.

## The value model

- Nodes are **flex** collections: `flex {}` / `flex []` are mutable and
  reference-stable (aliases share; writes are visible through every
  alias). Plain map/list literals are immutable — `vg-clone` and every
  node-creating helper builds flex nodes so in-place algorithms
  (`merge`, `inject`, `setpath`, `validate_CHILD`, …) behave exactly as
  in the canonical TypeScript.
- `none` is both `undefined` and JSON `null`. Group A readers
  (`getprop`, `getelem`, `haskey`, …) unify absent and stored-null;
  Group B writers preserve literal slots
  ([`../design/UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)). The corpus
  runner maps JSON `null` to the `"__NULL__"` marker exactly like the
  reference runner, and — exactly like the Python port's `_injectstr` —
  the partial string-injection path renders a found `"__NULL__"` as
  `"null"` (the single-null way of matching canonical
  `JSON.stringify(null)` for injected nulls). Validation's `$NIL`/`$NULL`
  recover the absent-vs-stored-null distinction via literal slot
  presence (`vgi-haslit`).
- Map literals and parsed JSON keep **sorted key order** in AQL; `set`
  appends new keys in insertion order. The corpus has been audited to be
  key-order-insensitive under the runner's `deq` comparison.

## Function-value carriers (IMPORTANT)

A bare Function-valued name **auto-dispatches when stepped** in AQL, so
function values never travel bare:

- **fn box** — `` {"`$FN`": f/r} ``: the general "function as data" carrier.
  Store commands (`$COPY`, `$EACH`, …), `handler`, `modify` and
  formatter-table entries are boxes; `vg-isfunc` recognises the shape
  (mirroring canonical `isfunc`).
- **one-element list** — `[f/r]`: pure callback slots that canonical
  code never `isfunc`-tests (walk before/after, `filter` predicates).

Unwrap with `vgi-fnarg`; call through `vgi-call1/2/4/5` (`apply` binds
the stack TOP to the FIRST parameter, so arguments are pushed in
reverse; zero-argument `apply` refuses to run, so nullary callables take
one ignored argument). Cross-module callbacks execute in the **callee's**
registry: a callback body may use core words, the library's `vg-*`
words, values captured from its defining frame, and the bundled utility
modules — but NOT the `Struct.*` namespace or runner-private words.

## Engine caveats (read before touching control flow)

Idioms in this codebase that look redundant are load-bearing:

1. **bind-then-return** — every fn body ends `def r (...)` then `r`,
   never a bare tail call. A body that ends in a bare call **loses a
   `none` result** at the return boundary in deep `apply` chains; a
   paired `(call) drop` then eats a foreign stack cell and corrupts an
   ancestor frame (the failure appears far away as
   `undefined word: <local>`).
2. **Module-level loops** — all recursion lives in module-level `vgl-*`
   functions with explicit parameters. Local named `def f fn …` loops
   corrupt recursion (the engine's InstallDef overlap-removal drops the
   outer binding of a same-name/signature nested fn def).
3. **No `and`/`or` short-circuit** — both sides always evaluate. Never
   guard a typed call with a type test in the same condition
   (`(n is Float) and ((MathUtil.floor n) eq n)` crashes for integers);
   nest `if`s instead.
4. **Computed `set` keys need parens** — `m set (k) v`; a bare word in
   key position is taken as a literal name.
5. **Reserved names** — `args`, `depth`, `sub`, `inner`, `node`, `ref`,
   `base` cannot be parameter/local names; `keys`, `pick`, `filter`,
   `join`, `slice`, `size`, `walk`, `select`, `flatten`, `pad` are core
   words that module fns must not redefine.
6. **Interpreter-pinned tests, checker-clean source** — `make test` runs
   `-no-check -no-compile` for deterministic corpus runs, but the module
   now also passes `aql check` with 0 errors (`make lint` runs it) and the
   full corpus passes under the default compiled mode too. Getting there
   took a series of aql-engine fixes (checker nil-derefs on store-shaped
   flex carriers, guard-fact/narrowing precision, forward-reference
   placeholder handling, multi-result poly for `pop`, dynamic-pattern
   `mini re` compilation) — an older `aql` binary will crash or report
   phantom errors on this module; build from an aql checkout that includes
   them.

## Canonical-name mapping

Public functions are `vg-<canonicalname>` (e.g. `vg-getpath`); internal
helpers are `vgi-*`; loop workers are `vgl-*`. The export map at the end
of `src/struct.aql` binds every canonical name (the parity checker reads
those keys). `jm`/`jt` take one list argument (AQL has no variadics);
optional canonical parameters are explicit `NOARG` arguments.

## Making a change

1. Change canonical TypeScript first (repo rule), regenerate the corpus
   if applicable, then mirror here.
2. Follow the engine-caveat idioms above — especially bind-then-return.
3. `make test` must end `PASS <n>  FAIL 0`, and
   `python3 ../tools/check_parity.py` must stay green.

## CI wiring (proposed — needs `workflow` scope to land)

CI has a `test-<lang>` job per port in `.github/workflows/build.yml`;
the aql job could not be pushed from this session (the token lacks the
`workflow` scope). Add it as:

```yaml
  test-aql:
    runs-on: ubuntu-latest
    env:
      # The port needs an aql build that includes the `del` word. Until
      # the matching aql-lang/aql change merges, pin AQL_GIT_REF to its
      # branch; then switch back to main.
      AQL_GIT_REF: main
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'
      - name: Build the aql CLI from source
        run: |
          git clone --depth 1 --branch "$AQL_GIT_REF" https://github.com/aql-lang/aql /tmp/aql-lang
          (cd /tmp/aql-lang/cmd/go && go build -o "$RUNNER_TEMP/aql" .)
      - name: Run tests
        working-directory: ./aql
        shell: bash
        run: make test AQL="$RUNNER_TEMP/aql"
```
