# AGENTS.md — Lua port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Lua port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript in [`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
> and pinned by [`../build/test/`](../build/test/). A behaviour change is
> never "just fix it in Lua" — change the canonical + corpus first, then
> mirror it here.

## Layout

```
lua/
├── makefile                # lowercase — note the casing
├── setup.sh                # bootstrap: installs Lua/LuaRocks + test deps
├── struct.rockspec         # package metadata; test-only deps listed here
├── src/
│   ├── struct.lua          # the library (the public module table)
│   └── regex.lua           # in-tree RE2-subset Thompson-NFA engine (pure Lua)
└── test/
    ├── runner.lua          # JSONIC corpus driver
    ├── struct_test.lua     # busted suite (corpus-driven)
    ├── regex_test.lua      # regex unit tests
    ├── regex_pathological.lua  # cross-port pathological-input panel
    └── walk_bench.lua      # walk() benchmark (gated on WALK_BENCH=1)
```

The public API is the table `src/struct.lua` returns at the bottom of the
file. `../tools/check_parity.py` checks that table against the canonical
`export { … }` block (case/underscore-insensitively), so adding/removing a
field there changes parity.

## Commands

```bash
make setup           # ./setup.sh — install Lua/LuaRocks + test deps (first run)
make test            # busted over test/*test.lua (against the shared corpus)
make lint            # luacheck src test  +  stylua --check src test
make format-check    # stylua --check src test
make bench           # WALK_BENCH=1 lua test/walk_bench.lua
make clean           # rm -rf luacov.* .busted
```

`make test-lua` / `make lint-lua` from the repo root wrap the same commands.
The toolchain (Lua, LuaRocks, busted, luacheck, StyLua) is **not always
installed** — if you can't run a target, say so; don't claim a change works.

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, …), exposed
  as fields on the module table. `select` is exported under that name but is
  `select_fn` internally to avoid shadowing the Lua built-in.
- **Lua >= 5.3** is required for the native bitwise operators (`&`, `|`,
  `<<`) that `typify` and the type flags use. Don't backport to 5.1/5.2.
- **Zero third-party runtime deps.** `src/struct.lua` + `src/regex.lua` use
  only the Lua stdlib. The rockspec's `busted`/`luassert`/`dkjson`/
  `luafilesystem` are **test-only** — never `require` them from `src/`.
- **One table type, two roles.** Maps and lists are both tables; the
  `__jsontype` metatable field (`'object'` / `'array'`) distinguishes them.
  Build with `jm`/`jt` (or set the field) — don't leave an empty or literal
  table unclassified.
- **`injdef` collapses trailing args.** `transform`/`validate` take one
  optional `injdef` table (`{ extra =, errs =, modify = }`) where canonical
  TS spreads `extra`/`modify`/`collecterrs`; `$APPLY` is called
  `fn(resolved, store, inj)`. These signatures are port-local (unit tests,
  not the corpus — see [`../NOTES.md`](../NOTES.md)).

## Gotchas

- **`nil` is the only absent value.** Lua has no separate null, so the port
  is **Group A throughout** — a stored `nil` is "no value". The corpus uses
  `"__NULL__"` / `"__UNDEF__"` / `"__EXISTS__"` sentinels where it must
  distinguish them (see [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md)).
- **0-based external paths, 1-based storage.** `getpath(list, '0')` is the
  first element; the translation is internal. Don't "fix" call sites.
- **`escre` escapes Lua patterns, not RE2.** It is for `string.match` /
  `string.gsub` callers and is distinct from the `re_*` engine in
  `regex.lua`. Don't conflate the two.
- **Regex is the in-tree Thompson NFA** in `regex.lua` (RE2 subset;
  ECMA-style zero-width `re_replace` → `"XXbXcX"`). Backref/lookaround don't
  match by design; pathological-input differences across engine families are
  **documented, not bugs** ([`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md)) —
  don't diverge to "fix" them.
- **Editing here is downstream.** After any canonical behaviour change:
  update `../build/test/*.jsonic`, make the canonical TS pass, then mirror
  here, `make test`, and run `python3 ../tools/check_parity.py` + `make test`.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
