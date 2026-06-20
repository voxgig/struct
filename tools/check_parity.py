#!/usr/bin/env python3
"""Cross-port API parity check.

The canonical public API is the `export { ... }` block in
`typescript/src/StructUtility.ts`.  Every "complete" port is expected to
define an equivalent function for each canonical name, in that language's
casing convention (snake_case in Rust, PascalCase in Go/C#, lower-smushed
everywhere else — Java and Kotlin included).

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
# canonical TypeScript API.  ("typescript" itself is the canonical source,
# so it is trivially in parity and is not checked.)
COMPLETE_PORTS = [
    "javascript", "python", "go", "php", "ruby", "lua",
    "rust", "c", "zig", "csharp", "perl", "cpp", "swift", "clojure",
]
PARTIAL_PORTS = ["java", "kotlin"]

# Accepted, documented divergences (normalised name keys).  Anything NOT listed
# here is treated as a parity gap and fails the check; this list should only
# shrink.
#
# zig: the regex helper module exports `re_compile`/`re_test`/`re_escape` but
#   not the canonical `re_find`/`re_find_all`/`re_replace` (the in-tree NFA
#   engine has the primitives, no top-level wrapper has been wired). Track
#   them as known gaps so the parity check can still fail on *new* gaps;
#   this list should only shrink.
KNOWN_GAPS: dict[str, set[str]] = {
    "zig": {"refind", "refindall", "rereplace"},
}

# Source files per port (implementation only — not tests).
SOURCES = {
    "typescript": ["typescript/src/StructUtility.ts"],
    "javascript": ["javascript/src/struct.js"],
    "python": [
        "python/voxgig_struct/voxgig_struct.py",
        "python/voxgig_struct/__init__.py",
    ],
    "go": ["go/voxgigstruct.go"],
    "php": ["php/src/Struct.php"],
    "ruby": ["ruby/voxgig_struct.rb"],
    "lua": ["lua/src/struct.lua"],
    "rust": ["rust/src/lib.rs", "rust/src/major.rs", "rust/src/mini.rs"],
    "c": [
        "c/src/voxgig_struct.h",
        "c/src/value.h",
        "c/src/regex.h",
        "c/src/utility.c",
        "c/src/inject.c",
        "c/src/transform.c",
        "c/src/value.c",
    ],
    "java": ["java/src/Struct.java"],
    "cpp": ["cpp/src/voxgig_struct.hpp", "cpp/src/value.hpp", "cpp/src/utility_decls.hpp"],
    "csharp": ["csharp/Struct.cs"],
    "zig": ["zig/src/struct.zig"],
    "kotlin": ["kotlin/src/main/kotlin/voxgig/struct/Struct.kt"],
    "perl": ["perl/lib/Voxgig/Struct.pm"],
    "clojure": ["clojure/src/voxgig/struct.clj"],
    "swift": [
        "swift/Sources/VoxgigStruct/Value.swift",
        "swift/Sources/VoxgigStruct/Constants.swift",
        "swift/Sources/VoxgigStruct/JSON.swift",
        "swift/Sources/VoxgigStruct/Minor.swift",
        "swift/Sources/VoxgigStruct/Walk.swift",
        "swift/Sources/VoxgigStruct/Merge.swift",
        "swift/Sources/VoxgigStruct/Path.swift",
        "swift/Sources/VoxgigStruct/Inject.swift",
        "swift/Sources/VoxgigStruct/Injection.swift",
        "swift/Sources/VoxgigStruct/Transform.swift",
        "swift/Sources/VoxgigStruct/Validate.swift",
        "swift/Sources/VoxgigStruct/Select.swift",
    ],
}


def norm(name: str) -> str:
    """Case/underscore-insensitive comparison key."""
    return name.replace("_", "").lower()


def canonical_names() -> list[str]:
    ts = (ROOT / "typescript/src/StructUtility.ts").read_text()
    m = re.search(r"^export \{\n(.*?)\n\}", ts, re.S | re.M)
    if not m:
        sys.exit(
            "could not parse the canonical export list from "
            "typescript/src/StructUtility.ts"
        )
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
# Perl `sub NAME {` / `sub NAME (` / `sub NAME;` definitions: the language
# doesn't put `(` after the function name in the definition, so neither of
# the patterns above catches them.
_PERL_SUB_DECL = re.compile(r"^\s*sub\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
# Clojure `(defn name` / `(defn- name` / `(def name` definitions. The library
# uses lower-smushed canonical names (getpath, ismap, re_find, checkPlacement),
# so the same case/underscore-insensitive norm() applies. Clojure idents allow
# extra symbol chars, none of which appear in canonical names.
_CLJ_DEFN_DECL = re.compile(r"\(defn?-?\s+([A-Za-z_][A-Za-z0-9_*+!?<>=-]*)", re.M)


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
        if port == "perl":
            for ident in _PERL_SUB_DECL.findall(text):
                keys.add(norm(ident))
        if port == "clojure":
            for ident in _CLJ_DEFN_DECL.findall(text):
                keys.add(norm(ident))
    # The C port uses a `voxgig_` prefix on every public function. Strip it so
    # `voxgig_getpath` matches canonical `getpath`. Trailing `_v` / `_va`
    # (voxgig_jm_va for variadic-style builders, voxgig_walk_v for the value
    # overload) is also stripped.
    if port == "c":
        extra: set[str] = set()
        for k in keys:
            if k.startswith("voxgig"):
                stripped = k[len("voxgig"):]
                if stripped.endswith("va"):
                    extra.add(stripped[:-2])
                if stripped.endswith("v"):
                    extra.add(stripped[:-1])
                extra.add(stripped)
                # voxgig_regex_* -> re_* alias (the C port's regex helpers ship
                # under the `voxgig_regex_` namespace, but canonical names are
                # `re_compile` / `re_test` / `re_find` / `re_find_all` /
                # `re_replace` / `re_escape`).
                if stripped.startswith("regex"):
                    extra.add("re" + stripped[len("regex"):])
        keys |= extra
    # The C++ port renames `walk` / `merge` / `getpath` / `setpath` to the
    # `_v` ("value-style") suffix to disambiguate them from header-internal
    # helpers, and `typename` to `typename_str` because `typename` is a
    # reserved C++ keyword.  Add the canonical name for each `_v` / `_str`
    # variant so the parity check sees them.
    if port == "cpp":
        extra = set()
        for k in keys:
            if k.endswith("v") and len(k) > 1:
                extra.add(k[:-1])
            if k.endswith("str") and len(k) > 3:
                extra.add(k[:-3])
        keys |= extra
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
