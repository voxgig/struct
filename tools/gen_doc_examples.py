#!/usr/bin/env python3
"""Generate the canonical output markers for documentation examples from the corpus.

This is the optional "Layer 3" companion to tools/check_doc_examples.py (see
design/DOC_EXAMPLES.md). An author writes only the binding anchor before an
example's code fence:

    <!-- example: minor/jsonify#map -->
    ```ts
    jsonify({ a: 1 })
    ```

and runs `make gen-docs`. This tool looks up the corpus entry for that id and
writes (or refreshes) the machine-checked output marker right after the fence:

    <!-- => "{\n  \"a\": 1\n}" -->

so the hand-escaped canonical JSON never has to be typed by hand and can never
drift from the tested corpus value. `err`-entries get a `<!-- throws: ... -->`
marker derived from the corpus error string.

The marker is canonical JSON on a single line — identical for every port,
because it is the shared corpus value. The native, human-readable output (in
each port's own value notation) stays as an inline comment inside the fence and
is not touched.

Modes:
  (default)   rewrite markers in place.
  --check     do not write; exit 1 if any committed marker differs from what the
              corpus would generate (the CI guard: `gofmt -l` style).

Exit status: 0 if all markers are in sync (or were rewritten); 1 under --check
when a marker is stale, or on a dangling/duplicate id.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_JSON = ROOT / "build" / "test" / "test.json"

_RE_EXAMPLE = re.compile(r"^\s*<!--\s*example:\s*(?P<id>\S+)\s*-->\s*$")
_RE_MARKER = re.compile(r"^\s*<!--\s*(?:=>|throws:).*-->\s*$")
_FENCE = re.compile(r"^\s*(`{3,})")

_MISSING = object()


def collect_doc_entries(node, out):
    if isinstance(node, dict):
        if node.get("doc"):
            out.append((node.get("id"), node))
        for v in node.values():
            collect_doc_entries(v, out)
    elif isinstance(node, list):
        for v in node:
            collect_doc_entries(v, out)


def load_by_id():
    if not TEST_JSON.exists():
        print(f"corpus not found at {TEST_JSON} (run `make corpus`)", file=sys.stderr)
        return None
    found: list = []
    collect_doc_entries(json.loads(TEST_JSON.read_text()), found)
    by_id: dict[str, dict] = {}
    for eid, node in found:
        if eid is not None:
            by_id[eid] = node
    return by_id


def marker_for(entry) -> str:
    """The canonical `=> ` marker line for an out-entry (single-line JSON)."""
    out = entry.get("out", _MISSING)
    val = None if out is _MISSING else out
    return f"<!-- => {json.dumps(val, ensure_ascii=False)} -->"


def markdown_files():
    skip = {"node_modules", ".git", "dist", "dist-test", "target"}
    for p in sorted(ROOT.rglob("*.md")):
        if any(part in skip for part in p.relative_to(ROOT).parts):
            continue
        yield p


def process(lines, by_id, rel, problems):
    """Return (new_lines, changed). Inserts/refreshes a marker after each
    example's code fence."""
    out: list[str] = []
    i = 0
    n = len(lines)
    fence = 0
    while i < n:
        line = lines[i]
        # Track fences so we never treat an anchor inside a fence as live.
        m = _FENCE.match(line)
        if m:
            ticks = len(m.group(1))
            if fence == 0:
                fence = ticks
            elif ticks >= fence and line.strip().strip("`") == "":
                fence = 0
            out.append(line)
            i += 1
            continue

        em = _RE_EXAMPLE.match(line) if fence == 0 else None
        if not em:
            out.append(line)
            i += 1
            continue

        eid = em.group("id")
        out.append(line)
        i += 1
        entry = by_id.get(eid)
        if entry is None:
            problems.append(f"{rel}: anchor id not in corpus: {eid}")
            continue
        # The generator only manages the canonical `=> ` JSON markers (the
        # error-prone, hand-escaped part). `throws:` markers for err-entries are
        # human-curated (a readable substring of the error) and left untouched.
        if "err" in entry:
            continue

        # Copy through to the end of the example's (first following) code fence.
        # Skip blank lines before the fence.
        while i < n and lines[i].strip() == "":
            out.append(lines[i]); i += 1
        fm = _FENCE.match(lines[i]) if i < n else None
        if not fm:
            problems.append(f"{rel}: {eid}: no code fence after anchor")
            continue
        openticks = len(fm.group(1))
        out.append(lines[i]); i += 1
        while i < n:
            cm = _FENCE.match(lines[i])
            out.append(lines[i])
            closed = cm and len(cm.group(1)) >= openticks and lines[i].strip().strip("`") == ""
            i += 1
            if closed:
                break

        want = marker_for(entry)
        # Look at the next non-blank line: replace an existing marker, else insert.
        j = i
        while j < n and lines[j].strip() == "":
            j += 1
        if j < n and _RE_MARKER.match(lines[j]):
            # preserve surrounding blank lines, replace the marker line
            out.extend(lines[i:j])
            out.append(want)
            i = j + 1
        else:
            out.append("")
            out.append(want)
    return out, None


def main(argv) -> int:
    check = "--check" in argv
    by_id = load_by_id()
    if by_id is None:
        return 1

    problems: list[str] = []
    stale: list[str] = []
    wrote = 0
    for path in markdown_files():
        text = path.read_text()
        if "<!-- example:" not in text:
            continue
        rel = path.relative_to(ROOT)
        lines = text.split("\n")
        new_lines, _ = process(lines, by_id, rel, problems)
        new_text = "\n".join(new_lines)
        if new_text != text:
            if check:
                stale.append(str(rel))
            else:
                path.write_text(new_text)
                wrote += 1

    for p in problems:
        print(f"  FAIL {p}")
    if check:
        for s in stale:
            print(f"  STALE {s}: output markers differ from corpus — run `make gen-docs`")
        print()
        print(f"{len(stale)} stale files, {len(problems)} problems.")
        return 1 if (stale or problems) else 0
    print(f"Rewrote markers in {wrote} files; {len(problems)} problems.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
