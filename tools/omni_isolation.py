#!/usr/bin/env python3
"""Register 4.13: no port's LIBRARY may declare voxgig/omni.

omni is the corpus runner. It is a TEST dependency of every port and a
published dependency of none, so nothing a consumer of struct resolves may
name it.

WHY THIS EXISTS, AND WHY IT IS NOT A BUILD-WITHOUT-OMNI CHECK.  4.13's rule
is about DECLARATION - does the library manifest name omni.  The proof the
register originally prescribed is about RESOLUTION - "CI must prove it with
the checkout absent".  Those are the same test only while omni is unfindable
by any other route, and Go left that state without anyone deciding to:
`github.com/voxgig/omni/go` resolves from proxy.golang.org today, with no
tags, because omni is a public repo.  `go mod tidy` in a module with no omni
checkout anywhere resolves a pseudo-version and writes the require line - the
voxgig/struct#89 bug that opened 4.13 in the first place.

So for Go a checkout-absent build can now go green while proving nothing.

That hole is GO'S SPECIFICALLY, and the difference is what a mechanism names
omni BY.  rust (`../../.omni/rust`), swift (the `.omni-runner` symlink), dart
(a generated `pubspec_overrides.yaml`), haskell (`-i$(OMNI_DIR)/haskell/src`)
and lean (`.omni-build`) all name a literal PATH, and a path has no fallback:
a Cargo path dependency whose target is absent fails with `failed to load
source for dependency` and never reaches for a registry or a git ref, however
much of omni is published.  Go needs a pair no other port has - a module path
a public proxy already serves, AND a routine command that writes that
resolution into the published manifest.

A declaration check is still worth having in EVERY port, for a reason that has
nothing to do with that hole: it catches an omni import at the commit that
introduces it, rather than at the `go mod tidy` that publishes it.  No
absence-based check does that at all.

Every check below reads a COMMITTED manifest or a shipped source file and asks
what it DECLARES.
None of them cares whether omni is resolvable, which is why this runs in CI
WITH the omni checkout present: if it passed only because omni was missing,
it would be the very check it replaces.

Adding a port: give it an entry in PORTS.  A port with no manifest is not a
silent pass - it is reported as UNCOVERED and listed in the output, because
"nothing to check" and "checked and clean" must never look alike.

Exit status: 0 if every library manifest is clean, 1 otherwise.  Every
failure is reported, not just the first.
"""

import json
import re
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Matches the ways omni is spelled across ecosystems: the npm scope
# (@voxgig/omni, @voxgig/omni-js), the Go module path, the Maven coordinate,
# the crate/gem/pub name (voxgig_omni, voxgig-omni) and a bare "omni" used as
# a component name.
OMNI = re.compile(r'(^|[^a-z0-9])(@?voxgig[/_.-]omni|omni)([^a-z0-9]|$)', re.I)


def names_omni(text):
    return bool(OMNI.search(text or ''))


# ---------------------------------------------------------------------------
# Per-format readers.  Each returns a list of DECLARED dependency strings for
# the LIBRARY only - the test/harness half of a manifest is skipped, because
# a harness naming omni is the whole point.
# ---------------------------------------------------------------------------

def read_go_mod(path):
    """go.mod: every module path in a require, single or block form."""
    deps, inblock = [], False
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.split('//')[0].strip()
        if line.startswith('require ('):
            inblock = True
            continue
        if inblock:
            if line == ')':
                inblock = False
            elif line:
                deps.append(line.split()[0])
        elif line.startswith('require '):
            deps.append(line[len('require '):].split()[0])
        elif line.startswith(('replace ', 'exclude ')):
            deps.append(line)
    return deps


def read_cargo(path):
    """Cargo.toml: dependencies AND dev-dependencies.

    dev-dependencies are NOT exempt here the way npm devDependencies are.
    Cargo resolves dev-dependencies even for a plain `cargo build`, which is
    exactly why struct/rust puts the harness in a separate corpus/ package
    rather than a dev-dependency (register 4.13).
    """
    data = tomllib.loads(path.read_text(encoding='utf-8'))
    deps = []
    for block in ('dependencies', 'dev-dependencies', 'build-dependencies'):
        deps.extend((data.get(block) or {}).keys())
    for tgt in (data.get('target') or {}).values():
        for block in ('dependencies', 'dev-dependencies'):
            deps.extend((tgt.get(block) or {}).keys())
    return deps


def read_package_json(path):
    """package.json: every block EXCEPT devDependencies.

    devDependencies is the isolation device for the Node ports - npm never
    installs a devDependency transitively - so naming omni there is correct.
    The deeper checks (production tree walked, lockfile dev:true, no shipped
    file naming omni) live in typescript/tools/omni-isolation.js.
    """
    data = json.loads(path.read_text(encoding='utf-8'))
    deps = []
    for block in ('dependencies', 'peerDependencies', 'optionalDependencies'):
        deps.extend((data.get(block) or {}).keys())
    return deps


def read_composer(path):
    """composer.json: require, and the fields that stand in for it.

    require-dev is exempt: Composer never installs a dependency's require-dev.
    """
    data = json.loads(path.read_text(encoding='utf-8'))
    deps = []
    for block in ('require', 'replace', 'provide', 'conflict'):
        deps.extend((data.get(block) or {}).keys())
    return deps


def read_pyproject(path):
    data = tomllib.loads(path.read_text(encoding='utf-8'))
    proj = data.get('project') or {}
    deps = list(proj.get('dependencies') or [])
    for group in (proj.get('optional-dependencies') or {}).values():
        deps.extend(group)
    deps.extend((data.get('build-system') or {}).get('requires') or [])
    return deps


def read_pom(path):
    """pom.xml: dependencies OUTSIDE any <profile>.

    struct/java keeps omni behind a `-Pomni` profile precisely so it is
    invisible to a consumer's resolver and to static scanners; a dependency
    in the default model is the failure this looks for.
    """
    ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
    root = ET.parse(path).getroot()
    profiles = {id(e) for p in root.findall('.//m:profiles', ns)
                for e in p.iter()}
    deps = []
    for dep in root.findall('.//m:dependency', ns):
        if id(dep) in profiles:
            continue
        gid = dep.findtext('m:groupId', '', ns)
        aid = dep.findtext('m:artifactId', '', ns)
        deps.append(f'{gid}:{aid}')
    return deps


def read_csproj(path):
    """A .csproj: PackageReference and ProjectReference."""
    root = ET.parse(path).getroot()
    deps = []
    for tag in ('PackageReference', 'ProjectReference'):
        for el in root.iter():
            if el.tag.split('}')[-1] != tag:
                continue
            deps.append(el.get('Include') or el.get('Update') or '')
    return deps


def read_lakefile(path):
    """lakefile.toml: [[require]] blocks only.

    A [[lean_lib]] with a srcDir is NOT a dependency declaration - it names a
    local directory, and nothing resolves it.  struct/lean's `Omni` lean_lib
    points at the gitignored .omni-build tree, so it is correctly not a
    require and not a thing a consumer resolves.
    """
    data = tomllib.loads(path.read_text(encoding='utf-8'))
    deps = []
    for req in (data.get('require') or []):
        deps.append(json.dumps(req))
    return deps


def read_swift(path):
    """Package.swift, structurally.

    This manifest legitimately names omni ten times: it is a Swift PROGRAM
    that declares the dependency only when the gitignored `.omni-runner`
    symlink exists, and only for the TEST target.  A grep would fail on the
    correct tree, so scope the check to what a consumer resolves - the
    `dependencies:` of the Package and of every non-test target.

    The `dependencies: nil == omniPath ? [] : [...]` form is what makes the
    package-level list conditional; that is accepted, and what is rejected is
    an unconditional package dependency or any omni reference inside a
    .target/.executableTarget dependency list.
    """
    text = path.read_text(encoding='utf-8')
    fails = []

    # Package-level dependencies must be empty unless gated on omniPath.
    m = re.search(r'\n\s*dependencies:\s*(.*?)(?=\n\s*targets:)', text, re.S)
    if m and names_omni(m.group(1)) and 'omniPath' not in m.group(1):
        fails.append('package dependencies name omni unconditionally')

    # Any non-test target naming omni in its dependency list.
    for tm in re.finditer(r'\.(target|executableTarget)\((.*?)\n\s*\)', text, re.S):
        if names_omni(tm.group(2)):
            fails.append(f'.{tm.group(1)} declares omni: '
                         + ' '.join(tm.group(2).split())[:70])
    return fails


def read_scoped(path, start, stop=None):
    """Read the dependency-declaring REGION of a manifest with no stdlib
    parser (cabal, opam, gemspec, rockspec, gradle.kts, mix.exs, deps.edn,
    Makefile.PL, build.zig.zon, pubspec.yaml).

    This is a scoped textual scan, and saying so plainly matters: it is
    weaker than a parse and it is what is available without adding a runtime
    dependency, which AGENTS.md forbids.  It is scoped rather than a whole
    file grep so that a comment or a harness stanza naming omni - which every
    one of these manifests is entitled to do - cannot false-positive.
    """
    text = path.read_text(encoding='utf-8')
    m = re.search(start, text, re.I | re.M)
    if not m:
        return []
    tail = text[m.end():]
    if stop:
        e = re.search(stop, tail, re.I | re.M)
        if e:
            tail = tail[:e.start()]
    return [line for line in tail.splitlines() if line.strip()]


# ---------------------------------------------------------------------------
# Source scan.  A manifest check alone is not enough for a compiled port with
# a module system: the manifest is DERIVED from the imports.  struct/go's
# original bug was an omni import in a normal package - the require line only
# appeared later, when someone ran `go mod tidy`.  So the manifest was clean
# right up until it silently wasn't.
#
# This walks the files a port SHIPS and asserts none of them imports omni,
# which catches that regression at the commit that introduces it rather than
# at the tidy that publishes it.  Harness trees are excluded by path - they
# are supposed to import omni.
# ---------------------------------------------------------------------------

SOURCES = {
    'go':     dict(globs=['go/**/*.go'],
                   skip=['go/testutil/'],
                   pattern=r'voxgig/omni'),
    'rust':   dict(globs=['rust/src/**/*.rs'], skip=[], pattern=r'voxgig_omni'),
    'java':   dict(globs=['java/src/**/*.java'], skip=['java/src/test/'],
                   pattern=r'\bomni\b'),
    'kotlin': dict(globs=['kotlin/src/main/**/*.kt'], skip=[], pattern=r'voxgig\.omni'),
    'csharp': dict(globs=['csharp/*.cs'], skip=[], pattern=r'\bomni\b'),
    'swift':  dict(globs=['swift/Sources/**/*.swift'], skip=[], pattern=r'\bomni\b'),
    'haskell': dict(globs=['haskell/src/**/*.hs'], skip=[], pattern=r'\bOmni\b'),
    'python': dict(globs=['python/voxgig_struct/**/*.py'], skip=[], pattern=r'\bomni\b'),
    'ruby':   dict(globs=['ruby/voxgig_struct.rb'], skip=[], pattern=r'\bomni\b'),
    'php':    dict(globs=['php/src/**/*.php'], skip=[], pattern=r'voxgig.{0,2}omni'),
    'dart':   dict(globs=['dart/lib/**/*.dart'], skip=[], pattern=r'voxgig_omni'),
    'elixir': dict(globs=['elixir/lib/**/*.ex'], skip=[], pattern=r'\bOmni\b'),
    'lua':    dict(globs=['lua/src/**/*.lua'], skip=[], pattern=r'\bomni\b'),
    'clojure': dict(globs=['clojure/src/**/*.clj*'], skip=[], pattern=r'\bomni\b'),
    'scala':  dict(globs=['scala/src/**/*.scala'], skip=[], pattern=r'\bomni\b'),
    'c':      dict(globs=['c/src/**/*.[ch]'], skip=[], pattern=r'\bomni\b'),
    'cpp':    dict(globs=['cpp/src/**/*.[ch]pp', 'cpp/src/**/*.h'], skip=[],
                   pattern=r'\bomni\b'),
    'ocaml':  dict(globs=['ocaml/src/**/*.ml*'], skip=[], pattern=r'\bomni\b'),
    'perl':   dict(globs=['perl/lib/**/*.pm'], skip=[], pattern=r'\bomni\b'),
    'lean':   dict(globs=['lean/src/**/*.lean'], skip=[], pattern=r'\bOmni\b'),
    'typescript': dict(globs=['typescript/src/**/*.ts'], skip=[], pattern=r'voxgig/omni'),
    'javascript': dict(globs=['javascript/src/**/*.js'], skip=[], pattern=r'voxgig/omni'),
}


def scan_sources(port):
    spec = SOURCES.get(port)
    if not spec:
        return [], 0
    rx = re.compile(spec['pattern'], re.I)
    hits, seen = [], 0
    for glob in spec['globs']:
        for path in ROOT.glob(glob):
            rel = path.relative_to(ROOT).as_posix()
            if any(rel.startswith(s) for s in spec['skip']):
                continue
            seen += 1
            try:
                text = path.read_text(encoding='utf-8', errors='replace')
            except OSError:
                continue
            for n, line in enumerate(text.splitlines(), 1):
                if rx.search(line):
                    hits.append(f'{rel}:{n}: {line.strip()[:70]}')
    return hits, seen


# ---------------------------------------------------------------------------
# The ports.  `lib` is what a consumer resolves; `harness` is listed only so
# the output can say it was deliberately skipped rather than missed.
# ---------------------------------------------------------------------------

PORTS = {
    'go':         dict(lib=[('go/go.mod', read_go_mod)],
                       harness=['go/testutil/go.mod']),
    'rust':       dict(lib=[('rust/Cargo.toml', read_cargo)],
                       harness=['rust/corpus/Cargo.toml']),
    'java':       dict(lib=[('java/pom.xml', read_pom)]),
    'csharp':     dict(lib=[('csharp/VoxgigStruct.csproj', read_csproj)],
                       harness=['csharp/tests/VoxgigStructTest.csproj',
                                'csharp/bench/bench.csproj']),
    'typescript': dict(lib=[('typescript/package.json', read_package_json)]),
    'javascript': dict(lib=[('javascript/package.json', read_package_json)]),
    'php':        dict(lib=[('php/composer.json', read_composer)]),
    'python':     dict(lib=[('python/pyproject.toml', read_pyproject)]),
    'lean':       dict(lib=[('lean/lakefile.toml', read_lakefile)]),
    'swift':      dict(lib=[('swift/Package.swift', read_swift)], structural=True),

    # Scoped scans - no stdlib parser for these formats.
    'haskell':    dict(lib=[('haskell/voxgig-struct.cabal',
                             lambda p: read_scoped(p, r'^library\b',
                                                   r'^(test-suite|executable|benchmark)\b'))]),
    'ocaml':      dict(lib=[('ocaml/voxgig-struct.opam',
                             lambda p: read_scoped(p, r'^depends:', r'^\w+:'))]),
    'ruby':       dict(lib=[('ruby/voxgig_struct.gemspec',
                             lambda p: read_scoped(p, r'Gem::Specification\.new'))]),
    'lua':        dict(lib=[('lua/struct.rockspec',
                             lambda p: read_scoped(p, r'^dependencies\s*=', r'^\w+\s*='))]),
    'elixir':     dict(lib=[('elixir/mix.exs',
                             lambda p: read_scoped(p, r'defp?\s+deps\b', r'^\s*end\b'))]),
    'kotlin':     dict(lib=[('kotlin/build.gradle.kts',
                             lambda p: read_scoped(p, r'^\s*dependencies\s*\{', r'^\}'))]),
    'clojure':    dict(lib=[('clojure/deps.edn',
                             lambda p: read_scoped(p, r':deps\b', r':aliases\b'))]),
    'dart':       dict(lib=[('dart/pubspec.yaml',
                             lambda p: read_scoped(p, r'^dependencies:', r'^dev_dependencies:'))]),
    'perl':       dict(lib=[('perl/Makefile.PL',
                             lambda p: read_scoped(p, r'WriteMakefile'))]),

    # No manifest of any kind - reported, never silently passed.
    'c':          dict(lib=[], why='header/source tree, no manifest a consumer resolves'),
    'cpp':        dict(lib=[], why='header-only, no manifest a consumer resolves'),
    'scala':      dict(lib=[], why='no build file at all - scala-cli argument lists in the Makefile'),
    'zig':        dict(lib=[], why='not migrated onto omni (register Phase 1: BLOCKED)'),
}


def main():
    fails, uncovered, checked = [], [], []

    for port in sorted(PORTS):
        spec = PORTS[port]
        if not spec['lib']:
            uncovered.append((port, spec.get('why', 'no manifest')))
            continue

        for relpath, reader in spec['lib']:
            path = ROOT / relpath
            if not path.exists():
                fails.append(f'{port}: {relpath} is missing - has the port moved?')
                continue
            try:
                found = reader(path)
            except Exception as err:                     # noqa: BLE001
                fails.append(f'{port}: could not read {relpath}: {err!r}')
                continue

            checked.append(relpath)
            if spec.get('structural'):
                # The reader returns failures directly, not dependency names.
                for f in found:
                    fails.append(f'{port}: {relpath}: {f}')
            else:
                for dep in found:
                    if names_omni(dep):
                        fails.append(f'{port}: {relpath} declares omni: '
                                     + ' '.join(str(dep).split())[:80])

    # The shipped SOURCE of every port, harness trees excluded.
    #
    # A glob that matches NOTHING is a failure, not a pass. Three of these
    # were wrong when first written - csharp, java and python each had a
    # source layout the glob did not describe - and every one of them
    # reported "clean" while reading zero files. Silence and success must
    # not look alike, so an empty match is reported as loudly as a hit.
    scanned = 0
    for port in sorted(SOURCES):
        hits, seen = scan_sources(port)
        scanned += seen
        if 0 == seen:
            fails.append(f'{port}: source globs matched NO files '
                         f'({SOURCES[port]["globs"]}) - the scan is checking '
                         'nothing; fix the glob')
        for hit in hits:
            fails.append(f'{port}: shipped source imports omni: {hit}')

    print(f'register 4.13 - library manifests checked: {len(checked)}, '
          f'shipped source files scanned: {scanned}')
    for port, why in uncovered:
        print(f'  UNCOVERED  {port}: {why}')

    if fails:
        print('\nstruct: omni is declared by something a consumer resolves\n',
              file=sys.stderr)
        for f in fails:
            print(f'  {f}', file=sys.stderr)
        return 1

    print('  all clean')
    return 0


if __name__ == '__main__':
    sys.exit(main())
