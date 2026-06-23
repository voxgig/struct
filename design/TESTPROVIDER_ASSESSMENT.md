# Test Provider — suitability as a general library, and what's missing

**Status:** assessment / proposal (2026-06). Evaluates the `test/proto/`
prototypes (see [`../test/proto/PROVIDER.md`](../test/proto/PROVIDER.md),
[`RUNNING.md`](../test/proto/RUNNING.md),
[`AGENTS.md`](../test/proto/AGENTS.md)) against the bar of being a *general
library for test-spec provision* — something a port's test suite, or a coding
agent, depends on to consume the shared corpus. Nothing here is implemented.

> **Verdict.** As a prototype proving the shape: suitable — the model and the
> 22-language parity are right. As a drop-in general library today: not yet.
> Gaps §3.1–§3.4 are correctness/usability blockers, not polish. The cleanest
> path is to push the *invoke-mapping* and *null-mode* into the test-spec model
> (the aontu schema strand, [`TESTSPEC_MODEL.md`](./TESTSPEC_MODEL.md)), which
> turns the provider from "data + an external cheat-sheet" into a genuinely
> self-contained library; only then is packaging worth the spend.


## 1. What the prototype is

A data-access library, ported to all 22 languages and verified to emit the same
normalized view of `build/test/test.json` — **1325 entries** (value 1181,
absent 84, error 59, match 1). It loads the corpus, classifies
`struct.<fn>.<group>.set[]` into normalized `Entry` records (tagged `Input`,
tagged `Expect`, provenance), and ships pure comparison helpers
(`equal`/`equalStrict`/`structMatch`/`errorMatches`/`matchval`). It is **not** a
runner: it never calls the function under test and never asserts.


## 2. What is already library-grade

* **Uniform model across 22 languages, proven identical.** Cross-language
  parity is the expensive part and it is done and run-verified.
* **Dependency-free**, with an order-preserving JSON reader (stdlib or
  hand-rolled) in every port.
* **The fiddly logic is centralized.** `structMatch` (regex / `__UNDEF__` /
  `__EXISTS__` / partial deep match) and the `equal` vs `equalStrict` null
  semantics are written once per port instead of re-derived in each test file.
* **Good authoring ergonomics.** Tagged input/expect + provenance
  (`function/group/index/id`) make per-case tests and failure messages clean.


## 3. Gaps that block general use (prioritized)

### 3.1 The invoke-mapping lives *outside* the library  ⟵ #1
The provider hands you `entry.input.in = {store, path}` but not that it maps to
`getpath(store, path)`. That knowledge is prose in `AGENTS.md` §3, not data.
Every consumer must hand-maintain that table — exactly the drift this repo
exists to prevent. **Highest-value gap.** (Proposal: §4.1.)

### 3.2 The `null:false` mode is not in the corpus
Whether a case is compared with `equal` or `equalStrict` is set by the test
author per `runset` call — i.e. **per (function, group)** (e.g. `validate.basic`
is strict, `validate.child` is not; `transform.format` is strict, sibling
groups are not; all of `minor.clone`, all `sentinels`, `walk.depth`, …). The
provider cannot currently tell a caller the right comparison mode. A silent
correctness hazard. (Proposal: §4.1.)

### 3.3 The `args`/`ctx` input paths are effectively untested
All 1325 iterated entries are `kind:in`. The only `args`/`ctx`/`DEF.client`
data lives under `primary.check`, which `functions()` deliberately skips. So
those provider branches are written but never exercised, and the entire
client-integration spec is unreachable through the provider. (Proposal: §4.2.)

### 3.4 No clone-on-read
`raw` and `input.in` are returned by reference. The real runner *clones*
`entry.in` before each call precisely so a subject can't mutate shared
corpus/fixtures; a test that mutates input here would corrupt later cases.
(Proposal: §4.3.)

### 3.5 The helpers are a reimplementation, not the port's own semantics
The runner matches using each port's *own* `struct.walk`/`getpath`/`stringify`;
the provider ships generic equivalents. Self-contained, but they can diverge
from a port's real semantics on edge cases (array indexing, special keys,
stringify formatting). Fine as a data utility, riskier as the assertion
authority — see the ownership decision in §4.6.

### 3.6 Corpus discovery is hardcoded
The default path assumes the in-repo `build/test/test.json` layout. A library
shipped inside a port's package will not know where the consumer's corpus is
(the runner already hints at a `.sdk/test/test.json` alternative for sdkgen
projects). Needs explicit/configurable resolution.

### 3.7 Thin API, and the provider itself is untested
No `byId()`, no filtering (by `doc`, by `client`), no access to the `primary`
namespace or to fixtures except via `raw()`. The provider's own logic is only
*smoke*-tested (counts) — the helpers have no conformance suite, and there is no
cross-port parity check (the analogue of `tools/check_parity.py`) keeping the 22
APIs and behaviours in sync.

### 3.8 Packaging
Loose single files under `test/proto/`, not consumable packages, with per-port
run quirks (swift `main.swift`, clojure ns/path depth, scala classpath) and
cosmetic inconsistencies (sorted vs insertion-order kind printing in smokes).


## 4. What else is needed

### 4.1 Encode invoke-mapping + null-mode in the model  (resolves §3.1, §3.2)
This is where the provider converges with the aontu schema work
([`TESTSPEC_MODEL.md`](./TESTSPEC_MODEL.md)). Add **emitted** descriptors the
provider can read. Sketch:

```jsonic
# per function: how an entry's input maps onto the call
struct: getpath: api: { args: ['in.store', 'in.path'] }
struct: merge:   api: { args: ['in'] }            # in is the whole arg
struct: select:  api: { args: ['in.obj', 'in.query'] }

# per group: comparison mode (default true = equal; false = equalStrict)
struct: validate: basic: nullmode: false
struct: transform: format: nullmode: false
```

* `args` is a list of **dotted path-expressions** resolved against the entry
  (`in.store`, `in`, …). The provider can then build the argument vector itself,
  and `AGENTS.md`'s mapping table disappears.
* **Honest limit:** not every call is pure-data-dispatchable. `filter` takes a
  predicate selected by `in.check`, `walk` takes a callback, `transform.modify`
  takes a modifier, `getpath.handler`/`inject`/`validate.special` take an
  injection/current. These need a small set of **named resolvers** the consumer
  registers once (e.g. `resolvers = { check: …, walkcb: … }`) and the model
  references (`args: ['in.val', {resolver: 'check', key: 'in.check'}]`). So the
  end state is *data-driven dispatch for the ~80% case + a handful of named
  hooks*, not magic.
* `nullmode` is **per-group** (§3.2). Default emitted from the
  `struct.&` template so only the exceptions are written.

These fields are additive — existing port runners ignore unknown keys, so
`test.json` consumers are unaffected (verify with the zero-diff guard from
`TESTSPEC_MODEL.md` §5, treating the new keys as intended additions).

### 4.2 Model `primary` / `DEF` / `client` / fixtures as first-class  (§3.3)
Expose `primary.check` through the provider (a `clients()` / `entries('check')`
path), surface a group's `DEF` and fixtures via typed accessors rather than
`raw()`, and add `args`/`ctx` corpus coverage so those branches are real. Ties
to the `fixtures`/`DEF` slots proposed in `TESTSPEC_MODEL.md` §4.4.

### 4.3 Clone-on-read or a documented immutability contract  (§3.4)
Either deep-clone `input`/`raw` on access (matches the runner), or document that
returned values are shared-immutable and provide an explicit `clone(entry)`.
Prefer clone-on-read for `input` (the thing tests touch most).

### 4.4 A provider-level conformance corpus + cross-port parity check  (§3.7)
A small fixed set of `(helper, args, expected)` cases — especially for
`structMatch`/`matchval`/`equalStrict` edge cases — that every port runs, plus a
`tools/check_provider_parity.py` that asserts all 22 expose the same API and
pass that set. Without it, 22 hand-written ports *will* drift.

### 4.5 Configurable corpus discovery  (§3.6)
`load(path)` explicit, plus a documented search order (env var → walk up for
`build/test/test.json` or `.sdk/test/test.json` → error). Fixes the
clojure/depth fragility noted in `RUNNING.md` along the way.

### 4.6 Decide who owns the assertion logic  (§3.5)
Pick one and commit:
* **(a) Provider = data only.** Drop the helpers; the port's own `struct` utils
  do matching. Maximally faithful, but every test reimplements comparison.
* **(b) Provider = the authority.** Keep the helpers but give them the
  conformance suite from §4.4 so they are provably correct, and document that
  they intentionally define corpus-match semantics independent of any port.

Recommendation: **(b)** — centralizing comparison is most of the value; just
make it earn the authority with tests.

### 4.7 Packaging  (§3.8)
Per-language module/package layout, consistent smoke output, and a decision on
*home*: stay in `test/proto/` as reference, or vendor each port's provider into
that port's package so its test suite imports it directly.


## 5. Suggested order

1. **§4.1** (invoke-mapping + null-mode in the model) — unblocks the rest and is
   the throughline with the schema work. Do it in the corpus model first, then
   teach the canonical TS provider to read it, then propagate.
2. **§4.3** clone-on-read and **§4.5** corpus discovery — small, pure
   correctness/robustness wins.
3. **§4.4** conformance corpus + parity check — lock the 22 together before
   adding surface area.
4. **§4.2** primary/DEF/fixtures + args/ctx coverage.
5. **§4.6 / §4.7** ownership decision and packaging — last, once the contract is
   stable.

Until §4.1–§4.4 land, treat the prototypes as a **proven core to build on**, not
a finished library: excellent for an agent writing per-case tests *with* the
`AGENTS.md` mapping table at hand, not yet a self-contained dependency.
