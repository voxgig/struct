#!/usr/bin/env python3
"""Mutation test for tools/omni_isolation.py.

A guard that has never failed is not a guard.  This injects a register-4.13
violation into every port - once into the library manifest, once into a
shipped source file - and requires the checker to catch each one.  It also
injects into the two blocks that are deliberately EXEMPT (npm
`devDependencies`, Composer `require-dev`) and requires the checker to stay
quiet, because a check that fires on the correct tree is as useless as one
that never fires.

This is not ceremony.  Writing the checker, three of its source globs
described a layout the repo does not have - csharp, java and python - and
all three reported "clean" while reading zero files.  Running the checker
against a clean tree could never have found that; only mutation did.

Every mutation is applied to a working-tree copy and reverted in a `finally`,
so an interrupted run leaves the tree as it found it.

Exit status: 0 if every mutation produced the expected verdict, 1 otherwise.
"""

import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECK = [sys.executable, 'tools/omni_isolation.py']

_spec = importlib.util.spec_from_file_location(
    'omni_isolation', ROOT / 'tools' / 'omni_isolation.py')
ISO = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ISO)

# A line that spells omni every way any port's pattern looks for.
LEAK = '// Omni voxgig_omni Voxgig.Omni voxgig.omni voxgig/omni omni\n'

# (port, manifest, anchor, replacement) - the anchor must exist, and a
# missing one is a FAILURE, not a skip: it means the manifest moved and the
# mutation silently stopped testing anything.
MANIFEST = [
    ('go', 'go/go.mod', 'go 1.23',
     'go 1.23\n\nrequire github.com/voxgig/omni/go v0.0.0-20260825220049-74ae081d405a'),
    ('rust', 'rust/Cargo.toml', '[lib]',
     '[dependencies]\nvoxgig_omni = { path = "../../omni/rust" }\n\n[lib]'),
    ('java', 'java/pom.xml', '</dependencies>',
     '<dependency><groupId>com.voxgig</groupId><artifactId>omni</artifactId>'
     '<version>0.1.0</version></dependency></dependencies>'),
    ('csharp', 'csharp/VoxgigStruct.csproj', '</Project>',
     '<ItemGroup><PackageReference Include="Voxgig.Omni" Version="0.1.0" /></ItemGroup></Project>'),
    ('typescript', 'typescript/package.json', '"main": "dist/StructUtility.js",',
     '"dependencies": { "@voxgig/omni": "^0.1.1" },\n  "main": "dist/StructUtility.js",'),
    ('javascript', 'javascript/package.json', '"main": "src/struct.js",',
     '"dependencies": { "@voxgig/omni-js": "^0.1.1" },\n  "main": "src/struct.js",'),
    ('php', 'php/composer.json', '"require-dev": {',
     '"require": { "voxgig/omni": "^0.1" },\n    "require-dev": {'),
    ('python', 'python/pyproject.toml', '[project]',
     '[project]\ndependencies = ["voxgig-omni>=0.1"]'),
    ('lean', 'lean/lakefile.toml', '[[lean_lib]]',
     '[[require]]\nname = "omni"\ngit = "https://github.com/voxgig/omni"\n\n[[lean_lib]]'),
    ('swift', 'swift/Package.swift',
     '.target(name: "VoxgigStruct", path: "Sources/VoxgigStruct")',
     '.target(name: "VoxgigStruct", path: "Sources/VoxgigStruct", '
     'dependencies: [.product(name: "Omni", package: "VoxgigOmni")])'),
    ('haskell', 'haskell/voxgig-struct.cabal', 'build-depends:',
     'build-depends: voxgig-omni,'),
    ('ocaml', 'ocaml/voxgig-struct.opam', 'depends: [', 'depends: [\n  "voxgig-omni"'),
    ('ruby', 'ruby/voxgig_struct.gemspec', 'Gem::Specification.new',
     'Gem::Specification.new # spec.add_dependency "voxgig_omni"'),
    ('lua', 'lua/struct.rockspec', 'dependencies =',
     'dependencies = { "voxgig-omni" } -- '),
    ('elixir', 'elixir/mix.exs', 'defp deps',
     'defp deps, do: [{:voxgig_omni, path: "../../omni/elixir"}]\n  defp deps_unused'),
    ('kotlin', 'kotlin/build.gradle.kts', 'dependencies {',
     'dependencies {\n    implementation("com.voxgig:omni:0.1.0")'),
    ('clojure', 'clojure/deps.edn', ':deps',
     ':deps {voxgig/omni {:mvn/version "0.1.0"}} :unused-deps'),
    ('dart', 'dart/pubspec.yaml', 'environment:',
     'dependencies:\n  voxgig_omni:\n    path: ../../omni/dart\n\nenvironment:'),
    ('perl', 'perl/Makefile.PL', 'WriteMakefile(',
     'WriteMakefile(\n  PREREQ_PM => { "Voxgig::Omni" => 0 },'),
]

# Blocks that may name omni. The checker must NOT fire on these.
EXEMPT = [
    ('typescript', 'typescript/package.json', '"main": "dist/StructUtility.js",',
     '"devDependencies": { "@voxgig/omni": "^0.1.1" },\n  "main": "dist/StructUtility.js",',
     'npm devDependencies are never installed transitively'),
    ('php', 'php/composer.json', '"require-dev": {',
     '"require-dev": { "voxgig/omni": "^0.1",',
     "Composer never installs a dependency's require-dev"),
]


def check():
    return subprocess.run(CHECK, cwd=ROOT, capture_output=True, text=True)


def fired(result, needle):
    return 0 != result.returncode and needle in (result.stderr or '')


def mutate(relpath, anchor, replacement, needle, expect, tag):
    path = ROOT / relpath
    original = path.read_text(encoding='utf-8', errors='surrogateescape')
    if anchor and anchor not in original:
        return ('FAIL', tag, f'anchor vanished from {relpath} - mutation tests nothing')
    try:
        body = (original.replace(anchor, replacement, 1) if anchor
                else replacement + original)
        path.write_text(body, encoding='utf-8', errors='surrogateescape')
        hit = fired(check(), needle)
    finally:
        path.write_text(original, encoding='utf-8', errors='surrogateescape')
    verdict = 'caught' if hit else 'clean'
    return ('PASS' if hit == expect else 'FAIL', tag, verdict)


def first_source(port):
    spec = ISO.SOURCES[port]
    for glob in spec['globs']:
        for path in sorted(ROOT.glob(glob)):
            rel = path.relative_to(ROOT).as_posix()
            if not any(rel.startswith(s) for s in spec['skip']):
                return rel
    return None


def main():
    results = []

    for port, rel, anchor, repl in MANIFEST:
        results.append(mutate(rel, anchor, repl, f'{port}: ', True, f'{port}:manifest'))

    for port, rel, anchor, repl, why in EXEMPT:
        results.append(mutate(rel, anchor, repl, f'{port}: ', False,
                              f'{port}:exempt ({why})'))

    for port in sorted(ISO.SOURCES):
        rel = first_source(port)
        if rel is None:
            results.append(('FAIL', f'{port}:source',
                            'no shipped source file matched - the glob is dead'))
            continue
        results.append(mutate(rel, '', LEAK,
                              f'{port}: shipped source imports omni',
                              True, f'{port}:source'))

    for status, tag, note in results:
        print(f'{status}  {tag:52} {note}')

    bad = [r for r in results if 'PASS' != r[0]]
    print(f'\n{len(results) - len(bad)}/{len(results)} mutations produced the expected verdict')
    if bad:
        print('\nthe 4.13 guard did not catch what it must:', file=sys.stderr)
        for status, tag, note in bad:
            print(f'  {tag}: {note}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
