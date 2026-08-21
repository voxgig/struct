# AGENTS.md — Perl port

Port-specific notes for AI agents. **Read the repo-wide
[`../AGENTS.md`](../AGENTS.md) first** — it holds the rules that matter most
(canonical-first, corpus-is-contract, parity, zero-deps). This file covers
only what is specific to the Perl port.

> **This is a port, not the canonical.** Behaviour is defined by the
> TypeScript source and pinned by [`../build/test/`](../build/test/). If
> this port disagrees with the corpus, fix the port — never the corpus.

## Layout

```
perl/
├── lib/Voxgig/Struct.pm   # the whole port: implementation + OrderedHash + JSON parser
├── t/OmniBridge.pm        # resolves the voxgig/omni checkout, and converts both value models
├── t/struct.t             # the shared corpus, run on the shared runner
├── t/client.t             # the client path (DEF.client, client options, contextify)
├── t/regex_pathological.t # regex edge-case panel
├── t/00-load.t            # load + sanity check
├── Makefile               # test / lint / inspect / build (no-op) targets
└── README.md
```

The whole port lives in one file. `Voxgig::Struct::OrderedHash` (the tie
class) and `Voxgig::Struct::JsonParser` are sub-packages at the top /
middle of that file.

## Commands

```bash
make test            # prove -Ilib t/
make lint            # perlcritic --gentle lib t
make inspect         # print Perl + module version
make build           # no-op (pure-Perl module; prints a notice)
```

`perlcritic` soft-skips locally if it is not on `PATH`; it is **required in
CI** (the Makefile fails when `CI=true` and it is missing). There is no
build step. `make test-perl` / `make lint-perl` from the repo root wrap the
same commands.

## Conventions specific to this port

- **Casing:** lowercase canonical names (`getpath`, `setpath`, …), matching
  the TypeScript spelling exactly.
- **Functional interface, no `Exporter`.** Nothing is exported; everything
  is called fully qualified as `Voxgig::Struct::name(...)`. Don't add an
  `@EXPORT`/`@EXPORT_OK` list — call sites and tests rely on the qualified
  form.
- **The corpus runner is voxgig/omni**, a local checkout found via
  `$OMNI_HOME` (see `t/OmniBridge.pm`); it is not on CPAN, and
  `Makefile.PL` gains nothing for it. `t/OmniBridge.pm` pushes omni's
  `lib` onto `@INC` at run time, so nothing built or installed from `lib/`
  can acquire it.
- **The bridge converts, in both directions.** omni and this port model
  JSON with different sentinels for absent (`Voxgig::Omni::Absent` vs
  `$NONE`), null (`undef` vs `$JNULL`) and booleans (`JSON::PP::Boolean`
  vs `Voxgig::Struct::Bool`). `tostruct` rewrites omni's containers IN
  PLACE so `match.args` can see an in-place `setpath`/`merge`; `toomni`
  copies. Read the header of `t/OmniBridge.pm` before touching either.
- **Zero runtime deps.** Only core `Scalar::Util`, `List::Util`, `B`. Do
  not add a CPAN dependency — in particular, don't swap the in-tree
  `OrderedHash` for `Tie::IxHash`, or `parse_json` for `JSON::*` (they
  randomise key order and would break the corpus).
- **`join` is shadowed** by `Voxgig::Struct::join`; internal code uses
  `CORE::join`. Keep that distinction when editing.

## Gotchas

- **Use ordered maps everywhere.** A bare `{ ... }` is an unordered hash;
  the library builds maps via `_mkmap` / `jm` / `parse_json` so they are
  tied to `OrderedHash`. Key order is observable (`jsonify` renders it) —
  never introduce a plain hash where order matters. An untied hash is not
  wrong, just orderless: `_map_keys` sorts it, so `jsonify` is at least
  deterministic. (`keysof` and `items` sort unconditionally, as canonical
  does.)
- **`_map_keys` returns a LIST.** `scalar _map_keys($m)` is its last key,
  not its length — use `_map_count`.
- **`undef` vs `$JNULL` vs `$NONE`.** Three distinct "empty" values:
  `undef`/`$NONE` are *absent* (Group A reads return the `alt`), `$JNULL`
  is the JSON null scalar (Group B preserves it literally). Re-read the
  Group A/B rule before touching any read/merge/clone path.
- **String-vs-number SVs.** `parse_json` forces numbers to carry
  `SVf_IOK`/`SVf_NOK`; `_is_number_sv`/`_is_string_sv` probe those flags.
  Avoid `0 + $x` on a value you'll later `typify` (it flips the IOK flag —
  see the deliberate workaround in `select_CMP`).
- **Editing here is a port change, not a canonical one.** If multiple ports
  fail the same way, suspect the canonical TS / corpus, not this port.
  After any behaviour change: confirm against the corpus, run `make test`,
  then `python3 ../tools/check_parity.py`.

## See also

- Port guide: [`DOCS.md`](./DOCS.md) · Reference + quick start:
  [`README.md`](./README.md)
- Repo rules & workflows: [`../AGENTS.md`](../AGENTS.md)
- The contract: [`../build/test/`](../build/test/) · Parity:
  [`../tools/check_parity.py`](../tools/check_parity.py)
- Group A/B: [`../UNDEF_SPEC.md`](../design/UNDEF_SPEC.md) · Regex:
  [`../REGEX_PATHOLOGICAL.md`](../design/REGEX_PATHOLOGICAL.md)
