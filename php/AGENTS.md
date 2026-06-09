# AGENTS.md — PHP port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers only
what is specific to the PHP port.

> **This is a faithful port, not the canonical.** Behaviour is defined by the
> TypeScript source and pinned by [`../build/test/`](../build/test/). If this
> port disagrees with the corpus, the port is wrong — fix the port, never the
> corpus. A genuine behaviour change starts in TypeScript and propagates here.

## Layout

```
php/
├── src/Struct.php          # the whole port: Struct, ListRef, Injection classes
├── tests/StructTest.php    # corpus-driven tests (loads ../build/test/)
├── tests/Runner.php        # shared corpus runner helper
├── tests/RegexPathologicalTest.php   # regex edge-case panel
├── tests/ClientTest.php · tests/SDK.php   # SDK/integration tests
├── tests/WalkBench.php     # walk micro-benchmark (make bench)
├── phpunit.xml             # test suite config (bootstrap: vendor/autoload.php)
├── phpcs.xml.dist          # PSR-12 sniffer config
├── phpstan.neon.dist       # static-analysis config
└── composer.json
```

Everything lives in `src/Struct.php` under namespace `Voxgig\Struct`: the public
API is the set of `public static` methods on `Struct`; `ListRef` and `Injection`
are supporting classes. There is **no `StructUtility`/instance wrapper** (the TS
port has one; PHP does not). `../tools/check_parity.py` checks the static-method
names against the canonical export list.

## Commands

```bash
composer install
make test        # vendor/bin/phpunit
make lint        # vendor/bin/phpcs (PSR-12) + vendor/bin/phpstan analyse --no-progress
make audit       # composer audit
make bench       # WALK_BENCH=1 php tests/WalkBench.php
make inspect     # PHP + project version
```

`composer test` / `composer lint` run the same tools. From the repo root,
`make test-php` / `make lint-php` wrap these. There is **no build step**
(`make build` is a no-op).

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, `getprop`) — this
  intentionally breaks PSR-12 camelCase; `phpcs` is configured to allow it.
  Parity beats style.
- **`mixed`/JSON-shaped data.** The data model is dynamic JSON. Don't tighten
  parameter or return types beyond `mixed` on the public surface — ports can't
  follow non-JSON types, and the corpus is the real contract.
- **Reference-stable lists** are reproduced with the `ListRef` wrapper (mirrors
  Go). Keep `cloneWrap`/`cloneUnwrap` at the boundaries; don't "simplify" by
  passing bare arrays through the inject/merge pipeline — they'll copy and lose
  mutations.
- **Mutation contract:** `setprop` takes `&$parent` by reference; `setpath` and
  `delprop` do **not** — they return the updated value (or mutate via `ListRef`).
  Don't add `&` to match a guess; match the source.

## Gotchas

- **PHP arrays are value types.** A bare array passed into the inject/transform/
  merge machinery is copied, so mutations vanish. This is exactly what `ListRef`
  exists to fix — suspect it first when a deep mutation doesn't stick.
- **`null` is not "absent".** Internally, absence is the `Struct::undef()`
  sentinel object (the public `Struct::UNDEF` string is legacy). This port is
  **Group A** (see [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)): readers treat stored
  null as no-value; value-processors preserve it. Internal Group B reads use
  `_getprop`, not the null-normalising public `getprop`. Re-read the Group A/B
  rule before touching any read/merge/clone path.
- **`validate` throws `\Exception`** (not a subclass) when no `errs` collector is
  supplied; `re_compile` throws `\InvalidArgumentException` on a bad pattern.
- **The `$path` in `walk` callbacks is reused** from a shared per-depth pool —
  clone it (`array_values($path)`) if you need to keep it.
- **Editing here is a port change, not a canonical one.** If multiple ports fail
  the same corpus case, suspect the canonical TS, not this port.
- **Regex is PCRE (backtracking).** Stay inside the RE2 subset; the documented
  pathological-input differences in
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md) are expected — do not
  "fix" them by diverging.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md) · Concepts:
  [`../DOCS.md`](../DOCS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py) · Matrix:
  [`../REPORT.md`](../design/REPORT.md)
```
