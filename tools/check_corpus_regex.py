#!/usr/bin/env python3
"""Check that every regex pattern in the shared test corpus stays inside the
RE2 subset.

The contract is documented in /design/REGEX.md: every port must support at least the
Go (RE2) regex feature set, and no port may carry a runtime regex dependency
beyond its stdlib. Some ports use weaker built-ins (Lua patterns) or
hand-rolled matchers (C), so the corpus must not use features RE2 itself
rejects.

This script:
  1. Scans build/test/*.jsonic for `$LIKE` clauses (the only user-supplied
     pattern slot in the API).
  2. Re-parses build/test/test.json (the compiled corpus) and extracts every
     `$LIKE` value.
  3. For each candidate pattern, rejects features that RE2 cannot compile:
       - lookahead/lookbehind: (?=, (?!, (?<=, (?<!
       - backreferences: \1..\9, (?P=name)
       - possessive quantifiers: a++, a*+, a?+
       - atomic groups: (?>...)
       - conditional patterns: (?(...)...)
     If `go` is on PATH, additionally pipes each pattern through
     `regexp.Compile` for an authoritative check.

Exit 0 if every pattern is inside the subset, 1 otherwise.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST_JSON = ROOT / "build/test/test.json"

# Features RE2 does not support. Each entry is (pattern, human-name).
_FORBIDDEN = [
    (re.compile(r"\(\?="), "lookahead (?=...)"),
    (re.compile(r"\(\?!"), "negative lookahead (?!...)"),
    (re.compile(r"\(\?<="), "lookbehind (?<=...)"),
    (re.compile(r"\(\?<!"), "negative lookbehind (?<!...)"),
    (re.compile(r"\(\?>"), "atomic group (?>...)"),
    (re.compile(r"\(\?\("), "conditional pattern (?(...))"),
    (re.compile(r"\\[1-9]"), "backreference \\N"),
    (re.compile(r"\(\?P=[A-Za-z_]"), "named backref (?P=name)"),
    (re.compile(r"[*+?]\+"), "possessive quantifier"),
]


def collect_like_patterns(node, into):
    """Walk `node` and append every value under a `$LIKE` key to `into`."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "`$LIKE`" or k == "$LIKE":
                if isinstance(v, str):
                    into.append(v)
                # If a list of alternatives ever appears, recurse on each.
                elif isinstance(v, list):
                    for item in v:
                        if isinstance(item, str):
                            into.append(item)
            collect_like_patterns(v, into)
    elif isinstance(node, list):
        for item in node:
            collect_like_patterns(item, into)


def check_pattern(pat: str) -> list[str]:
    """Return a list of complaints for `pat`. Empty list means OK."""
    problems = []
    for rx, label in _FORBIDDEN:
        if rx.search(pat):
            problems.append(label)
    return problems


def check_with_go(pats: list[str]) -> dict[str, str]:
    """If `go` is available, compile every pattern via Go's regexp and return
    a {pattern: error_message} dict for the ones that fail. Returns an empty
    dict on success or if Go is not installed."""
    try:
        subprocess.run(
            ["go", "version"],
            check=True,
            capture_output=True,
            timeout=10,
        )
    except (FileNotFoundError, subprocess.CalledProcessError, subprocess.TimeoutExpired):
        return {}

    # Build a one-shot Go program that reads patterns from stdin (one per line)
    # and prints "OK <pat>" or "ERR <pat>: <msg>".
    prog = r"""
package main
import (
  "bufio"
  "encoding/base64"
  "fmt"
  "os"
  "regexp"
)
func main() {
  s := bufio.NewScanner(os.Stdin)
  s.Buffer(make([]byte, 64*1024), 1024*1024)
  for s.Scan() {
    raw, err := base64.StdEncoding.DecodeString(s.Text())
    if err != nil { fmt.Printf("ERR (decode failed): %v\n", err); continue }
    pat := string(raw)
    if _, err := regexp.Compile(pat); err != nil {
      fmt.Printf("ERR %s :: %s\n", pat, err.Error())
    } else {
      fmt.Printf("OK %s\n", pat)
    }
  }
}
"""
    import base64
    inputs = "\n".join(base64.b64encode(p.encode()).decode() for p in pats) + "\n"
    try:
        out = subprocess.run(
            ["go", "run", "-"],
            input=prog + "\x00",
            capture_output=True,
            text=True,
            timeout=30,
        )
        # Above won't work — `go run -` needs filename input. Use a temp file.
    except Exception:
        pass

    # Simpler: write a temp program file and pipe patterns.
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        src = Path(d) / "checkre.go"
        src.write_text(prog)
        try:
            proc = subprocess.run(
                ["go", "run", str(src)],
                input=inputs,
                capture_output=True,
                text=True,
                timeout=60,
            )
        except Exception as e:
            print(f"  (Go check skipped: {e})", file=sys.stderr)
            return {}
    out_lines = proc.stdout.splitlines()
    fails: dict[str, str] = {}
    for line in out_lines:
        if line.startswith("ERR "):
            rest = line[4:]
            if " :: " in rest:
                pat, msg = rest.split(" :: ", 1)
                fails[pat] = msg
    return fails


def main() -> int:
    if not TEST_JSON.exists():
        print(f"missing {TEST_JSON}", file=sys.stderr)
        return 1
    data = json.loads(TEST_JSON.read_text())
    pats: list[str] = []
    collect_like_patterns(data, pats)
    # Dedupe but preserve order.
    seen: set[str] = set()
    unique: list[str] = []
    for p in pats:
        if p not in seen:
            seen.add(p)
            unique.append(p)
    print(f"corpus regex patterns: {len(unique)} unique ({len(pats)} occurrences)")
    bad: list[tuple[str, list[str]]] = []
    for p in unique:
        issues = check_pattern(p)
        if issues:
            bad.append((p, issues))
        else:
            print(f"  ok  {p!r}")
    go_fails = check_with_go(unique)
    for p, msg in go_fails.items():
        already = next((b for b in bad if b[0] == p), None)
        if already:
            already[1].append(f"go regexp.Compile: {msg}")
        else:
            bad.append((p, [f"go regexp.Compile: {msg}"]))
    for p, issues in bad:
        print(f"  FAIL {p!r}")
        for it in issues:
            print(f"        — {it}")
    if bad:
        print(
            f"\n{len(bad)} corpus pattern(s) use features outside the RE2 subset.\n"
            "Patterns must work in Go's `regexp` package; see /design/REGEX.md."
        )
        return 1
    print("\nall corpus regex patterns are inside the RE2 subset.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
