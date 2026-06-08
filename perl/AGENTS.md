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
├── t/struct.t             # corpus runner (loads ../build/test/test.json)
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
- **Zero runtime deps.** Only core `Scalar::Util`, `List::Util`, `B`. Do
  not add a CPAN dependency — in particular, don't swap the in-tree
  `OrderedHash` for `Tie::IxHash`, or `parse_json` for `JSON::*` (they
  randomise key order and would break the corpus).
- **`join` is shadowed** by `Voxgig::Struct::join`; internal code uses
  `CORE::join`. Keep that distinction when editing.

## Gotchas

- **Use ordered maps everywhere.** A bare `{ ... }` is an unordered hash;
  the library builds maps via `_mkmap` / `jm` / `parse_json` so they are
  tied to `OrderedHash`. Key order is observable (`keysof`, `items`,
  `jsonify`) — never introduce a plain hash where order matters.
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
- Group A/B: [`../UNDEF_SPEC.md`](../UNDEF_SPEC.md) · Regex:
  [`../REGEX_PATHOLOGICAL.md`](../REGEX_PATHOLOGICAL.md)
