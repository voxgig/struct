# Documentation Example Validation — Design / Plan

**Status:** implemented (2026-06). `tools/check_doc_examples.py` + `tools/gen_doc_examples.py`
are wired into `make corpus` / `make gen-docs` / `make scan-docs-examples` and the
`docs-examples` + `corpus-freshness` CI jobs. 250 example anchors across all 16 ports validate
against the shared corpus; all 16 port test suites pass the doc-example corpus entries. The
sections below are the design as built (the original per-port `render_value` of Layer 3 proved
unnecessary — see §3 Layer 3).
**Problem it solves:** the documentation review of 2026-06 confirmed 108 source-contradicted
claims, dominated by *example outputs that were never re-run* (`jsonify` shown compact but
defaults to pretty; `filter` shown returning `[k,v]` pairs but returns values; `slice(...,-3)`
shown as last-N but is first-N; the headline `$APPLY`/`$EACH` recipes throw at runtime). These
are not writing mistakes — they are **untested assertions living in prose**. This plan makes every
documented example a tested assertion, validated by the **same shared corpus** that already backs
all 16 ports, plus **one shared checker** in the `tools/`-script house style.

---

## 1. Principle: a doc example *is* a corpus entry

The repo already has the exact substrate we need. `build/test/*.jsonic` compiles (via
`@voxgig/model`) to the committed `build/test/test.json`, and **every** port's runner executes it
as `subject(...args)` deep-equalled to `out` (or matched to `err`/`match`). A documentation
example — "call `F` with these inputs, get this output" — is structurally identical to a corpus
entry `{ in | args, out | err }`.

So the design reuses the build-folder model verbatim: **one shared corpus, compiled once, executed
by 16 thin per-language runners.** Doc examples become first-class corpus entries. Their *behaviour*
is then validated in all 16 languages **for free, with no new per-port code.** A single shared
Python tool (mirroring `tools/check_parity.py`) ties the prose back to those entries.

What stays irreducibly per-language is only the **surface rendering** of a snippet (call syntax and
native value notation). The plan isolates that to the smallest possible, opt-in layer.

---

## 2. Feasibility — verified per port (probe, 2026-06)

An 18-agent probe inspected every port's test harness and the corpus toolchain. Results:

| Fact | Result | Consequence |
|---|---|---|
| Harness dispatch | **hardcoded in all 16 ports** (explicit `runset(spec.<fn>.<subject>, closure)`; no port loops over groups) | A *new* top-level group (`struct.examples.*`) would need new dispatch in **all 16** ports. Appending to an **existing** subject-set needs **none**. |
| Append entry to existing subject-set | **auto-runs in all 16 ports** | Doc examples added to e.g. `getpath.basic.set` execute everywhere with zero code change. |
| Extra `id`/`doc` field on an entry | **tolerated by all 16** (entries parsed as generic JSON maps, incl. typed go/rust/java/kotlin/csharp/swift/zig/cpp; empirically confirmed for JS) | Examples can carry linkage metadata safely. Avoid only jsonic-reserved tokens (`&`, `key()`, `DEF`, `@"…"`). |
| Unknown fields through `voxgig-model` compile | **preserved** (`match`/`ctx`/`client` already round-trip into `test.json`) | `id`/`doc` survive compile unchanged. |
| `test.json` regeneration | **manual; NOT in CI or any Makefile** | **Gap to fix** — see §4. Editing `.jsonic` today requires a hand-run `cd build && npm i && npm run test-model` + commit, or the stale JSON keeps being tested. |
| Doc output convention | **every port uses inline native-comment output** (`//`, `#`, `--`, `/* */`), never a JSON fence; outputs in native notation (`.string("x")`, `Value::Str(...)`, `.{…}`); **no HTML-comment markers exist anywhere today** | A shared checker cannot textually compare native output → §3 layers separate the *machine-checked* canonical output from the *human-visible* native comment. The clean slate means we can introduce one uniform anchor convention. |

**Net:** the maximal-sharing path is to **append tagged example entries to existing corpus
subject-sets** (zero per-port code), not to create a new `examples` group (16× dispatch).

---

## 3. The mechanism — three shared layers, one optional per-port tier

### Layer 0 — Example data in the shared corpus *(shared, mandatory)*
Each documented example is authored as one corpus entry, in the shape its function's existing
subject-closure already consumes, appended to that subject's `set` in the relevant
`build/test/*.jsonic` file, and tagged:

```jsonic
// in build/test/getpath.jsonic, under basic.set:
{ id:'getpath/basic#db-host', doc:true, in:{ store:{ db:{ host:'localhost' }}, path:'db.host' }, out:'localhost' }
```

- `doc:true` lets the checker enumerate *all* documented examples (recursive walk of `test.json`,
  exactly like `check_corpus_regex.py` harvests `$LIKE`).
- `id` is the stable linkage key, format `<fn>/<subject>#<slug>`.
- Because it lands in an already-dispatched subject-set, **all 16 ports execute and assert it.**
  The corpus `out`/`err` becomes the single source of truth for that documented result.

Error examples (e.g. the broken `$APPLY` placement) use `err`, so the docs can show the *correct*
usage as a passing entry and, if desired, the *wrong* usage as an `err` entry — both tested.

### Layer 1 — The binding anchor in docs *(shared, mandatory)*
Immediately before each example block, a uniform HTML-comment anchor (none exist today, so this is
a clean, identical convention across all ports):

````markdown
<!-- example: getpath/basic#db-host -->
```ts
getpath('db.host', store)   // 'localhost'   ← human-illustrative, native notation, optional
```
<!-- => "localhost" -->
````

- `<!-- example: <id> -->` binds the block to the corpus entry.
- `<!-- => <canonical-json> -->` is the **machine-checked** expected output (canonical JSON, or
  `<!-- throws: <substr> -->` for `err` entries). The native inline comment above it stays as
  human-friendly decoration; it is not what CI compares.

### Layer 2 — The shared checker `tools/check_doc_examples.py` *(shared, mandatory)*
Stdlib-only Python 3, modelled exactly on `tools/check_parity.py` / `check_corpus_regex.py`
(`from __future__ import annotations`, `ROOT = Path(__file__).resolve().parent.parent`, contract
docstring with documented exit codes, `main() -> int` returning 0/1, `  ok ` / `  FAIL ` per-item
lines + summary). It:

1. Loads `build/test/test.json`; recursively collects every entry with `doc:true` into an
   `id → {out|err, group-is-executed?}` map (reuses the `check_corpus_regex.py` read idiom).
2. Walks `*/README.md`, `*/DOCS.md`, and top-level `README.md`/`DOCS.md` with a line-based fenced
   block + anchor state machine (no markdown library — greenfield, house style).
3. Asserts, per anchored block:
   - **binding:** `id` exists in the corpus → else `FAIL` (dangling anchor);
   - **executed:** the entry sits in a subject-set the ports actually run → else `FAIL` (so an
     example can't be "documented but not really tested");
   - **output:** the block's `<!-- => … -->` parses and **equals** the corpus entry's `out`
     (canonical compare), or `<!-- throws: … -->` is a substring of the corpus `err` → else `FAIL`
     (this is the check that would have caught jsonify/filter/slice/`$APPLY`).
4. Optionally `WARN`s on `doc:true` corpus entries that **no** doc references (under-documented).

Exit 0 if every anchored example binds to an executed, passing entry whose pinned output matches the
docs; 1 otherwise.

### Layer 3 — Output-marker generation *(shared, no per-port code — as built)*
Hand-escaping the canonical JSON in a `<!-- => … -->` marker (e.g. `jsonify`'s
`"{\n  \"a\": 1\n}"`) is itself error-prone. `tools/gen_doc_examples.py` removes that step: an
author writes only the `<!-- example: id -->` anchor before a code fence and runs `make gen-docs`;
the tool looks up the corpus entry and writes (or refreshes) the single-line canonical `=> ` marker
right after the fence. Because the marker is the shared corpus value rendered as canonical JSON, it
is **identical for every port and needs no per-language code** — the original plan's per-port
`render_value` turned out to be unnecessary. The human-visible *native* output stays as an inline
comment inside the fence (decoration; not machine-checked). `err`-entries keep their human-curated
`<!-- throws: … -->` markers untouched. CI runs `gen_doc_examples.py --check`, which regenerates
markers in memory and fails if any committed marker is missing or stale (`gofmt -l` pattern) — so
every anchor is guaranteed to carry an up-to-date, corpus-correct output.

---

## 4. Toolchain prerequisites (must land first)

1. **Make corpus regeneration first-class and CI-guarded.** Add a `make corpus` target that runs
   the `@voxgig/model` compile (`cd build && npm ci && npm run test-model`) and a CI job that
   recompiles `.jsonic` and `git diff --exit-code build/test/test.json`. Without this, example
   entries added to `.jsonic` but not recompiled would silently never run — the same staleness that
   caused the original problem. (This also fixes a latent gap: `test.json` is regenerated entirely
   by hand today.)
2. **Naming:** the Makefile `scan-docs` target is already markdownlint — use **`scan-docs-examples`**.
3. Fix the stale `.PHONY` line (it omits `scan-regex` etc.); add the new target there.

---

## 5. Wiring (mirrors the existing `parity` scan exactly)

**Makefile:**
```make
scan-docs-examples:
	@echo "======== scan: documentation examples ========"
	python3 tools/check_doc_examples.py
```
Append `scan-docs-examples` to the `scan:` aggregate and to `.PHONY`.

**`.github/workflows/security.yml`** — a `docs-examples` job cloning the `parity` job
(`actions/checkout@v4` + `actions/setup-python@v5` `python-version: '3.12'` + `run: python3
tools/check_doc_examples.py`). The corpus-regeneration guard (§4.1) is a separate small job that also needs
`actions/setup-node@v4`. (Note: `check_corpus_regex.py` currently has *no* CI job — do add this one.)

The example *behaviour* needs no new CI: it rides the existing per-port `test-*` jobs in `build.yml`.

---

## 6. Authoring workflow (what a contributor does)

1. Write the example as a corpus entry (`id`, `doc:true`, `in|args`, `out|err`) in the relevant
   `build/test/<fn>.jsonic` subject-set.
2. `make corpus` to regenerate + commit `build/test/test.json`.
3. In the doc, add the `<!-- example: <id> -->` anchor, the native snippet, and the
   `<!-- => <json> -->` (or `<!-- throws: … -->`) line. (Or, on a Layer-3 port, just the anchor +
   `<!-- /example -->` markers and run `make gen-docs`.)
4. `make test` (all ports assert the behaviour) and `make scan-docs-examples` (docs match corpus)
   both stay green.

This honours the repo's canonical-first rule: examples originate in the shared corpus, then
propagate to every port's prose.

---

## 7. Rollout (phased; canonical-first)

- **Phase A — rails.** Land §4 (corpus regeneration + CI guard), the checker skeleton, and the
  `scan-docs-examples` Make/CI wiring. Checker passes trivially (no anchors yet).
- **Phase B — TypeScript canonical.** Convert `typescript/README.md` + `typescript/DOCS.md`
  examples to anchored, corpus-backed entries; fix every wrong output against the now-tested values.
  This establishes the pattern on the reference port and corrects the highest-traffic docs.
- **Phase C — propagate.** Port the same example ids across the other 15 ports' README/DOCS,
  fixing outputs as the checker flags them. Each port's prose now shows outputs pinned to entries
  its own test suite executes.
- **Phase D — generation.** `tools/gen_doc_examples.py` (`make gen-docs`) fills/refreshes the
  canonical `=> ` markers from the corpus for every port at once; CI's `--check` form gates them.

A practical target for "every example is validated": the §6 invariant becomes a merge gate — a new
example without a passing, anchored corpus entry fails `scan-docs-examples` in CI.

---

## 8. Design decisions & rejected alternatives

- **Append to existing subject-sets, not a new `examples` group.** Maximal sharing: appending is
  zero per-port code (all 16 auto-run it); a dedicated `struct.examples.*` group would need new
  hardcoded dispatch in all 16 hand-written harnesses. The `doc:true`/`id` tags give the separation
  a group would have provided, without the 16× cost.
- **Bind prose to the corpus; do not execute markdown snippets per language.** Executing fenced
  code per port would require 16 bespoke doc-snippet harnesses — exactly the per-language tooling we
  minimise. Binding to a corpus entry the existing runner already executes achieves validation with
  one shared tool.
- **Canonical machine-checked output, native comment optional.** Because output notation is
  irreducibly per-language, the shared checker compares a *canonical* `<!-- => … -->` to the corpus;
  the native inline comment is decoration. Full native-output guarantees are the opt-in Layer 3.
- **Reuse the `tools/` Python house style**, not a new toolchain — stdlib-only, `ROOT`-anchored,
  `make scan-*` + `security.yml` job, identical to `check_parity.py`.

---

## 9. Risks & mitigations

- **Manual corpus regeneration forgotten** → §4 CI `git diff --exit-code` guard makes a stale `test.json`
  a red build.
- **Author duplicates output in `<!-- => -->` and it drifts from corpus** → CI compares it *to* the
  corpus every run, so drift is a failure, not silent rot; Layer 3 removes the duplication entirely.
- **`@voxgig/model` not installed in `build/`** (no `build/node_modules`) → the regeneration job runs
  `npm ci` in `build/` first; document it in `build/`'s notes.
- **Example entries enlarge contract sets** → harmless (they are valid behaviour assertions); the
  `doc:true` tag keeps them enumerable and lets `check_parity`/coverage tooling distinguish them.
- **A port later switches to generic dispatch** → only *improves* this design (examples in any new
  group would auto-run); nothing here depends on dispatch staying hardcoded.
