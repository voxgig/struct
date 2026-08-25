# AGENTS.md — JavaScript port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the JavaScript port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript source ([`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts))
> and pinned by [`../build/test/`](../build/test/). When this port disagrees
> with the corpus, this port is wrong — fix it here, never edit the corpus.

## Layout

```
javascript/
├── src/struct.js           # the implementation + public API (module.exports)
├── test/omni.js            # resolves the voxgig/omni checkout (the runner)
├── test/struct.test.js     # corpus-driven tests
├── test/client.test.js     # SDK/client smoke test
├── test/regex_pathological.test.js  # regex edge-case panel
├── test/sdk.js             # test SDK wrapping StructUtility
├── test/walk-bench.test.js # walk benchmark (run via npm run walk-bench)
├── eslint.config.mjs       # flat config (ESLint 10)
├── .prettierrc.json        # Prettier config
└── package.json
```

The public API is the `module.exports = { … }` block at the bottom of
`src/struct.js`. `../tools/check_parity.py` checks it against the canonical
export list, so adding/removing a public name there affects parity.

## Commands

Tests need a local [voxgig/omni](https://github.com/voxgig/omni) checkout
(this port has not yet moved to the published `@voxgig/omni-js`): clone it
as a sibling of
this repo, or point `OMNI_HOME` at it. Without one, `npm test` aborts
with `struct: voxgig/omni checkout not found - set OMNI_HOME`.

```bash
npm install
npm test              # node --test test/struct.test.js test/client.test.js
OMNI_HOME=/path/to/omni npm test   # when omni is not a sibling checkout
npm run lint          # eslint src test
npm run format:check  # prettier --check
npm run lint:fix      # eslint --fix
npm run format        # prettier --write
```

There is **no build step** (`npm test` runs the source directly). `make test`
wraps `npm test`; `make lint` runs `npm run lint` *and* `npm run format:check`;
`make build` is a no-op; `make audit` runs `npm audit`.

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, …), mirroring
  TypeScript exactly.
- **Plain JSON-shaped values.** The data model is untyped JSON on purpose;
  this is plain CommonJS JavaScript, so there are no compile-time types to
  "tighten" — the corpus is the real contract.
- **`no-useless-assignment` is disabled** in `eslint.config.mjs`: the source
  uses deliberate init-then-reassign patterns so it ports line-for-line to
  other languages. Keep that style; don't "optimise" it away.
- **Module type is CommonJS** (`"type": "commonjs"`); require/`module.exports`,
  not ESM `import`/`export`.

## Gotchas

- **The runner is voxgig/omni, not in-tree.** `test/omni.js` resolves a
  local omni checkout ($OMNI_HOME, then sibling paths) and re-exposes
  omni's struct-compat shim behind the old `require('./runner')` API. The
  library itself never touches omni - it is a test-only dependency, and
  struct's zero-runtime-dependency rule is untouched.
- **No build, but tests read a compiled corpus.** The runner reads
  `../build/test/test.json` (the aggregated form of `../build/test/*.aontu`).
  If a corpus case looks stale, regenerate it from the canonical side — do
  not edit it to make this port pass.
- **`null` is not `undefined`.** JS distinguishes them and so does `struct`:
  Group A readers treat stored `null` as absent; Group B processors preserve
  it. Re-read the Group A/B rule ([`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md))
  before touching any read/merge/clone path.
- **Editing here is downstream of a canonical change.** If you are matching a
  TS behaviour change: update this port to follow it, run `npm test`, then
  `python3 ../tools/check_parity.py`. The corpus and canonical TS change
  first, elsewhere.
- **Regex stays in the RE2 subset.** ECMAScript `RegExp` allows
  backreferences/lookaround, but they don't port. Pathological-input
  differences (catastrophic backtracking; zero-width `re_replace`) are
  documented in [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md) — do
  not "fix" them by diverging.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- Canonical source: [`../typescript/`](../typescript/) · The contract:
  [`../build/test/`](../build/test/) · Parity: `../tools/check_parity.py`
