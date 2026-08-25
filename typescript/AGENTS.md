# AGENTS.md — TypeScript port (canonical)

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the TypeScript port.

> **This is the canonical port.** Behaviour changes start *here*. When you
> edit `src/StructUtility.ts` you are changing the definition every other
> language must follow — so a change here is never "just this port".

## Layout

```
typescript/
├── src/StructUtility.ts   # THE canonical implementation + public API
├── src/tsconfig.json      # build config for src
├── test/omni.ts           # resolves the voxgig/omni checkout; the ONLY file
│                          #   that names the shared runner
├── test/utility/StructUtility.test.ts   # corpus-driven tests
├── test/regex_pathological.test.ts      # regex edge-case panel
├── test/direct.ts         # developer scratch (run via npm run test-direct)
├── eslint.config.mjs      # flat config (ESLint 10 + typescript-eslint)
└── package.json
```

The public API is the `export { … }` block at the bottom of
`src/StructUtility.ts`. `tools/check_parity.py` parses exactly that block,
so adding/removing a public name there changes what every other port is
required to define.

## Commands

```bash
npm install
npm run build        # tsc --build src test  (REQUIRED before npm test)
npm test             # node --test dist-test/**/*.test.js  (NEEDS omni, below)
npm run lint         # eslint src test  +  prettier --check
npm run typecheck    # tsc --build --force
npm run reset        # clean + reinstall + build + test
```

`make test` / `make lint` from this dir (or `make test-ts` from the root)
wrap the same commands.

**`npm test` needs nothing but `npm ci`.** The corpus runner is omni's,
taken from npm as the `@voxgig/omni` devDependency; `test/omni.ts` imports
`@voxgig/omni/compat/struct` directly. There is no checkout to resolve and no
`OMNI_HOME`. It is pinned EXACTLY - `"0.1.0"`, not `"^0.1.0"`: this repo
commits no lockfile (`.gitignore` line 150), so the manifest is the only
thing pinning it, and a 0.x caret floats to anything under 0.2.0. `make
omni-check` asserts the devDependencies-only isolation register 4.13
requires.

The other ports still resolve a checkout, and for them the old rules hold:
`$OMNI_HOME` or a sibling path, and for a port loading compiled output, a
built one. This port needs none of that any more.

Only the TESTS need omni. `npm run build`, `npm run lint` and `npm run
typecheck` do not. `package.json` names it, which it never did before, so
`make omni-check` (`tools/omni-isolation.js`) asserts it stays a
devDependency: absent from `dependencies`, absent from the production tree,
`dev: true` in the lockfile, and named by no shipped file. That is register
4.13's requirement, and it is checked in CI rather than trusted - which is
the lesson struct/go paid for.

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, …).
- **Types:** the data model is JSON-shaped `any` on purpose;
  `@typescript-eslint/no-explicit-any` is intentionally off. Don't try to
  "tighten" the public types — ports can't follow non-JSON types, and the
  corpus is the real contract.
- **`no-useless-assignment` is disabled** in `eslint.config.mjs`: the
  source uses deliberate init-then-reassign patterns so it ports
  line-for-line to other languages. Keep that style; don't "optimise" it.
- **Module type is CommonJS** (`"type": "commonjs"`); tests run the
  compiled JS in `dist-test/`.

## Gotchas

- **Always `npm run build` before `npm test`** — tests execute compiled
  output, not the `.ts` directly. A stale `dist-test/` will mask or fake
  results; `rm -rf dist dist-test` if in doubt.
- **TypeScript 6 narrows default `@types` inclusion** — the test tsconfig
  declares `"types": ["node"]` so node globals (`process`, `__dirname`,
  `node:test`) resolve. Don't remove it.
- **Editing here is a cross-port event.** After any behaviour change:
  update `../build/test/*.aontu`, rebuild+test here, then propagate to
  every port and run `python3 ../tools/check_parity.py` + `make test`.
- **`test/direct.ts` is scratch**, not part of the suite (the runner globs
  `*.test.js`). It is still linted.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  `../tools/check_parity.py`
</content>
