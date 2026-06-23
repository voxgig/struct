# test/proto — agent guidance

You are writing **actual tests** for a `struct` port using the **test provider**
library in this directory. The provider gives you normalized cases from the
shared corpus (`build/test/test.json`); you supply the part it deliberately does
not: *how a case's input maps onto the function call, and how to assert.*

Read [`PROVIDER.md`](./PROVIDER.md) first for the data model. This file is the
how-to.

## 0. What the provider does and does not do

- **Does:** load `test.json`, enumerate functions/groups, and hand you a flat
  list of normalized `Entry` records — each with a tagged `input`, a tagged
  `expect`, and provenance (`function`/`group`/`index`/`id`). Plus pure
  comparison helpers (`equal`, `equalStrict`, `structMatch`, `errorMatches`,
  `matchval`).
- **Does NOT:** call the function under test, assert, or know the function's
  parameter order. That is your job — it is function-specific (§3).

## 1. The recipe

For each function you are testing:

1. `provider.entries("<fn>")` (optionally per group).
2. For each entry, **map `entry.input` onto the call** using §3.
3. Run the call (inside try/catch when an error may be expected).
4. **Assert against `entry.expect`** by its `kind`:

```
switch (entry.expect.kind) {
  VALUE  : assert equal(entry.expect.value, result)          // or equalStrict — §4
  ERROR  : the call must throw; assert errorMatches(entry.expect.error, message)
  MATCH  : assert structMatch(entry.expect.match, resultContext).ok
  ABSENT : assert the result is nullish (null/undefined/None/nil)
}
if (entry.expect.match != null && kind != MATCH) also assert structMatch(...)  // co-existing match
```

For `MATCH`, the runner matches against a *context object*
`{ in, args, out: result, ctx }`, not the bare result — build the same shape
before calling `structMatch` (see the `merge` cases, whose match paths start
`args.0…`).

## 2. Entry quick-reference

```
entry.function / .group / .index / .id / .doc / .client   # provenance
entry.input  = { kind: IN|ARGS|CTX, in?, args?, ctx? }
entry.expect = { kind: VALUE|ERROR|MATCH|ABSENT, value?, error?, match? }
entry.raw                                                   # original map, escape hatch
```

`entry.input.in` is usually a small map (`{path, store}`, `{data, spec}`, …) you
destructure. When `kind` is `ARGS`, spread `entry.input.args`. When `CTX`, the
function takes the context map (these are the `primary.check` client cases).

## 3. Per-function input → call mapping

Derived from the canonical TS runner. `vin = entry.input.in`. Names are the
canonical function names (case per your language).

| Function (group)        | Call to make |
|-------------------------|--------------|
| `getpath` basic         | `getpath(vin.store, vin.path)` |
| `getpath` relative/handler | `getpath(vin.store, vin.path, vin.current)` (handler) |
| `getpath` special       | `getpath(vin.store, vin.path, vin.inj)` |
| `merge` (most groups)   | `merge(vin)` — `vin` is the list of objects |
| `merge` depth           | `merge(vin.val, vin.depth)` |
| `transform` (most)      | `transform(vin.data, vin.spec)` |
| `transform` modify      | `transform(vin.data, vin.spec, <modifier>)` |
| `validate` (most)       | `validate(vin.data, vin.spec)` |
| `validate` special      | `validate(vin.data, vin.spec, vin.inj)` |
| `inject` deep           | `inject(vin.val, vin.store)` |
| `select` (all)          | `select(vin.obj, vin.query)` |
| `walk` basic/copy       | `walk(vin, <callback>)` |
| `minor.isnode/ismap/islist/iskey/isempty/isfunc/clone/keysof/items/escre/escurl/typename/typify/size` | pass `vin` (or the whole `in`) directly: `fn(in)` |
| `minor.filter`          | `filter(vin.val, <check from vin.check>)` |
| `minor.flatten`         | `flatten(vin.val, vin.depth)` |
| `minor.getprop`         | `getprop(vin.val, vin.key, vin.alt?)` |
| `minor.getelem`         | `getelem(vin.val, vin.key, vin.alt?)` |
| `minor.setprop`         | `setprop(vin.parent, vin.key, vin.val)` |
| `minor.delprop`         | `delprop(vin.parent, vin.key)` |
| `minor.haskey`          | `haskey(vin.val, vin.key)` |
| `minor.join`            | `join(vin.val, vin.sep?)` |
| `minor.slice`           | `slice(vin.val, vin.start, vin.end?)` |
| `minor.pad`             | `pad(vin.val, …)` |
| `minor.setpath`         | `setpath(vin.store, vin.path, vin.val)` |

When unsure, open the canonical `typescript/test/utility/StructUtility.test.ts`
— each `runset(spec.<fn>.<group>, …)` line shows the exact lambda. The corpus is
the contract; that file is the reference mapping.

## 4. The `null:false` functions — use `equalStrict`

Most functions treat absent ≡ null (use `equal`). These run with the runner's
`{ null: false }` flag, where an absent/undefined result is **distinct** from
JSON null — assert them with `equalStrict`:

```
iskey, strkey, isempty, clone, jsonify, getelem, getprop, haskey, join,
typify, size, slice, pad, setpath,
walk.depth, transform.format, validate.basic, validate.invalid,
and every group under `sentinels`.
```

(This flag is a property of the function's contract, not the corpus, so it is
not encoded in `Entry`. If a port disagrees, the corpus + canonical TS win.)

## 5. Worked example (TypeScript, `getpath`)

```ts
import { TestProvider, equal, errorMatches, structMatch } from './provider'
import { getpath } from '../../../typescript/dist/StructUtility' // your port's import

const provider = TestProvider.load()

for (const e of provider.entries('getpath')) {
  const label = e.id ?? `${e.function}/${e.group}#${e.index}`
  const vin = e.input.in
  if (e.expect.kind === 'error') {
    let threw = false
    try { getpath(vin.store, vin.path) } catch (err: any) {
      threw = true
      assert(errorMatches(e.expect.error!, err.message), label)
    }
    assert(threw, `${label}: expected an error`)
  } else if (e.expect.kind === 'value') {
    assert(equal(e.expect.value, getpath(vin.store, vin.path)), label)
  } else if (e.expect.kind === 'absent') {
    assert(equal(null, getpath(vin.store, vin.path)), label)
  } else if (e.expect.kind === 'match') {
    const res = getpath(vin.store, vin.path)
    assert(structMatch(e.expect.match, { in: e.raw.in, out: res }).ok, label)
  }
}
```

Use your language's own test framework for `assert` and iteration — the provider
is framework-agnostic on purpose.

## 6. Rules

- **Never edit the corpus** to make a test pass (repo-wide rule; see top-level
  `AGENTS.md`). If a port disagrees with a case, the port is wrong.
- **Keep the provider a pure data utility.** Comparison helpers must stay
  side-effect-free; execution and assertion belong in the test you write.
- **Provenance in failures.** Always include `entry.id` (or
  `function/group#index`) in assertion messages so a failure points at one case.
