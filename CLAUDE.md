# CLAUDE.md

This repository's agent guidance lives in [`AGENTS.md`](./AGENTS.md). Read
it first — it is the single source of truth for how to work here.

Quick reminders (the full rationale is in `AGENTS.md`):

- **TypeScript is canonical** (`typescript/src/StructUtility.ts`); every
  other language is a port of it.
- **The `build/test/*.aon` corpus is the contract** — it runs against
  every port. A port that disagrees with the corpus is the thing that's
  wrong, not the corpus.
- **Change canonical first, then propagate** to every port and re-test.
- **Keep `python3 tools/check_parity.py` green** and **add no runtime
  dependencies.**
- Build/test a port with `make test-<lang>` (or `cd <lang> && make test`).

- **Prose follows [`STYLE-GUIDE.md`](./STYLE-GUIDE.md)** — normative for
  the root and per-port `README.md` / `DOCS.md`: the voice, the banned
  phrases, the spaced em dash, and the rule that documentation never cites
  a working document (this file included). Two gates enforce it, `vale`
  and `python3 tools/check_prose.py`; `make scan-prose` runs both.

Per-port agent notes are in each `<lang>/AGENTS.md`. User documentation is
in [`README.md`](./README.md) and [`DOCS.md`](./DOCS.md).
</content>
