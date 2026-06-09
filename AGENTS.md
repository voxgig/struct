# AGENTS.md — working in the `voxgig/struct` repo

Guidance for AI coding agents (and the humans reviewing them) working in
this repository. If you read one file before touching anything, read this
one. For the user-facing documentation see [`README.md`](./README.md) (overview)
and [`DOCS.md`](./DOCS.md) (the comprehensive guide).

> **TL;DR**
> 1. **TypeScript is canonical.** Behaviour is defined by
>    [`typescript/src/StructUtility.ts`](./typescript/src/StructUtility.ts).
>    Every other language is a *port* of it.
> 2. **The shared JSON corpus is the contract.** The `.jsonic` files in
>    [`build/test/`](./build/test/) run against every port. If a port
>    disagrees with the corpus, the port is wrong.
> 3. **Change the canonical first, then propagate.** A behaviour change
>    means: edit the TS source, add/adjust a corpus case, then update
>    every port and re-run its tests.
> 4. **Keep parity.** Every "complete" port defines every canonical
>    public function. `python3 tools/check_parity.py` must stay green.
> 5. **Zero runtime dependencies.** No port may add a third-party
>    runtime dependency. Test-only tooling is the only exception.


## What this repository is

`struct` is one small, fixed API for manipulating JSON-shaped data —
lookups, deep merge, by-example transform, by-example validate, tree
walk, path get/set, selection. It is defined **once** in TypeScript and
**ported faithfully** to every language a Voxgig SDK runs in, so that
`getpath(store, 'a.b.c')` returns the same value in TypeScript, Python,
Go, Rust, C, and every other port.

The value of the project *is* that uniformity. The job when working here
is almost never "make this port clever"; it is "make this port agree with
the canonical TypeScript, case for case, in idiomatic local style."

Ports and their status (full table in [`README.md`](./README.md), parity
matrix in [`REPORT.md`](design/REPORT.md)):

| Canonical | Complete | Partial |
|---|---|---|
| typescript | javascript, python, go, php, ruby, lua, rust, c, csharp, zig, cpp, perl, swift | java, kotlin |


## Prime directives (do not break these)

1. **Do not change behaviour in a single port.** If a port's output is
   "wrong", confirm against the corpus and the canonical TS. Either it's a
   port bug (fix the port to match) or it's a canonical change (change TS +
   corpus + *all* ports). Never let one port drift.
2. **Do not edit the corpus to make a failing port pass.** The corpus
   encodes canonical TS behaviour. Change it only when you are
   deliberately changing canonical behaviour, and then verify the
   canonical TS still passes it first.
3. **Do not add runtime dependencies.** Every port's library proper has
   zero third-party runtime deps (it uses the host stdlib, or a small
   in-tree helper — see [`REPORT.md`](design/REPORT.md)). Test harnesses may use
   a JSON/test library; the library may not.
4. **Do not rename public functions.** The public surface is the
   `export { … }` block in the canonical TS. Casing is per-language
   convention (see below) but the names are fixed.
5. **Do not push to `main`.** Work on the branch you were given; commit
   with clear messages; only open a PR if explicitly asked.


## Repository map

```
.
├── README.md            # user-facing overview + language-neutral reference
├── DOCS.md              # comprehensive language-neutral guide (tutorial→reference)
├── AGENTS.md            # this file
├── design/              # reports & specs:
│   ├── REPORT.md        #   cross-port parity matrix (per-port function/test counts)
│   ├── NOTES.md         #   cross-cutting quirks & edge cases that fit nowhere else
│   ├── UNDEF.md / UNDEF_SPEC.md        # the absent-vs-null ("Group A/B") semantics
│   └── REGEX.md / REGEX_API.md / REGEX_PATHOLOGICAL.md   # the regex dialect & API
├── Makefile             # top-level aggregate targets (test/lint/audit/scan)
├── build/test/*.jsonic  # the shared test corpus — the behavioural contract
├── tools/               # check_parity.py, check_corpus_regex.py
├── typescript/          # the canonical implementation (+ its own AGENTS.md/DOCS.md)
└── <lang>/              # one directory per port, each with the same layout
```

Each `<lang>/` directory contains: the implementation source, a test
runner that loads `build/test/*.jsonic`, a `Makefile` (at least `test`
and `lint`), a `README.md` (overview), a `DOCS.md` (comprehensive), and an
`AGENTS.md` (port-specific agent notes).


## The shared test corpus (the contract)

The behavioural spec lives in [`build/test/`](./build/test/) as `.jsonic`
files (JSON with comments), one per area: `getpath`, `merge`, `walk`,
`inject`, `transform`, `validate`, `select`, `minor`, `sentinels`, etc.
`test.json` is the compiled/aggregated form the runners read.

Each entry is roughly `{ in, out }` (or `{ in, err }`, or `{ args, out }`):
call the named function with `in`/`args`, expect `out` (or an error
matching `err`). Special string sentinels bridge representations the test
language cannot express directly:

- `"__NULL__"` — a real JSON `null` (distinct from "absent").
- `"__UNDEF__"` / `"__EXISTS__"` — absent vs. present markers used by the
  `match` mechanism.

Every port ships a runner that walks these entries and asserts equality
the same way (see [`typescript/test/runner.ts`](./typescript/test/runner.ts)
for the reference). **A change is "done" only when the corpus passes in
the canonical TS and in every port you touched.**


## Per-language quick reference

Run from the repo root: `make test-<lang>` / `make lint-<lang>`. Or `cd`
into the directory and use its `Makefile`. First run installs deps.

| Lang | Dir | Test | Lint | Notes |
|---|---|---|---|---|
| TypeScript | `typescript/` | `npm test` (needs `npm run build` first) | `npm run lint` + prettier | canonical; ESLint 10, TS 6 |
| JavaScript | `javascript/` | `npm test` | `npm run lint` + prettier | |
| Python | `python/` | `python3 -m unittest discover -s tests` | ruff + mypy | function names match TS (not PEP8) |
| Go | `go/` | `go test ./...` | golangci-lint, `go vet`, gofmt | PascalCase; `ListRef` wrapper |
| PHP | `php/` | `vendor/bin/phpunit` (`composer install` first) | phpcs (PSR-12) + phpstan | PHPUnit 12 |
| Ruby | `ruby/` | `ruby test_voxgig_struct.rb` | rubocop | |
| Rust | `rust/` | `cargo test` | clippy + `cargo fmt --check` | snake_case; in-tree `OrderedMap`/regex |
| C | `c/` | `make test` (gcc, no deps) | clang-tidy + clang-format | `voxgig_` prefix; vendored JSON + regex |
| C++ | `cpp/` | `make test` (needs `nlohmann/json` header) | clang-tidy + clang-format | `_v`/`_str` suffix variants |
| C# | `csharp/` | `dotnet test` | Roslyn analyzers | PascalCase; SDK pinned to 8.0 on purpose |
| Zig | `zig/` | `zig build test` | `zig build` + `zig fmt` | `allocator` is the first parameter |
| Java | `java/` | `mvn test` | checkstyle + spotbugs | lowercase names; partial port (JUnit 6) |
| Kotlin | `kotlin/` | `./gradlew test` | detekt + ktlint | partial port |
| Perl | `perl/` | `prove -Ilib t/` | perlcritic | `Tie::IxHash`-style ordered hash |
| Swift | `swift/` | `swift test` | swift-format | `allocator`-free; in-tree ordered dict |

Repo-wide: `make test` / `make lint` / `make audit` (supply-chain) /
`make scan` (secrets, SAST, parity, regex, spelling, markdown) /
`make analyze` (all three). Some `scan`/`lint` tools must be on PATH
(gitleaks, semgrep, osv-scanner, actionlint, shellcheck, cspell,
markdownlint, plus each language's linters).


## Standard workflows

### Fix a bug in one port (port disagrees with the corpus)
1. Reproduce: `make test-<lang>` and read the failing corpus case.
2. Compare the port's logic to the canonical TS for that function.
3. Fix the **port** to match the canonical. Do **not** touch the corpus.
4. `make test-<lang>` green, then `make lint-<lang>`.

### Change canonical behaviour (rare; affects everyone)
1. Edit [`typescript/src/StructUtility.ts`](./typescript/src/StructUtility.ts).
2. Add/adjust the corpus case(s) in `build/test/*.jsonic`.
3. `cd typescript && npm run build && npm test` — canonical passes.
4. Propagate the same logic to **every** port; run each port's tests.
5. `python3 tools/check_parity.py` and `make test` stay green.
6. Document any unavoidable per-port variance in the port's `README.md`
   and, if cross-cutting, in [`NOTES.md`](design/NOTES.md).

### Add a new public function
1. Implement + export it in the canonical TS; add corpus coverage.
2. Add it to the canonical export list (the parity tool reads that block).
3. Port it to every "complete" port, in local casing.
4. `python3 tools/check_parity.py` must report every complete port `ok`.


## Conventions

- **Casing.** `getpath` (TS/JS/Py/Ruby/PHP/Lua/Perl/Java/Kotlin/Swift),
  `GetPath` (Go/C#), `get_path` (Rust), `voxgig_getpath` (C — and C++ adds
  `_v`/`_str` variants). Parity is checked case/underscore-insensitively.
- **Absent vs. null ("Group A/B").** See [`UNDEF_SPEC.md`](design/UNDEF_SPEC.md).
  Group A readers (`getprop`, `getelem`, `haskey`, `isempty`, `isnode`)
  treat a stored `null` as "no value". Group B value-processors
  (`setprop`, `clone`, `walk`, `merge`, `inject`, `transform`, `validate`,
  `select`, …) preserve `null` literally. This distinction is the single
  most common source of port bugs — get it right.
- **Ordered maps.** Map key order must match insertion order (TS object
  semantics). Languages without an ordered-map stdlib type hand-roll one
  in-tree (see `REPORT.md`); never swap in an unordered map.
- **Regex.** Patterns must stay inside the **RE2 subset**
  ([`REGEX.md`](design/REGEX.md)); the uniform six-function API is in
  [`REGEX_API.md`](design/REGEX_API.md). `python3 tools/check_corpus_regex.py`
  enforces the corpus stays in-subset. Backtracking-engine ports
  (Python/PHP/Perl/Ruby/JS) and RE2/NFA ports differ on a few pathological
  inputs — documented in [`REGEX_PATHOLOGICAL.md`](design/REGEX_PATHOLOGICAL.md);
  do not "fix" these by diverging.
- **Commit messages.** Conventional, scoped (`fix(go): …`, `deps(php): …`,
  `docs: …`). Describe *what changed and why*, and note test results.


## Gotchas that trip up agents

- **`npm test` needs a build first.** The TS runner executes compiled JS
  in `dist-test/`; run `npm run build` (or `npm run reset`) before `npm test`.
- **Editing only the failing port might be a canonical bug.** If multiple
  ports fail the same way, suspect the corpus/canonical, not the port.
- **`null` is not `undefined`.** Most JSON parsers conflate them; this
  library does not. Re-read the Group A/B rule before touching any
  read/merge/clone path.
- **Don't reorder map keys** to satisfy a diff — fix the comparison or the
  ordered-map usage instead.
- **Function-value signatures** (`$APPLY`, `$FORMAT`, callable `alt`) vary
  by port and are covered by *port-local unit tests*, not the JSON corpus —
  see [`NOTES.md`](design/NOTES.md).
- **Toolchains may be missing** in a given environment (Lua, C#, Zig,
  Swift are common gaps). If you can't build a port, say so — don't guess
  that a change works.


## Where to look next

- Conceptual + how-to + full reference: [`DOCS.md`](./DOCS.md)
- Per-port specifics: `<lang>/DOCS.md`, `<lang>/README.md`, `<lang>/AGENTS.md`
- Parity matrix: [`REPORT.md`](design/REPORT.md)
- Edge cases & quirks: [`NOTES.md`](design/NOTES.md), [`UNDEF.md`](design/UNDEF.md)
- Regex: [`REGEX.md`](design/REGEX.md), [`REGEX_API.md`](design/REGEX_API.md)
</content>
</invoke>
