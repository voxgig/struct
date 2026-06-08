# AGENTS.md — Ruby port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Ruby port.

> **This is a port, not the canonical.** Behaviour is defined in
> [`../typescript/src/StructUtility.ts`](../typescript/src/StructUtility.ts)
> and pinned by [`../build/test/`](../build/test/). If Ruby disagrees with
> the corpus, the Ruby port is wrong — fix it here, don't touch the corpus.

## Layout

```
ruby/
├── voxgig_struct.rb        # the whole port: module VoxgigStruct + Injection class
├── test_voxgig_struct.rb   # corpus-driven test runner (minitest)
├── walk_bench.rb           # walk micro-benchmark (make walk-bench)
├── Gemfile                 # test-only dev deps (minitest, rubocop)
└── Makefile
```

The public surface is the set of `def self.…` methods on module
`VoxgigStruct`. `../tools/check_parity.py` matches those names against the
canonical TS `export { … }` block, case/underscore-insensitively.

## Commands

```bash
bundle install
make test         # ruby test_voxgig_struct.rb
make lint         # bundle exec rubocop
make audit        # bundler-audit check --update (needs gem install bundler-audit)
make walk-bench   # WALK_BENCH=1 ruby walk_bench.rb
```

`make test-rb` / `make lint-rb` from the repo root wrap the same commands.
There is no build step (`make build` is a no-op).

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, …) as module
  methods — **not** idiomatic snake_case. Parity beats Ruby style.
- **String keys:** the data model is JSON-shaped, so maps use string keys
  (`{ 'a' => 1 }`). Don't switch to symbol keys.
- **`nil` vs `UNDEF`:** `UNDEF = Object.new.freeze` is the "absent"
  sentinel; `nil` is the JSON-null scalar. Keep them distinct (Group A/B).
- **Ordered maps come free:** Ruby `Hash` is insertion-ordered, so there is
  no ordered-map wrapper to maintain — but never reorder keys to win a diff.
- **Deliberate port style:** the source mirrors the canonical TS
  line-for-line (init-then-reassign, `merge` built as a `walk`). Keep it;
  don't "optimise" it out of parity.

## Gotchas

- **`null` is not `UNDEF`.** Group A readers (`getprop`, `getelem`,
  `haskey`, `isempty`, `isnode`) treat a stored `nil` as absent; Group B
  processors preserve it. `setval` keeps the distinction. Re-read
  [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md) before touching any read/merge path.
- **Editing here is *not* a cross-port event** — unless you've found a
  canonical bug. A normal fix makes Ruby match the corpus and stops there.
- **Regex is backtracking (Onigmo).** Edges align with the JS/Python/PHP/
  Perl ports, not the RE2 ports — see
  [`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md). Don't "fix" a
  documented cross-engine difference by diverging; stay in the RE2 subset.
- **`joinurl` is defined twice** in the source (the second carries a
  `rubocop:disable Lint/DuplicateMethods`). If you touch it, keep both call
  sites passing rather than silently deleting one.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
