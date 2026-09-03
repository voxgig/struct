# AGENTS.md — working in the `voxgig/struct` repo

Guidance for AI coding agents (and the humans reviewing them) working in
this repository. If you read one file before touching anything, read this
one. For the user-facing documentation see [`README.md`](./README.md) (overview)
and [`DOCS.md`](./DOCS.md) (the full guide); before writing a sentence that
ships, read [`STYLE-GUIDE.md`](./STYLE-GUIDE.md).

> **TL;DR**
> 1. **TypeScript is canonical.** Behaviour is defined by
>    [`typescript/src/StructUtility.ts`](./typescript/src/StructUtility.ts).
>    Every other language is a *port* of it.
> 2. **The shared JSON corpus is the contract.** The `.aon` files in
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
| typescript | javascript, python, go, php, ruby, lua, rust, c, csharp, zig, cpp, perl, swift, clojure, ocaml, scala, java, kotlin, dart, elixir, haskell, lean, boru | — |


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
├── DOCS.md              # the language-neutral guide in full (tutorial→reference)
├── AGENTS.md            # this file
├── STYLE-GUIDE.md       # normative for the reader-facing pages; two CI gates
├── design/              # reports & specs:
│   ├── REPORT.md        #   cross-port parity matrix (per-port function/test counts)
│   ├── NOTES.md         #   cross-cutting quirks & edge cases that fit nowhere else
│   ├── UNDEF.md / UNDEF_SPEC.md        # the absent-vs-null ("Group A/B") semantics
│   └── REGEX.md / REGEX_API.md / REGEX_PATHOLOGICAL.md   # the regex dialect & API
├── Makefile             # top-level aggregate targets (test/lint/audit/scan)
├── build/test/*.aon  # the shared test corpus — the behavioural contract
├── tools/               # check_parity.py, check_corpus_regex.py
├── typescript/          # the canonical implementation (+ its own AGENTS.md/DOCS.md)
└── <lang>/              # one directory per port, each with the same layout
```

Each `<lang>/` directory contains: the implementation source, a test
runner that loads `build/test/*.aon`, a `Makefile` (at least `test`
and `lint`), a `README.md` (overview), a `DOCS.md` (comprehensive), and an
`AGENTS.md` (port-specific agent notes).


## The shared test corpus (the contract)

The behavioural spec lives in [`build/test/`](./build/test/) as `.aon`
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
for the reference). The in-situ runners are being replaced, port by port,
by [voxgig/omni](https://github.com/voxgig/omni) — the same algorithm as a
shared library. Most ports consume it as a local checkout (`$OMNI_HOME`,
then sibling paths; see `javascript/test/omni.js`, the first migrated
port). **typescript takes it from npm instead**, as the `@voxgig/omni`
devDependency — no checkout, no `OMNI_HOME` — and `typescript/tools/
omni-isolation.js` proves nothing shipped can reach it. The plan
and per-port status live in omni's `doc/plan/` register.

**Register 4.13 — omni is a test dependency of every port and a published
dependency of none.** Nothing a consumer resolves may declare it.
`python3 tools/omni_isolation.py` (`make scan-omni-isolation`) asserts that
across every port's library manifest, and it is a *declaration* check, not a
build-without-omni check. The difference matters: omni is a public repo, so
`github.com/voxgig/omni/go` resolves from proxy.golang.org with no tags at
all, and `go mod tidy` in a module with no checkout anywhere still writes the
require line, so for Go a checkout-absent build can pass while proving
nothing. That hole is Go's specifically — rust, swift, dart, haskell and
lean name omni by a literal *path*, which has no fallback — but a
declaration check is worth having everywhere for a separate reason: it
catches an omni import at the commit that introduces it, rather than at
the `go mod tidy` that publishes it. The CI job checks omni out *on
purpose* and then asserts the manifests stay clean. Four ports are UNCOVERED and say so in the output
rather than passing silently — `c`, `cpp` and `scala` have no manifest a
consumer resolves, and `zig` is not migrated. **A change is
"done" only when the corpus passes in the canonical TS and in every port
you touched.**


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
| Java | `java/` | `mvn test` | checkstyle + spotbugs | lowercase names; JUnit 6 |
| Kotlin | `kotlin/` | `./gradlew test` | detekt + ktlint | |
| Perl | `perl/` | `prove -Ilib t/` | perlcritic | `Tie::IxHash`-style ordered hash |
| Swift | `swift/` | `swift test` | swift-format | `allocator`-free; in-tree ordered dict |
| Clojure | `clojure/` | `clojure -M:test` | namespace compile check | mutable `LinkedHashMap`/`ArrayList` nodes; lower-smushed names |
| OCaml | `ocaml/` | `make test` (`ocamlc`) | type-check (`ocamlc -c`) | `value` variant; distinct Noval/Null (like TS); in-tree regex engine |
| Scala | `scala/` | `make test` (`scalac`/`scala`) | type-check (`scalac`) | `Value` ADT; distinct Noval/VNull (like TS); `java.util.regex` |
| Dart | `dart/` | `dart run test/runner.dart` | `dart analyze` | native `Map`/`List` nodes; single `null` (like Python); core `RegExp` |
| Elixir | `elixir/` | `elixir test/runner.exs` | compile check (`elixirc`) | ETS-backed heap nodes (`{:vmap,_}`/`{:vlist,_}`); single `nil` (like Python); core `Regex` |
| Haskell | `haskell/` | `ghc … test/Runner.hs` | type-check (`ghc -fno-code`) | `IORef`-backed nodes (whole API in `IO`); distinct `VNoval`/`VNull` (like OCaml); in-tree Vregex |
| Lean | `lean/` | `lake build` + runner | type-check (`lake build`) | heap-handle nodes (whole API in `SIO = ReaderT Ctx IO`); distinct `noval`/`null` (like OCaml); in-tree Vregex |
| boru | `boru/` | `boru run … test/runner.boru` | module load smoke | written in the boru language itself; `flex` nodes; single `none` (like Python); `mini re` (Go RE2); fn-box carriers for function values |

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
2. Add/adjust the corpus case(s) in `build/test/*.aon`.
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

- **Casing.** `getpath` (TS/JS/Py/Ruby/PHP/Lua/Perl/Java/Kotlin/Swift/Clojure/OCaml/Scala/Dart/Elixir/Haskell/Lean/boru),
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
- **Regex.** The Go stdlib `regexp` behaviour is the minimum `re_*`
  functionality for every port (find with captures, find_all, replace with
  `$1`..`$9` expansion) — enforced by the corpus `regex` group; see
  [`REGEX_API.md`](design/REGEX_API.md). Patterns must stay inside the **RE2 subset**
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


## Prose follows STYLE-GUIDE.md

[`STYLE-GUIDE.md`](./STYLE-GUIDE.md) is normative for the root
`README.md` and `DOCS.md` and for every port's `README.md` and `DOCS.md` —
50 pages. It carries the voice, the four-part section rules, the
banned-phrase list, the spaced em dash and its ration, and the rule that
documentation never cites a working document. Read it before writing a
sentence that ships; every rule in it was added after something went
wrong, and the counts behind each one are recorded.

Two gates enforce it and both run in CI, in `.github/workflows/docs.yml`:

| Gate | Runs | Covers |
| --- | --- | --- |
| `vale --minAlertLevel=error $(python3 tools/check_prose.py --files)` | `make scan-prose`, docs.yml | Google's rules plus the banned list, at the levels in `.vale.ini` |
| `python3 tools/check_prose.py` | `make scan-prose`, docs.yml | the banned list, em-dash spacing and ration, first person, no emoji, no working-document citations, resolving relative links, a complete page set |

The banned list is one file,
`.vale/styles/config/vocabularies/Struct/reject.txt`, read by both. The
page set is one function, `pages()` in `tools/check_prose.py`, printed by
`--files` and handed to Vale. Add a phrase or a page in one place and both
gates pick it up; there is no second copy to keep in step.

**Every port carries both a `README.md` and a `DOCS.md`, and the gate
fails if one goes missing.** Existence is not membership: a page that is
simply absent would otherwise drop out of the set and both gates would
report green on the 49 that remain, with nothing saying the fiftieth had
stopped being read.

**This file is not documentation, and the docs may not cite it.** Nor may
they cite `CLAUDE.md`, `design/DOC_EXAMPLES.md`, the assessments, or any
future `*_PLAN.md`. They are working documents: written for the people
changing this repository and revised as the code moves. State the fact in
the page that owns it instead. `design/`'s *specifications* — `REGEX*.md`,
`UNDEF*.md`, `TESTSPEC_MODEL.md`, `REPORT.md`, `NOTES.md` — are normative
and stay freely citable; the guide's "What stays linkable, and why"
explains the split.

**Three Google rules are switched off** in `.vale.ini` in favour of house
rules that live in `tools/check_prose.py`: `Google.EmDash` (this project
spaces the em dash — 589 of them, none unspaced), `Google.We` and
`Google.FirstPerson`. A Google rule switched off in favour of a house rule
that is not real is worse than no rule at all, so if you switch one off,
write the replacement first.

## Release and publish

Two tag namespaces, because there are two kinds of thing to release.

| what | version lives in | released by | tag |
| --- | --- | --- | --- |
| npm `@voxgig/struct` | `typescript/package.json` | `publish.yml` (CI, OIDC) | `v<version>` |
| npm `@voxgig/struct-js` | `javascript/package.json` | `publish.yml` (CI, OIDC) | `javascript/v<version>` |
| crates.io `voxgig-struct` | `rust/Cargo.toml` | `publish.yml` (CI, OIDC) | `rust/v<version>` |
| each of the 21 other ports | that port's manifest | `make publish-<lang>` | `<lang>/v<version>` |

**Three ports are on the CI path**: typescript and javascript on npm, rust
on crates.io. Each has a trusted publisher registered against
`publish.yml`, so each is released by dispatching that workflow rather than
by `make publish-<lang>`. Both of the newer two keep the
`<lang>/v<version>` tag shape every other port uses; only the credential
and the operator changed.

**The javascript package is renamed to `@voxgig/struct-js`, and that name
has no trusted publisher yet.** npm registers a trusted publisher only on a
package that already exists, so the first release under the new name cannot
go over OIDC: publish it with a token (`make -C javascript publish`, then
`npm stage approve`), register the publisher against `publish.yml` on the
new package's settings page, and every release after that goes back through
CI. Dispatching `publish.yml` with target `javascript` before that
registration fails the OIDC exchange, which npm reports as a 404.

The old `@voxgig/structjs` ends at 0.1.1 and is not published again;
deprecate it at the new name. The new package starts at **0.1.2**, because
`javascript/v0.1.1` is already tagged for the old one and every guard on
the release path compares `javascript/package.json` against that one tag
namespace, whatever the npm name under it.

**Targets are named by port, not by registry** — `typescript`,
`javascript`, `rust`. The dispatch input used to offer `npm`, which stopped
identifying anything the moment a second npm package joined it.

`PUBLISH_LANGS` in the root `Makefile` lists every port with a publish flow
(all but boru); `typescript` and `rust` are in it but should go through CI,
per above. Each `make publish-<lang>` publishes to that ecosystem's
registry **where one exists** (npm, PyPI, crates.io, NuGet, RubyGems,
LuaRocks, Maven Central, CPAN) and **always** pushes `<lang>/vX.Y.Z`.
Registry-less ports — Go, PHP/Packagist, Swift, Zig, C, C++ — release *purely*
by that tag.

**There is no `publish-all`, deliberately.** Each publish is irreversible and
cuts a version tag, so they are one command each.

`make status` (`tools/release_status.py`) is the dashboard. Start there — but
know what it does and does not do:

- **It covers 22 of the 24 ports.** Its `PORTS` table omits `lean` and `boru`.
  `boru` has no publish flow so that is right; **`lean` does** — it is in
  `PUBLISH_LANGS` — so a pending or mismatched Lean release shows up nowhere.
- **STATUS compares LOCAL against TAG only.** The registry column is a
  cross-check, not an input: `status()` reports `released` whenever local and
  tag agree and the registry is anything other than `absent`/`?`. It never
  compares the registry version to the other two, so it can call a release
  complete while the registry still serves an older version.
- **It reads only `<lang>/v*` tags.** `_add_tag` matches `^([a-z+]+)/v(.+)$`
  and silently drops anything else — including the bare `v*` tags that are the
  npm package's real release markers. See below.

### The three OIDC ports go through CI, not the Makefile

**Actions → publish → Run workflow** on `main`, picking `target:
typescript`, `javascript` or `rust`; or push the matching tag by hand
(`v<version>`, `javascript/v<version>`, `rust/v<version>`). One target per
run: the three packages version independently and every publish is
irreversible, which is the same reason there is no `publish-all`.

`make publish` from `typescript/` and `javascript/`, and `make
publish-rust`, also exist — **prefer the workflow**:

- The Makefile path publishes over a long-lived registry token (an **npm
  token**, a **`CARGO_REGISTRY_TOKEN`**), bypassing OIDC trusted publishing
  and its provenance attestation entirely.
- For typescript it cuts `typescript/v<version>`, a *different tag* from the `v<version>`
  that `publish.yml` writes and that the 16 bare `v*` tags actually use.
  There is exactly one `typescript/v*` tag in this repo (`typescript/v0.2.1`)
  against 16 bare ones.
- **Both npm ports need two commands, not one.** `make publish` runs
  `npm stage publish`, which uploads the tarball and defers the 2FA
  proof-of-presence: the version is *staged*, not released. `npm stage
  approve` is what puts it on the registry, and only then does `make tag`
  cut `<lang>/v<version>`. The tag is deliberately a second command,
  gated on the registry actually serving the version — the same order
  `publish.yml` keeps by having its tag job `needs` a successful publish,
  so that a tag only ever exists for a version a consumer can install.
  The single-command version of this used to tag and report "Published"
  the moment staging returned, which left a release tag with no release
  behind it whenever an approval was rejected, expired or forgotten.
- **`npm stage publish` needs npm >= 11.19** (it landed between 11.9.0 and
  11.19.1). Older npm answers `Unknown command: "stage"`, which reads like
  a typo and is not one.

**The two namespaces are already out of step, and `make status` is the one
thing that cannot see it.** The dashboard reads only `<lang>/v*`, so for
typescript it tracks the abandoned `typescript/v0.2.1` and ignores every bare
`v*` tag — including the current `v0.3.2`. It therefore reports:

```
typescript  0.3.2  typescript/v0.2.1  0.3.2  publish-pending
```

publish-pending for a version that is on npm. That is not a stale row waiting
on a release; it is what the dashboard will keep saying after every successful
CI release, until it learns about bare tags. Treat typescript's row as
unreliable, and read `git ls-remote --tags origin 'v*'` for the truth.

**`make publish-rust` cuts the same `rust/v<version>` tag the workflow does**,
so unlike typescript there is no split namespace to reconcile — the only
difference is the credential. `make status` reads rust's row correctly.

The workflow reads the version from `typescript/package.json` or
`rust/Cargo.toml`, so **bump it first in a reviewed PR**, then dispatch. It
refuses a pushed tag that disagrees with the manifest version, and refuses a
tag that already points at a different commit.

**Rehearse with `dry_run: true`** before a first release, or after touching
`publish.yml`. It runs every guard and every test, packs the artifact with
`--dry-run`, and publishes and tags nothing. For rust it also mints and
immediately revokes a real crates.io token — the only way to prove the
registry-side trusted publisher is configured correctly without spending a
version number on finding out. A dry run is the one path exempt from the
"dispatches must come from main" guard, precisely because it cannot leave
anything behind.

**A pushed tag is not checked against `main`.** The "Dispatches must come from
main" guard is gated on `github.event_name == 'workflow_dispatch'`; the push
path only checks the tag against the package version. Tag a feature commit and
the workflow publishes *that commit* — code that never landed in the reviewed
release, irreversibly, since npm will not take the version again. If you push
a tag by hand, point it at a commit on `main`. The dispatch path has no such
hole, which is the strongest reason to prefer it.

### Why publish and tag are two jobs, and why both registries share one file

`publish.yml` holds six jobs, a publish/tag pair per port: `publish` / `tag`
for typescript, `publish-javascript` / `tag-javascript`, and `publish-rust` /
`tag-rust`. Each pair splits `id-token: write, contents: read` from
`contents: write`. That split is load-bearing, not tidiness:

- OIDC **cannot** write a tag — its audience is the registry, not GitHub.
- `checkout` persists its token into the git config for a whole job, so one
  combined job would run every dependency `postinstall` — or every `cargo`
  build script and proc macro — alongside a repository-write credential.
- They cannot be split across two **files**: npm and crates.io each register a
  trusted publisher against a single workflow **filename**, and a ref pushed
  with `GITHUB_TOKEN` starts no further workflow run — so "tag in A, publish
  on the tag" publishes nothing, silently. npm refuses an unregistered
  workflow's OIDC token as **404, not 403**, which reads as "package does not
  exist"; crates.io fails the exchange in `crates-io-auth-action`, before
  `cargo publish` runs.

That is also why both registries live in *this* file rather than one each:
each can name only one filename, and they both name `publish.yml`. Renaming
it breaks both until both are updated.

### Irreversible

- **npm never allows republishing a version.** Bump and release again.
- **crates.io never allows republishing a version either**, and `yank` only
  stops *new* dependents resolving it — the artifact stays downloadable.
- **A Go tag is permanent**: `proxy.golang.org` and `sum.golang.org` cache a
  version immutably, and moving or deleting the tag reaches users as a
  security error. Withdraw only via `retract` in a new version. The same
  caution applies to every registry-less port here.

`voxgig/apidef`'s `docs/how-to/release-and-tag.md` carries the fullest
write-up of this design.


## Where to look next

- Conceptual + how-to + full reference: [`DOCS.md`](./DOCS.md)
- Writing any of it: [`STYLE-GUIDE.md`](./STYLE-GUIDE.md)
- Per-port specifics: `<lang>/DOCS.md`, `<lang>/README.md`, `<lang>/AGENTS.md`
- Parity matrix: [`REPORT.md`](design/REPORT.md)
- Edge cases & quirks: [`NOTES.md`](design/NOTES.md), [`UNDEF.md`](design/UNDEF.md)
- Regex: [`REGEX.md`](design/REGEX.md), [`REGEX_API.md`](design/REGEX_API.md)
</content>
</invoke>
