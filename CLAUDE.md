# CLAUDE.md

This repository's agent guidance lives in [`AGENTS.md`](./AGENTS.md). Read
it first — it is the single source of truth for how to work here.

Quick reminders (the full rationale is in `AGENTS.md`):

- **TypeScript is canonical** (`typescript/src/StructUtility.ts`); every
  other language is a port of it.
- **The `build/test/*.jsonic` corpus is the contract** — it runs against
  every port. A port that disagrees with the corpus is the thing that's
  wrong, not the corpus.
- **Change canonical first, then propagate** to every port and re-test.
- **Keep `python3 tools/check_parity.py` green** and **add no runtime
  dependencies.**
- Build/test a port with `make test-<lang>` (or `cd <lang> && make test`).

Per-port agent notes are in each `<lang>/AGENTS.md`. User documentation is
in [`README.md`](./README.md) and [`DOCS.md`](./DOCS.md).
</content>
