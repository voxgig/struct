# AGENTS.md — Swift port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Swift port.

> **This is a port, not the canonical.** Behaviour is defined by the
> canonical TypeScript and pinned by [`../build/test/`](../build/test/). If
> this port disagrees with the corpus, the port is wrong — fix it here, do
> not edit the corpus.

## Layout

```
swift/
├── Package.swift                       # SwiftPM, swift-tools 5.9, zero runtime deps
├── Sources/VoxgigStruct/               # the library target
│   ├── Value.swift                     # the Value enum + VList/VMap/Sentinel
│   ├── OrderedDictionary.swift         # in-tree insertion-ordered map (the only ordered-map type)
│   ├── Constants.swift  JSON.swift     # S_*/T_*/M_* constants; JSON parse/stringify
│   ├── Minor.swift  Walk.swift  Merge.swift  Path.swift
│   ├── Inject.swift  Injection.swift   # inject engine + Injection reference class
│   └── Transform.swift  Validate.swift  Select.swift
└── Tests/VoxgigStructTests/            # XCTest target VoxgigStructTests
    ├── CorpusTests.swift               # shared-corpus driver (loads ../build/test/test.json)
    ├── SmokeTests.swift  QuickTest.swift  RegexPathologicalTests.swift
```

The public surface is the set of top-level `public func`s across these
files; `../tools/check_parity.py` checks the canonical 48 names are present.

## Commands

```bash
make build          # swift build - the LIBRARY alone (no omni)
make test           # the shared corpus, on voxgig/omni
make lint           # swift-format lint --strict --recursive Sources Tests
make inspect        # swift --version + package describe
make clean          # swift package clean + rm -rf .build
make reset          # clean + rm -rf Package.resolved
```

- **The corpus runner is voxgig/omni**, a local checkout `make test` finds via
  `$OMNI_HOME` or beside this repository and points `.omni-runner` (a
  gitignored symlink) at. `Package.swift` declares the dependency only when
  that symlink is there, and only for the TEST target, so `swift build`
  compiles the library alone (register 4.13). The symlink is not decoration:
  SwiftPM takes a path dependency's identity from the last path component, and
  omni's package lives at `omni/swift` - the same basename as this package,
  which SwiftPM reads as a self-dependency.
- **`Tests/VoxgigStructTests/CorpusTests.swift` is a bridge plus a list of
  subjects.** `tostruct` / `toomni` convert between omni's `Json` and this
  port's `Value`; everything else - the entry loop, `fixjson`, deep equality,
  `err` and `match` handling - is omni's.
- **`match.args` needs the arguments back.** omni's `Json` is a value type, so
  a subject cannot write through the argument list even though `VMap` / `VList`
  are classes. `runsetflagsargs` takes a subject returning `(args, result)`.
- **An integral number becomes `.int`.** omni parses every JSON number as a
  Double; this port's `typify` reads T_integer / T_decimal off the case, so
  `tostruct` normalises. struct/go's shim and struct/clojure's bridge needed
  the same (voxgig/omni#13).
- **`in` fields are read RAW** (`lookup`, not `getprop`): the Group-A rule
  would turn an authored `alt: null` or `val: null` into absent, and
  `minor/getprop#51` and `minor/stringify#6` notice.

`make test-swift` / `make lint-swift` from the repo root wrap the same
commands. **The Swift toolchain is often absent** in CI/dev environments
(see [`../AGENTS.md`](../AGENTS.md) gotchas). If you can't build, say so —
don't claim a change works.

## Conventions specific to this port

- **Casing:** library functions keep **canonical lowercase** names
  (`getpath`, `setprop`, `keysof`, …) as top-level `public func`s — do not
  camelCase them, the name table must match every port. Methods on
  `Value`/`Injection` use Swift camelCase (`isNode`, `setval`, `child`).
- **One value type:** everything is the `Value` `indirect enum`. Containers
  are **classes** (`VList`, `VMap`) so lists/maps are reference-stable — the
  canonical merge/walk semantics require it. Never replace them with Swift
  value-type arrays/dicts.
- **Ordered maps:** every map is `VMap` over the in-tree
  `OrderedDictionary`. Swift's `Dictionary` is unordered; never swap it in
  (`jsonify`/`keysof`/`items` expose key order).
- **`.noval` vs `.null`:** `.noval` = canonical `undefined`/absent; `.null`
  = JSON null. They are distinct under `==`. Group A readers (`getprop`,
  `getelem`, `haskey`, `isempty`, `isnode`) treat stored `.null` as absent;
  Group B (`setprop`, `clone`, `walk`, `merge`, …) preserve it.
- **No throwing surface:** only `JSON.parse` throws. `validate`/`transform`
  accumulate `inj.errs.items` instead of throwing; `re_compile` returns
  `nil` on a bad pattern. Don't add `throws` to the public functions.
- **Zero runtime deps:** Foundation only; `OrderedDictionary.swift` is the
  in-tree ordered-map. Do not add a SwiftPM dependency to the library target.

## Gotchas

- **`getprop` is Group A** (returns `alt` for a stored `.null`); `lookup` is
  the Group-B raw reader. Pick the right one when porting a TS line — most
  read/merge/clone bugs are a Group A/B mixup.
- **Sentinels compare by `===`.** `setprop` only short-circuits on the
  `.sentinel(_)` case; a JSON-parsed `` "`$SKIP`": true `` map stays a
  `.map(_)`. Don't try to make map-shaped sentinels short-circuit.
- **Editing here never changes canonical behaviour.** A behaviour fix that
  isn't already in the corpus is a canonical change: do it in TypeScript +
  corpus first, then port here and re-run `python3 ../tools/check_parity.py`.
- **`make lint` soft-skips** when `swift-format` isn't on PATH (CI sets
  `CI=true` to make a missing tool a hard failure). Green local lint may
  mean "skipped", not "passed".

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  `../tools/check_parity.py` · Matrix: [`../REPORT.md`](../design/REPORT.md)
