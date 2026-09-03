#!/usr/bin/env python3
"""bump.py — raise the patch version of one or more ports, everywhere it is written.

A port's version is not one string in one file. Six of them keep a second (or
third) copy that a guard or a build reads, and a bump that moves only the
manifest leaves the port in a state its own `make publish` refuses:

    ocaml       `make publish` aborts unless VERSION and dune-project agree
    haskell     the .cabal version names the sdist tarball
    lua         the rockspec's source `tag` points at this repo's release tag
    lean        lakefile.toml carries it alongside VERSION
    typescript  a `// VERSION:` comment in src and test, and the committed dist/
    javascript  the same comment in src/struct.js

GENERATED FILES ARE REGENERATED, NEVER EDITED. The npm ports own a
`inject-version` script and typescript has a build; rust has two lockfiles that
cargo maintains. This script shells out to those rather than rewriting their
output by hand, so the result is whatever the port's own tooling produces.

AN UNRELEASED VERSION IS NOT BUMPED PAST. The test is whether the version now
in the manifest carries a tag -- not whether the port was ever tagged at all.
A port bumped in a previous run whose tag push then failed is sitting on a
version no consumer has seen, and bumping again would skip it permanently:
the release that eventually happens jumps from the last tag straight over it.
Both states exist here -- `lean` has never been tagged, and a failed tag push
leaves any port that way. Such a port is reported and left alone, and
releasing it publishes the version already in its manifest.

Stdlib only; runs on Python 3.9+.

Usage:
    python3 tools/bump.py --ports go,php,rust      # bump those
    python3 tools/bump.py --ports go --dry-run     # report, write nothing
    python3 tools/bump.py --ports go --check       # verify every copy agrees
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class Loc:
    """One place a version is written.

    `pattern` must capture the version in group 1 and match exactly once in the
    file; a second match means the pattern is too loose to rewrite safely. That
    is not hypothetical: `  <version>0.1.0</version>` in java/pom.xml is also a
    substring of the ten-space-indented omni test dependency further down, so a
    naive pattern silently rewrites voxgig/omni's version instead of the port's.
    """

    def __init__(self, path: str, pattern: str, flags: int = 0):
        self.path = path
        self.pattern = re.compile(pattern, flags)

    def read(self) -> str:
        text = (ROOT / self.path).read_text()
        found = self.pattern.findall(text)
        if len(found) != 1:
            sys.exit(
                f"{self.path}: pattern matched {len(found)} times, expected 1 "
                f"-- refusing to guess which one is the port's version"
            )
        return found[0]

    def write(self, old: str, new: str) -> None:
        path = ROOT / self.path
        text = path.read_text()
        # Rewrite through the same anchored pattern, not a bare replace of the
        # version string: the bare string can occur in prose, a dependency pin
        # or another port's tag reference in the same file.
        replaced, count = self.pattern.subn(
            lambda m: m.group(0).replace(old, new, 1), text, count=1
        )
        if count != 1:
            sys.exit(f"{self.path}: rewrite matched {count} times, expected 1")
        path.write_text(replaced)


def plain(path: str) -> Loc:
    """A VERSION file: the whole content is the version."""
    return Loc(path, r"\A\s*(\d+\.\d+\.\d+)\s*\Z")


# port -> (tag prefix, version locations, post-bump commands)
#
# EVERY PREFIX IS `<lang>/v`, typescript included. It used to be the exception
# -- the package released under the bare `v<version>` namespace, so this table
# carried `"v"` for it and reading `typescript/v*` found one stale Makefile tag
# and reported the port as years behind. publish.yml writes
# `typescript/v<version>` now, and the 16 bare tags up to `v0.3.4` are the
# history that scheme left behind. `typescript/v0.3.4` was added alongside the
# bare one, so this table finds the current release rather than that stale tag.
PORTS = {
    "go":         ("go/v",         [plain("go/VERSION")], []),
    "php":        ("php/v",        [plain("php/VERSION")], []),
    "c":          ("c/v",          [plain("c/VERSION")], []),
    "cpp":        ("cpp/v",        [plain("cpp/VERSION")], []),
    "swift":      ("swift/v",      [plain("swift/VERSION")], []),
    "zig":        ("zig/v",        [Loc("zig/build.zig.zon", r'\.version = "(\d+\.\d+\.\d+)"')], []),
    "lean":       ("lean/v",       [plain("lean/VERSION"),
                                    Loc("lean/lakefile.toml", r'(?m)^version = "(\d+\.\d+\.\d+)"')], []),
    "rust":       ("rust/v",       [Loc("rust/Cargo.toml", r'(?m)^version = "(\d+\.\d+\.\d+)"')],
                                   # cargo owns both lockfiles; `metadata` refreshes
                                   # the workspace entry without touching dependency
                                   # versions the way `cargo update` would.
                                   [("rust", ["cargo", "metadata", "--format-version", "1"]),
                                    ("rust/corpus", ["cargo", "metadata", "--format-version", "1"])]),
    "javascript": ("javascript/v", [Loc("javascript/package.json", r'"version": "(\d+\.\d+\.\d+)"')],
                                   [("javascript", ["npm", "run", "inject-version"])]),
    # --- registry ports ---
    "python":     ("python/v",     [Loc("python/pyproject.toml", r'(?m)^version = "(\d+\.\d+\.\d+)"')], []),
    "ruby":       ("ruby/v",       [Loc("ruby/voxgig_struct.gemspec", r"spec\.version\s*=\s*'(\d+\.\d+\.\d+)'")], []),
    "csharp":     ("csharp/v",     [Loc("csharp/VoxgigStruct.csproj", r"<Version>(\d+\.\d+\.\d+)</Version>")], []),
    "perl":       ("perl/v",       [Loc("perl/lib/Voxgig/Struct.pm", r"our \$VERSION = '(\d+\.\d+\.\d+)';")], []),
    # Anchored on the project's own coordinates: the bare `<version>` line is
    # also a substring of the omni test dependency further down the file.
    "java":       ("java/v",       [Loc("java/pom.xml",
                                        r"<artifactId>struct-java</artifactId>\s*\n\s*<version>(\d+\.\d+\.\d+)</version>")], []),
    "kotlin":     ("kotlin/v",     [Loc("kotlin/build.gradle.kts", r'(?m)^version = "(\d+\.\d+\.\d+)"')], []),
    "scala":      ("scala/v",      [plain("scala/VERSION")], []),
    "clojure":    ("clojure/v",    [plain("clojure/VERSION")], []),
    "elixir":     ("elixir/v",     [plain("elixir/VERSION")], []),
    "dart":       ("dart/v",       [Loc("dart/pubspec.yaml", r"(?m)^version: (\d+\.\d+\.\d+)")], []),
    # The rockspec carries the version twice: its own `X.Y.Z-<rev>` (the
    # trailing rockspec revision is not part of the port's version) and the
    # source `tag`, which points at this repo's release tag.
    "lua":        ("lua/v",        [Loc("lua/struct.rockspec", r'(?m)^version = "(\d+\.\d+\.\d+)-\d+"'),
                                    Loc("lua/struct.rockspec", r'tag = "lua/v(\d+\.\d+\.\d+)"')], []),
    "haskell":    ("haskell/v",    [plain("haskell/VERSION"),
                                    Loc("haskell/voxgig-struct.cabal", r"(?m)^version:\s+(\d+\.\d+\.\d+)")], []),
    # `^version:` must be anchored: unanchored it also matches the
    # `opam-version: "2.0"` line above it.
    "ocaml":      ("ocaml/v",      [plain("ocaml/VERSION"),
                                    Loc("ocaml/voxgig-struct.opam", r'(?m)^version: "(\d+\.\d+\.\d+)"'),
                                    Loc("ocaml/dune-project", r"(?m)^\(version (\d+\.\d+\.\d+)\)")], []),
    "typescript": ("typescript/v", [Loc("typescript/package.json", r'"version": "(\d+\.\d+\.\d+)"')],
                                   # inject-version rewrites the src and test
                                   # comments; the build carries them into the
                                   # committed dist/ and dist-test/.
                                   [("typescript", ["npm", "run", "inject-version"]),
                                    ("typescript", ["npm", "run", "build"])]),
}


def run(cmd: list, cwd: Path) -> str:
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"{' '.join(cmd)} (in {cwd}) failed:\n{proc.stderr.strip()}")
    return proc.stdout


def released(prefix: str, version: str) -> bool:
    """Is the version currently in the manifest already tagged?

    NOT "has this port ever been tagged". A port whose manifest has been bumped
    but whose tag was never pushed is sitting on an unreleased version, and
    bumping again skips it permanently -- the release that finally happens
    jumps from the last tag straight past it. Both states occur in this repo:
    `lean` has never been tagged at all, and a tag push that fails after the
    manifest is committed leaves any port that way.

    Local tags only, so callers must `git fetch --tags` first.
    """
    out = run(["git", "tag", "-l", f"{prefix}{version}"], ROOT).strip()
    return bool(out)


def bump_patch(version: str) -> str:
    major, minor, patch = version.split(".")
    return f"{major}.{minor}.{int(patch) + 1}"


def main(argv: list) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ports", required=True, help="comma-separated port names")
    ap.add_argument("--dry-run", action="store_true", help="report, write nothing")
    ap.add_argument("--check", action="store_true", help="verify every copy agrees")
    ap.add_argument("--plan", action="store_true",
                    help="machine-readable: one 'port<TAB>tag<TAB>version' line per port")
    args = ap.parse_args(argv)

    names = [n.strip() for n in args.ports.split(",") if n.strip()]
    unknown = [n for n in names if n not in PORTS]
    if unknown:
        sys.exit(f"unknown port(s): {', '.join(unknown)}\nknown: {', '.join(PORTS)}")

    rc = 0
    for name in names:
        prefix, locs, after = PORTS[name]
        versions = {loc.path: loc.read() for loc in locs}
        distinct = set(versions.values())
        if len(distinct) != 1:
            print(f"  {name}: version copies DISAGREE: {versions}", file=sys.stderr)
            rc = 1
            continue
        current = distinct.pop()

        if args.plan:
            # The release tag this port's CURRENT version wants. Callers cut
            # tags from this rather than composing `<lang>/v<version>`
            # themselves: the prefix is the table's to decide, not theirs.
            print(f"{name}\t{prefix}{current}\t{current}")
            continue

        if args.check:
            print(f"  {name}: {current} (in {len(locs)} file(s), all agree)")
            continue

        if not released(prefix, current):
            print(f"  {name}: {current} left alone — {prefix}{current} is not "
                  f"tagged, so {current} is still unreleased; release it "
                  f"rather than bumping past it")
            continue

        new = bump_patch(current)
        if args.dry_run:
            print(f"  {name}: {current} -> {new} in {', '.join(v for v in versions)}"
                  + (f" (+ {len(after)} regen step(s))" if after else ""))
            continue

        for loc in locs:
            loc.write(current, new)
        for cwd, cmd in after:
            tool = cmd[0]
            if shutil.which(tool) is None:
                sys.exit(f"{name}: {tool} is not installed, but {cwd} needs it to "
                         f"regenerate its version-derived files")
            run(cmd, ROOT / cwd)
        print(f"  {name}: {current} -> {new}")

    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
