#!/usr/bin/env python3
"""Validate that documentation examples are backed by the shared test corpus.

voxgig/struct documents the same API across 16 language ports. Inline example
OUTPUTS used to be hand-written and drifted out of sync with the code (the
2026-06 doc review confirmed jsonify shown compact when it defaults to pretty,
filter shown returning pairs when it returns values, slice negative-start shown
as last-N when it is first-N, etc.). This checker closes that gap by binding
every documented example to a *tested* corpus entry.

How it works (the design lives in design/DOC_EXAMPLES.md):

  * A documentation example is authored as a normal entry in build/test/*.jsonic,
    tagged `doc: true` and given a stable `id: '<fn>/<subject>#<slug>'`. Because
    it lands in an existing function subject-set, ALL 16 ports already execute it
    and assert its `out`/`err` — so its behaviour is tested everywhere for free.

  * In the Markdown, the example block is preceded by an anchor comment that
    binds the prose to that corpus entry, and (optionally) declares the expected
    output canonically so this checker can compare it to the corpus:

        <!-- example: minor/jsonify#map -->
        ```ts
        jsonify({ a: 1 })
        ```
        <!-- => "{\n  \"a\": 1\n}" -->

    Use `<!-- throws: <substring> -->` instead of `<!-- => <json> -->` for an
    example whose corpus entry expects an error (`err`).

This script (stdlib only, like tools/check_parity.py and check_corpus_regex.py):
  1. loads build/test/test.json and collects every `doc: true` entry by `id`;
  2. scans every *.md for `<!-- example: ID -->` anchors and their optional
     `<!-- => ... -->` / `<!-- throws: ... -->` output markers;
  3. FAILs if an anchor names an id not in the corpus, or a declared output does
     not equal the corpus entry's tested `out` (or is not a substring of `err`);
  4. WARNs (does not fail) on `doc: true` corpus entries that no doc references.

Exit status: 0 if every anchored example binds to a real corpus entry and every
declared output matches the corpus; 1 otherwise.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_JSON = ROOT / "build" / "test" / "test.json"

# Anchor / marker grammar. Markers are HTML comments so they never render.
_RE_EXAMPLE = re.compile(r"<!--\s*example:\s*(?P<id>\S+)\s*-->")
_RE_OUT = re.compile(r"<!--\s*=>\s*(?P<payload>.*?)\s*-->", re.DOTALL)
_RE_THROWS = re.compile(r"<!--\s*throws:\s*(?P<payload>.*?)\s*-->", re.DOTALL)

# A corpus entry's `out` may legitimately be absent (function returns nothing).
_MISSING = object()


def collect_doc_entries(node, out):
    """Recursively gather every dict tagged `doc` truthy into out[id]."""
    if isinstance(node, dict):
        if node.get("doc"):
            eid = node.get("id")
            out.append((eid, node))
        for v in node.values():
            collect_doc_entries(v, out)
    elif isinstance(node, list):
        for v in node:
            collect_doc_entries(v, out)


def load_corpus():
    if not TEST_JSON.exists():
        print(
            f"FAIL: corpus not found at {TEST_JSON.relative_to(ROOT)} "
            "(run `make corpus`)",
            file=sys.stderr,
        )
        return None
    data = json.loads(TEST_JSON.read_text())
    found: list = []
    collect_doc_entries(data, found)
    return found


def markdown_files():
    skip = {"node_modules", ".git", "dist", "dist-test", "target", "build/node_modules"}
    for p in sorted(ROOT.rglob("*.md")):
        rel = p.relative_to(ROOT)
        if any(part in skip for part in rel.parts):
            continue
        yield p


def strip_fences(text):
    """Blank out fenced code regions so anchors *inside* code samples (e.g. the
    convention shown in design/DOC_EXAMPLES.md) are not treated as live anchors.

    Live anchors and their `=>`/`throws` markers live in prose; only the code
    snippet itself sits inside a fence. Handles nested fences (a 4-backtick block
    wrapping 3-backtick blocks) by requiring the closing fence to be at least as
    long as the opener (CommonMark rule).
    """
    out_lines = []
    fence = 0  # length of the currently-open fence, 0 if none
    for line in text.split("\n"):
        stripped = line.lstrip()
        ticks = len(stripped) - len(stripped.lstrip("`"))
        if fence == 0:
            if ticks >= 3:
                fence = ticks
                out_lines.append("")
                continue
            # Strip inline `code` spans: an anchor shown as inline code (e.g. when
            # documenting the convention itself) is illustration, not live.
            out_lines.append(re.sub(r"`[^`\n]*`", "", line))
        else:
            # Inside a fence: a line of only backticks, >= opener length, closes.
            if ticks >= fence and stripped.strip("`") == "":
                fence = 0
            out_lines.append("")
    return "\n".join(out_lines)


def find_anchors(text):
    """Yield (id, kind, payload) for each example anchor in a markdown file.

    Each `example:` anchor is associated with the first `=>`/`throws` marker that
    follows it and precedes the next `example:` anchor. kind is 'out', 'throws',
    or None (binding only, no declared output).
    """
    text = strip_fences(text)
    examples = [(m.start(), m.group("id")) for m in _RE_EXAMPLE.finditer(text)]
    outs = [(m.start(), "out", m.group("payload")) for m in _RE_OUT.finditer(text)]
    throws = [(m.start(), "throws", m.group("payload")) for m in _RE_THROWS.finditer(text)]
    markers = sorted(outs + throws)

    for i, (pos, eid) in enumerate(examples):
        nxt = examples[i + 1][0] if i + 1 < len(examples) else len(text) + 1
        kind = payload = None
        for mpos, mkind, mpayload in markers:
            if pos < mpos < nxt:
                kind, payload = mkind, mpayload
                break
        yield eid, kind, payload


def canon(v):
    """Canonical JSON for stable comparison (sorted keys, compact)."""
    return json.dumps(v, sort_keys=True, ensure_ascii=False)


def main() -> int:
    entries = load_corpus()
    if entries is None:
        return 1

    by_id: dict[str, dict] = {}
    dup = False
    for eid, node in entries:
        if eid is None:
            print(f"  FAIL corpus entry tagged doc:true has no id: {canon(node)[:120]}")
            dup = True
            continue
        if eid in by_id:
            print(f"  FAIL duplicate corpus example id: {eid}")
            dup = True
        by_id[eid] = node

    print(f"corpus doc examples: {len(by_id)} unique")

    failures = 0
    anchors = 0
    checked = 0
    referenced: set[str] = set()

    for path in markdown_files():
        text = path.read_text()
        if "<!-- example:" not in text and "<!--example:" not in text:
            continue
        rel = path.relative_to(ROOT)
        for eid, kind, payload in find_anchors(text):
            anchors += 1
            referenced.add(eid)
            entry = by_id.get(eid)
            if entry is None:
                print(f"  FAIL {rel}: anchor id not in corpus: {eid}")
                failures += 1
                continue

            has_err = "err" in entry
            corpus_out = entry.get("out", _MISSING)

            if kind == "out":
                if has_err:
                    print(
                        f"  FAIL {rel}: {eid} declares `=>` but corpus entry "
                        "expects an error (use `throws:`)"
                    )
                    failures += 1
                    continue
                try:
                    declared = json.loads(payload)
                except json.JSONDecodeError as e:
                    print(f"  FAIL {rel}: {eid}: `=>` payload is not valid JSON: {e}")
                    failures += 1
                    continue
                actual = None if corpus_out is _MISSING else corpus_out
                if canon(declared) != canon(actual):
                    print(
                        f"  FAIL {rel}: {eid}: documented output != corpus.\n"
                        f"         doc:    {canon(declared)}\n"
                        f"         corpus: {canon(actual)}"
                    )
                    failures += 1
                else:
                    checked += 1
                    print(f"  ok   {rel}: {eid}")

            elif kind == "throws":
                if not has_err:
                    print(
                        f"  FAIL {rel}: {eid} declares `throws:` but corpus entry "
                        "does not expect an error"
                    )
                    failures += 1
                    continue
                err = entry.get("err")
                # `err: true` means "some error"; any declared substring is fine.
                if err is True or err is None:
                    checked += 1
                    print(f"  ok   {rel}: {eid} (throws)")
                elif payload.lower() in str(err).lower():
                    checked += 1
                    print(f"  ok   {rel}: {eid} (throws)")
                else:
                    print(
                        f"  FAIL {rel}: {eid}: documented error not found in corpus err.\n"
                        f"         doc:    {payload!r}\n"
                        f"         corpus: {err!r}"
                    )
                    failures += 1
            else:
                # Binding only: the example is tied to a tested entry, but its
                # output is not pinned. Allowed; report so it is visible.
                print(f"  ok   {rel}: {eid} (bound, output not declared)")

    orphans = sorted(set(by_id) - referenced)
    for eid in orphans:
        print(f"  note corpus example never referenced by any doc: {eid}")

    print()
    print(
        f"{anchors} doc anchors, {checked} outputs verified against corpus, "
        f"{failures} failures, {len(orphans)} unreferenced corpus examples."
    )
    if dup or failures:
        print(
            "Documentation examples disagree with the tested corpus. "
            "Fix the doc output or the corpus entry; see design/DOC_EXAMPLES.md."
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
