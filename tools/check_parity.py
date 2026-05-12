#!/usr/bin/env python3
"""Cross-port API parity check.

The canonical public API is the `export { ... }` block in
`ts/src/StructUtility.ts`.  Every "complete" port is expected to define an
equivalent function for each canonical name, in that language's casing
convention (snake_case in Rust, PascalCase in Go/C#, camelCase in Java,
lower-smushed everywhere else).

This is a smoke test: it confirms a function with the expected name exists in
each port's source (matching is done on a case/underscore-insensitive key, so
`get_path`, `GetPath`, `getPath` and `getpath` all count as the same name).
It does not check signatures — the shared JSONic test corpus is the real
behavioural contract.

Exit status: 0 if every complete port defines every canonical function;
1 otherwise.  Ports the README marks "in progress" are reported for
information only and never affect the exit status.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Ports the README marks "Complete" — these must be in full parity with the
# canonical TypeScript API.  ("ts" itself is the canonical source, so it is
# trivially in parity and is not checked.)
COMPLETE_PORTS = ["js", "py", "go", "php", "rb", "lua", "rs", "zig"]
PARTIAL_PORTS = ["java", "cpp", "cs", "kt"]

# Accepted, documented divergences (normalised name keys).  Anything NOT listed
# here is treated as a parity gap and fails the check; this list should only
# shrink.
KNOWN_GAPS: dict[str, set[str]] = {}

# Source files per port (implementation only — not tests).
SOURCES = {
    "ts": ["ts/src/StructUtility.ts"],
    "js": ["js/src/struct.js"],
    "py": ["py/voxgig_struct/voxgig_struct.py", "py/voxgig_struct/__init__.py"],
    "go": ["go/voxgigstruct.go"],
    "php": ["php/src/Struct.php"],
    "rb": ["rb/voxgig_struct.rb"],
    "lua": ["lua/src/struct.lua"],
    "rs": ["rs/src/lib.rs", "rs/src/major.rs", "rs/src/mini.rs"],
    "java": ["java/src/Struct.java"],
    "cpp": ["cpp/src/voxgig_struct.hpp", "cpp/src/value.hpp", "cpp/src/utility_decls.hpp"],
    "cs": ["cs/Struct.cs"],
    "zig": ["zig/src/struct.zig"],
    "kt": ["kt/src/main/kotlin/voxgig/struct/Struct.kt"],
}


def norm(name: str) -> str:
    """Case/underscore-insensitive comparison key."""
    return name.replace("_", "").lower()


def canonical_names() -> list[str]:
    ts = (ROOT / "ts/src/StructUtility.ts").read_text()
    m = re.search(r"^export \{\n(.*?)\n\}", ts, re.S | re.M)
    if not m:
        sys.exit("could not parse the canonical export list from ts/src/StructUtility.ts")
    names = [n.strip().rstrip(",") for n in m.group(1).splitlines() if n.strip()]
    out = []
    for n in names:
        if not n or n == "StructUtility":
            continue
        # Drop value/flag constants — they're not functions.
        if n in {"SKIP", "DELETE", "MODENAME"} or n.startswith(("T_", "M_")):
            continue
        out.append(n)
    return out


_IDENT_BEFORE_PAREN = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*\(")
# Catches re-exports / aliases / object-literal keys / module-table entries:
#   `jm = jo`  (Python alias),  `select = select_fn`  (Lua module table),
#   `getpath: getPath,` (JS module.exports), `var Jm = ...` (Go), `jm,` (export list)
_IDENT_DECL = re.compile(r"^\s*(?:(?:export|public|static|const|let|var|local)\s+)*([A-Za-z_][A-Za-z0-9_]*)\s*(?:[:=,]|$)", re.M)


def defined_keys(port: str) -> set[str]:
    """Comparison keys for every identifier a port's source defines/re-exports.

    A function *definition* always writes the name immediately before `(`; a
    re-export/alias/object key writes it before `=`/`:`/`,`/EOL.  Together this
    is a superset of the port's public names — exactly what we want for a
    "is function X present?" check (false extras are harmless; a false omission
    would be a real parity gap)."""
    keys: set[str] = set()
    for rel in SOURCES.get(port, []):
        p = ROOT / rel
        if not p.exists():
            continue
        text = p.read_text()
        for ident in _IDENT_BEFORE_PAREN.findall(text):
            keys.add(norm(ident))
        for ident in _IDENT_DECL.findall(text):
            keys.add(norm(ident))
    return keys


def main() -> int:
    names = canonical_names()
    canon_keys = {norm(n): n for n in names}
    print(f"canonical API: {len(names)} functions")

    ok = True
    for port in COMPLETE_PORTS:
        have = defined_keys(port)
        gaps = KNOWN_GAPS.get(port, set())
        miss = [orig for key, orig in canon_keys.items() if key not in have and key not in gaps]
        accepted = sorted(orig for key, orig in canon_keys.items() if key not in have and key in gaps)
        suffix = f" (known gaps: {', '.join(accepted)})" if accepted else ""
        if miss:
            ok = False
            print(f"  FAIL {port:5} — missing {len(miss)}: " + ", ".join(sorted(miss)) + suffix)
        else:
            print(f"  ok   {port}{suffix}")

    for port in PARTIAL_PORTS:
        have = defined_keys(port)
        miss = [orig for key, orig in canon_keys.items() if key not in have]
        if miss:
            print(f"  note {port:5} (in progress) — missing {len(miss)}: " + ", ".join(sorted(miss)))
        else:
            print(f"  ok   {port:5} (in progress; full parity)")

    if not ok:
        print("\nA complete port is missing one or more canonical functions.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
