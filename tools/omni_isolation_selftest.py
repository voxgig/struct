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
# NOT a comment. Whole-line comments are skipped by the scanner now that it
# shares the manifest matcher, so a `//`-prefixed marker would be silently
# ignored and every source mutation would pass while testing nothing.
LEAK = 'LEAK voxgig_omni VoxgigOmni Omni voxgig.omni voxgig/omni omni\n'

# The module spelling that actually appears in code. `\bomni\b` could not match
# `voxgig_omni` - `_` is a word character, so there is no boundary - and that is
# exactly what Python and Rust import. The old marker carried a standalone
# `omni`, so every source mutation passed while this spelling went unchecked.
SOURCE_SPELLINGS = 'import voxgig_omni\nuse voxgig_omni::Runner;\n'

# `#include "voxgig/omni.h"` is CODE. The comment skip classified every `#`
# line as prose, which made it invisible in c and cpp - ports with no manifest,
# so the source scan is the only check they get.
PREPROCESSOR = '#include "voxgig/omni.h"\n'

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

    # THE FIVE EVASIONS Codex found on the sekreto copy of this tool.
    # A block-form `replace` redirecting an innocuous module to omni; the old
    # parser recorded the literal `replace (` and ignored everything inside.
    ('go', 'go/go.mod', 'go 1.23',
     'go 1.23\n\nrequire innocent/pkg v1.0.0\n\nreplace (\n\tinnocent/pkg => github.com/voxgig/omni/go v0.0.0\n)'),
    # Single-quoted XML, valid, and read as no dependency at all.
    ('csharp', 'csharp/VoxgigStruct.csproj', '</Project>',
     "<ItemGroup><PackageReference Include='Voxgig.Omni' Version='0.1.0' /></ItemGroup></Project>"),
    # Cargo workspace inheritance: the real crate is named in
    # [workspace.dependencies], which a package-level read never sees.
    ('rust', 'rust/Cargo.toml', '[lib]',
     '[dependencies]\nrunner = { workspace = true }\n\n[workspace.dependencies]\nrunner = { package = "voxgig_omni", version = "0.1" }\n\n[lib]'),

    # EVASIONS. Each of these declares omni in a way that reads clean to a
    # naive check, and every one was a live hole in the first version.
    # A rename: the key says `runner`, and shipped code can import `runner`
    # too, so the source scan does not compensate.
    ('rust', 'rust/Cargo.toml', '[lib]',
     '[dependencies]\nrunner = { package = "voxgig_omni", version = "0.1" }\n\n[lib]'),
    # An npm alias: same shape, same blind spot.
    ('typescript', 'typescript/package.json', '"devDependencies": {',
     '"dependencies": { "runner": "npm:@voxgig/omni@1.0.0" },\n  "devDependencies": {'),
    # A Maven profile that turns ITSELF on, so it reaches the effective model
    # a consumer resolves. Only activation-free profiles are exempt.
    ('java', 'java/pom.xml', '<profiles>',
     '<profiles><profile><id>auto</id><activation><activeByDefault>true'
     '</activeByDefault></activation><dependencies><dependency>'
     '<groupId>com.voxgig</groupId><artifactId>omni</artifactId>'
     '</dependency></dependencies></profile>'),
    # Gradle's SECOND dependencies block, on a published configuration.
    # `re.search` read only the first and called the file clean.
    ('kotlin', 'kotlin/build.gradle.kts', 'dependencies {\n    testImplementation(omni.output)',
     'dependencies {\n    implementation("com.voxgig:omni:0.1.0")\n    testImplementation(omni.output)'),
    # Dependencies declared dynamic and sourced from a file this cannot read:
    # must fail, not pass over.
    ('python', 'python/pyproject.toml', '[project]',
     '[project]\ndynamic = ["dependencies"]'),
    # Swift with the gate deleted: unconditional, and unevaluatable for a
    # consumer with no symlink.
    ('swift', 'swift/Package.swift', 'dependencies: nil == omniPath ? [] : [',
     'dependencies: [', ),
    # An ungated `.package(` CONCATENATED with the gated array: the gate is
    # still present, so "a gate exists somewhere" passed it.
    ('swift', 'swift/Package.swift', 'dependencies: nil == omniPath',
     'dependencies: [.package(name: "Evil", path: "../omni/swift")] + (nil == omniPath'),
    # A nested `.product(...)` in a library target - unmatchable after a
    # `[^(]` guard was added to stop one `.target(` running into the next.
    ('swift', 'swift/Package.swift',
     '.target(name: "VoxgigStruct", path: "Sources/VoxgigStruct")',
     '.target(name: "VoxgigStruct", dependencies: [.product(name: "Omni", package: "VoxgigOmni")], path: "Sources/VoxgigStruct")'),
]

# Blocks that may name omni. The checker must NOT fire on these.
EXEMPT = [
    # Into the EXISTING object, not a second top-level key. A duplicate
    # `devDependencies` is silently discarded by json.loads (last wins), so
    # the first version of this mutation reported "clean" while the injected
    # entry was never parsed - an exemption test that tested nothing.
    ('typescript', 'typescript/package.json', '"devDependencies": {',
     '"devDependencies": {\n    "@voxgig/omni": "^0.1.1",',
     'npm devDependencies are never installed transitively'),
    ('php', 'php/composer.json', '"require-dev": {',
     '"require-dev": { "voxgig/omni": "^0.1",',
     "Composer never installs a dependency's require-dev"),
    # java's ACTUAL mechanism, and the reason read_pom scopes rather than
    # greps: pom.xml names omni ten times today, all inside <profiles>.
    ('java', 'java/pom.xml', '<profiles>',
     '<profiles><profile><id>leak</id><dependencies><dependency>'
     '<groupId>com.voxgig</groupId><artifactId>omni</artifactId>'
     '</dependency></dependencies></profile>',
     'a -Pomni profile is invisible to a resolver and to static scanners'),
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
        # And again with ONLY the ecosystem module spelling, no standalone
        # `omni` anywhere in the marker.
        results.append(mutate(rel, '', SOURCE_SPELLINGS,
                              f'{port}: shipped source imports omni',
                              True, f'{port}:source-spelling'))
        if port in ('c', 'cpp'):
            results.append(mutate(rel, '', PREPROCESSOR,
                                  f'{port}: shipped source imports omni',
                                  True, f'{port}:source-include'))

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
