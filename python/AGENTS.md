# AGENTS.md — Python port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Python port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript source and pinned by the shared corpus. If Python disagrees
> with the corpus, Python is wrong — fix the port to match, never edit the
> corpus to make Python pass.

## Layout

```
python/
├── voxgig_struct/
│   ├── voxgig_struct.py   # the whole port — implementation + public API
│   └── __init__.py        # re-exports the public surface (parity reads this)
├── tests/
│   ├── runner.py          # shared-corpus runner (mirrors the TS reference)
│   └── test_voxgig_struct.py   # corpus-driven tests
├── Makefile
└── pyproject.toml         # ruff + mypy config
```

The public API is the re-export list in `voxgig_struct/__init__.py`.
`../tools/check_parity.py` checks that surface against the canonical
TypeScript `export` block, so adding/removing a public name there affects
parity.

## Commands

```bash
pip install -e .            # or add the source dir to sys.path
make test                   # python3 -m unittest discover -s tests
make lint                   # ruff check + ruff format --check + mypy
make format-check           # ruff format --check only
make typecheck              # mypy only
```

`make test-py` / `make lint-py` from the repo root wrap the same commands.
Dev tooling floors: `ruff>=0.9`, `mypy>=1.14`. No build step.

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, `getprop`,
  …) — deliberately **not** the PEP8 `get_path`. Parity beats style; don't
  "fix" the names.
- **`UNDEF` sentinel.** Python has only `None`, so the port uses an internal
  `UNDEF` (= `None`) to mean "absent". Optional args default to `UNDEF`.
  Both JSON `null` and "absent" surface as `None` at the API.
- **`walk` uses keyword args** (`before=`, `after=`, `maxdepth=`) where
  canonical TS uses positional optionals. Keep that.
- **Python-specific extras** (`replace`, `joinurl`) exist beyond the
  canonical set — they are convenience helpers, not part of the parity
  surface. Don't add more without a reason.
- **Ruff config is deliberate** (see `pyproject.toml`): `E501` is off
  (formatter owns line length), `B008` is off (default-arg calls are used
  on purpose), and `F401`/`F403`/`F405` are relaxed for the re-export
  `__init__.py` and the `import *` test runners. Don't tighten these.

## Gotchas

- **`None` is not "absent".** This is the single most common port bug. Re-read
  the Group A/B rule ([`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md)) before touching
  any read/merge/clone path. The corpus uses `"__NULL__"` to mark a real
  null distinct from absent.
- **Editing here never changes canonical behaviour.** If a behaviour looks
  wrong, confirm against the corpus and the canonical TS first. A canonical
  change starts in TypeScript + corpus, then propagates to this port.
- **Stay in the RE2 subset.** The port wraps stdlib `re`, which allows
  backreferences and lookaround — those won't port to the RE2/NFA ports.
  Cross-engine edge cases are documented, not "fixed", in
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md).
- **Don't reorder map keys** to satisfy a diff — `dict` preserves insertion
  order and key order is observable through `keysof`, `items`, and
  `jsonify`.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
