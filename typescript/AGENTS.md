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

**`npm test` needs a voxgig/omni checkout, and needs it BUILT.** The corpus
runner is omni's, consumed as a local checkout that is not published;
`test/omni.ts` resolves it from `$OMNI_HOME` or a sibling path. Because the
shim loads omni's COMPILED output, `npm run build` in the omni checkout is a
prerequisite too - `dist/` is not committed there. There is no `omni-check`
make target here, and deliberately: `test/omni.ts` already fails with the
reason, and it distinguishes "no checkout" from "checkout present but not
built", which a Makefile probe would not.

Only the tests need it. `npm run build`, `npm run lint` and `npm run
typecheck` do not, and `package.json` gains no dependency.

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
