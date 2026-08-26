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
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Matches the ways omni is spelled across ecosystems: the npm scope
# (@voxgig/omni, @voxgig/omni-js), the Go module path, the Maven coordinate,
# the crate/gem/pub name (voxgig_omni, voxgig-omni), CONCATENATED CamelCase
# (VoxgigOmni, which is how SwiftPM names the package) and a bare "omni" used
# as a component name.
#
# The separator is optional on purpose. It was mandatory at first, and that
# missed `.package(name: "VoxgigOmni", path: omniPath!)` entirely - the exact
# line a swift leak consists of. `omniPath` is still NOT matched, and should
# not be: it is a local variable, not a dependency.
OMNI = re.compile(r'(^|[^a-z0-9])(@?voxgig[/_.-]?omni|omni)([^a-z0-9]|$)', re.I)


def names_omni(text):
    return bool(OMNI.search(text or ''))


# THE SPELLING THAT ACTUALLY APPEARS IN CODE.
#
# Every port's source pattern used to be hand-written, and most were
# `\bomni\b` - which cannot match `voxgig_omni`, because `_` is a word
# character so there is no boundary before `omni`. That is the exact module
# name Python and Rust import, so the guard would have read
# `import voxgig_omni` in a shipped file and called it clean.
#
# The mutation suite did not catch it either: the injected marker happened to
# contain a standalone `omni`. Mutation testing proves what you thought to
# mutate, and this was not thought of.
#
# One matcher now, shared with the manifest side, so the two cannot drift.
SOURCE = OMNI


# A WHOLE-LINE comment is skipped; a trailing one is not. Sharing the matcher
# above means prose about omni now matches too, and these repos discuss it
# constantly - scanning comments is how a guard trains people to ignore it.
# Deliberately narrow: only a line whose FIRST non-space characters are a
# comment marker, so a real reference with a trailing comment is still read.
COMMENT = re.compile(r'^\s*(//|#|--|\*|/\*|"""|\'\'\')')

# `#` OPENS A COMMENT IN SOME LANGUAGES AND A PREPROCESSOR DIRECTIVE IN OTHERS.
# Treating every `#` line as prose made `#include "voxgig/omni.h"` invisible -
# in c and cpp, which have NO manifest, so the source scan is the only check
# they get. A regression introduced by the comment skip itself.
#
# Listed rather than keyed on file type, and erring towards CODE: a prose line
# that happens to start `# if you want to...` is scanned, which is the safe
# direction. Missing a directive is not.
DIRECTIVE = re.compile(
    r'^\s*#\s*(include|import|define|pragma|if|ifdef|ifndef|elif|else|endif|'
    r'undef|error|warning|line)\b', re.I)


def is_comment(line):
    if DIRECTIVE.match(line):
        return False
    return bool(COMMENT.match(line))



# A dynamic dependency list this cannot resolve must FAIL, not pass quietly -
# it is precisely the case where omni could be declared and unseen. The string
# names omni so it trips the same matcher every other finding does.
DYNAMIC_UNRESOLVED = ('<dynamic dependencies with no resolvable source: '
                      'omni cannot be ruled out here>')


def _aslist(value):
    if value is None:
        return []
    return [value] if isinstance(value, str) else list(value)


# ---------------------------------------------------------------------------
# Per-format readers.  Each returns a list of DECLARED dependency strings for
# the LIBRARY only - the test/harness half of a manifest is skipped, because
# a harness naming omni is the whole point.
# ---------------------------------------------------------------------------

def read_go_mod(path):
    """go.mod: every module path in a require, replace or exclude.

    ALL THREE HAVE A BLOCK FORM. Handling `require (` alone recorded the
    literal `replace (` and ignored every entry inside it, so an innocuously
    named module redirected to omni - `innocent/pkg => github.com/voxgig/omni/go`
    - read clean.
    """
    deps, block = [], None
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.split('//')[0].strip()
        if not line:
            continue
        if block is not None:
            if line == ')':
                block = None
            else:
                # A replace line is `old => new`; both sides matter.
                deps.append(line)
            continue
        for kw in ('require', 'replace', 'exclude'):
            if line == f'{kw} (' or line.startswith(f'{kw} ('):
                block = kw
                break
        else:
            for kw in ('require ', 'replace ', 'exclude '):
                if line.startswith(kw):
                    deps.append(line[len(kw):])
                    break
    return deps


def read_cargo(path):
    """Cargo.toml: dependencies AND dev-dependencies, keys, `package`, and
    anything inherited from `[workspace.dependencies]`.

    dev-dependencies are not exempt the way npm devDependencies are: Cargo
    resolves them even for a plain `cargo build`, which is why the conformance
    harness is a separate package.

    Three spellings hide the real crate. `runner = { package = "voxgig_omni" }`
    renames it, so the key says `runner` and code imports `runner`.
    `runner = { workspace = true }` moves the real declaration into
    `[workspace.dependencies]`, which a package-level read never sees. And a
    `[target.*]` block repeats both.
    """
    data = tomllib.loads(path.read_text(encoding='utf-8'))
    wsdeps = ((data.get('workspace') or {}).get('dependencies') or {})

    def entries(block):
        for name, spec in (block or {}).items():
            yield name
            if not isinstance(spec, dict):
                continue
            if spec.get('package'):
                yield spec['package']
            if spec.get('workspace'):
                inherited = wsdeps.get(name)
                if isinstance(inherited, dict):
                    yield inherited.get('package') or name
                    if inherited.get('git'):
                        yield str(inherited['git'])
                    if inherited.get('path'):
                        yield str(inherited['path'])
                elif isinstance(inherited, str):
                    yield inherited
            for key in ('path', 'git'):
                if spec.get(key):
                    yield str(spec[key])

    deps = []
    for block in ('dependencies', 'dev-dependencies', 'build-dependencies'):
        deps.extend(entries(data.get(block)))
    deps.extend(entries(wsdeps))
    for tgt in (data.get('target') or {}).values():
        for block in ('dependencies', 'dev-dependencies', 'build-dependencies'):
            deps.extend(entries(tgt.get(block)))
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
        for name, spec in (data.get(block) or {}).items():
            # The key AND the value. `"runner": "npm:@voxgig/omni@1.0.0"` is
            # an npm alias: the key says `runner`, shipped code imports
            # `runner`, and the consumer still resolves omni.
            deps.append(name)
            if isinstance(spec, str):
                deps.append(spec)
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
    """pyproject.toml, including DYNAMIC dependency declarations.

    `dynamic = ["dependencies"]` moves the real list out of this file - with
    setuptools, into whatever `[tool.setuptools.dynamic]` points at.  Reading
    only the static keys would see nothing while an omni requirement became
    published `Requires-Dist` metadata that consumers install.  So the
    referenced files are read too, and a dynamic declaration this cannot
    resolve is REPORTED rather than passed over.
    """
    data = tomllib.loads(path.read_text(encoding='utf-8'))
    proj = data.get('project') or {}
    deps = list(proj.get('dependencies') or [])
    for group in (proj.get('optional-dependencies') or {}).values():
        deps.extend(group)
    deps.extend((data.get('build-system') or {}).get('requires') or [])

    dynamic = set(proj.get('dynamic') or [])
    if dynamic & {'dependencies', 'optional-dependencies'}:
        cfg = ((data.get('tool') or {}).get('setuptools') or {}).get('dynamic') or {}
        targets = []
        for key in ('dependencies', 'optional-dependencies'):
            spec = cfg.get(key)
            if not isinstance(spec, dict):
                continue
            if 'file' in spec:                       # dependencies = {file = [...]}
                targets.extend(_aslist(spec['file']))
            else:                                    # optional-dependencies = {grp = {file=..}}
                for group in spec.values():
                    if isinstance(group, dict):
                        targets.extend(_aslist(group.get('file')))
        if not targets:
            deps.append(DYNAMIC_UNRESOLVED)
        for rel in targets:
            ref = path.parent / rel
            deps.extend(ref.read_text(encoding='utf-8').splitlines()
                        if ref.exists() else [DYNAMIC_UNRESOLVED])
    return deps


# NO XML PARSER, DELIBERATELY.  `xml.etree.ElementTree` is what this wanted,
# and semgrep blocks it repo-wide
# (python.lang.security.use-defused-xml.use-defused-xml): the stdlib parser is
# vulnerable to entity expansion, and `defusedxml` is the recommended fix.
# Taking that fix would mean a new dependency, which AGENTS.md forbids, for a
# threat that does not exist here - these two files are committed repo content,
# not input.  Rather than argue the exemption in a suppression comment, both
# readers below scope textually, the same technique already used for the
# formats with no stdlib parser at all.  It costs nothing: neither reader
# needed the tree, only the region.

def read_pom(path):
    """pom.xml: dependency coordinates OUTSIDE any <profiles> block.

    struct/java keeps omni behind a `-Pomni` profile precisely so it is
    invisible to a consumer's resolver and to static scanners, so that profile
    is exempt and the default model is not.  The exemption is live, not
    theoretical: java/pom.xml names omni ten times today, every one of them
    inside <profiles>.  A whole-file grep would fail on the correct tree.

    But the exemption is narrow.  Only a profile with NO <activation> is
    dropped, because that is the kind Maven applies solely when named on the
    command line.  A profile carrying activeByDefault, or a jdk/os/property
    condition, can turn itself on in a consumer's build, so it is checked like
    any other dependency.  Both of this pom's profiles (omni, release) are
    activation-free today; the distinction is here so that stays true.
    """
    text = path.read_text(encoding='utf-8')

    # Drop only the profiles that CANNOT participate in the effective model a
    # consumer resolves - i.e. those with no <activation> block, which Maven
    # applies only when named explicitly (`-Pomni`). A profile carrying
    # activeByDefault, or a jdk/os/property condition, CAN activate on its
    # own, so its dependencies stay in scope and are checked like any other.
    def droppable(match):
        return '' if not re.search(r'<activation>', match.group(0), re.I) else match.group(0)

    text = re.sub(r'<profile>.*?</profile>', droppable, text, flags=re.S | re.I)
    deps = []
    for dep in re.finditer(r'<dependency>(.*?)</dependency>', text, re.S | re.I):
        body = dep.group(1)
        gid = re.search(r'<groupId>(.*?)</groupId>', body, re.S | re.I)
        aid = re.search(r'<artifactId>(.*?)</artifactId>', body, re.S | re.I)
        deps.append('{}:{}'.format(gid.group(1).strip() if gid else '',
                                   aid.group(1).strip() if aid else ''))
    return deps


def read_csproj(path):
    """A .csproj: the Include/Update of every Package/ProjectReference.

    BOTH XML QUOTE STYLES. A double-quote-only pattern returned nothing at all
    for `Include='Voxgig.Omni'`, which is valid XML, and a package reference
    resolves whether or not any source file imports its namespace - so the
    source scan does not close that hole."""
    text = path.read_text(encoding='utf-8')
    return [m.group(1) or m.group(2) for m in re.finditer(
        r'<(?:Package|Project)Reference\b[^>]*?\b(?:Include|Update)\s*='
        r'\s*(?:"([^"]*)"|\'([^\']*)\')',
        text, re.I)]


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


def _balanced(text, open_at):
    """The substring from `open_at` (an index of `(`) to its matching `)`.

    A regex cannot do this. `.target(...)` legitimately contains nested calls -
    `.product(name: "Omni", package: "VoxgigOmni")` is the normal way a target
    declares a dependency - and an earlier `[^(]` guard, added to stop one
    `.target(` running on into the next, made exactly that nesting
    unmatchable. Count instead.
    """
    depth = 0
    for i in range(open_at, len(text)):
        if '(' == text[i]:
            depth += 1
        elif ')' == text[i]:
            depth -= 1
            if 0 == depth:
                return text[open_at + 1:i]
    return text[open_at + 1:]


def read_swift(path):
    """Package.swift, structurally - it is a PROGRAM, not a data file.

    This manifest legitimately names omni many times: it declares the
    dependency only when a gitignored symlink exists, and only for the TEST
    target.  A grep would fail on the correct tree.

    PACKAGE-LEVEL: strip the gated ternary, then assert nothing is left. Not
    "a gate exists somewhere in the region" - that passed an unconditional
    declaration CONCATENATED with the gated array, which still contains the
    gate. What must be true is that every `.package(` is inside the gate, and
    removing the gate and finding none left is how to say so.

    TARGETS: every non-test target, read to its matching paren so nested
    calls are visible.
    """
    text = path.read_text(encoding='utf-8')
    fails = []

    m = re.search(r'\n\s*dependencies:\s*(.*?)(?=\n\s*targets:)', text, re.S)
    if m:
        region = m.group(1)
        # Remove `<nil-check> ? [] : [ ... ]` in full, however spelled.
        stripped = re.sub(
            r'(nil\s*==\s*\w*[Oo]mni\w*|\w*[Oo]mni\w*\s*==\s*nil)'
            r'\s*\?\s*\[\s*\]\s*:\s*\[.*?\]',
            '', region, flags=re.S)
        if '.package(' in stripped:
            fails.append('package dependencies declare `.package(` outside the '
                         'nil-check gate: ' + ' '.join(stripped.split())[:70])

    for tm in re.finditer(r'\.(target|executableTarget)\(', text):
        body = _balanced(text, tm.end() - 1)
        if names_omni(body):
            fails.append(f'.{tm.group(1)} declares omni: '
                         + ' '.join(body.split())[:70])
    return fails


def read_scoped(path, start, stop=None, exempt=None, comment=None):
    """Read the dependency-declaring REGION of a manifest with no stdlib
    parser (cabal, opam, gemspec, rockspec, gradle.kts, mix.exs, deps.edn,
    Makefile.PL, build.zig.zon, pubspec.yaml).

    `exempt` drops lines matching a pattern, for the declarations a format
    scopes to tests the way npm scopes devDependencies.  It must stay NARROW:
    the only use is Gradle's test configurations, which Gradle never publishes
    to a consumer.

    `comment` strips comment text before anything else, and it is not a
    nicety: a comment can also open a scope by accident.  clojure's start
    pattern is `:deps\b`, and a comment ABOVE the map explaining
    `:deps/root "clojure"` matched it - so the scan began inside prose and
    read the word omni out of an explanation of why omni is NOT declared
    there.  Measured, not hypothetical.  It strips by line, so a `;` inside a
    string would be cut too; no manifest here has one, and a parse is the
    real answer if one ever does.

    This is a scoped textual scan, and saying so plainly matters: it is
    weaker than a parse and it is what is available without adding a runtime
    dependency, which AGENTS.md forbids.  It is scoped rather than a whole
    file grep so that a comment or a harness stanza naming omni - which every
    one of these manifests is entitled to do - cannot false-positive.
    """
    text = path.read_text(encoding='utf-8')
    if comment:
        text = re.sub(comment, '', text, flags=re.M)
    lines = []
    # EVERY region, not the first. Gradle allows several `dependencies { }`
    # blocks and kotlin/build.gradle.kts already has two, so `re.search` read
    # one and declared the file clean on the strength of it.
    for m in re.finditer(start, text, re.I | re.M):
        tail = text[m.end():]
        if stop:
            e = re.search(stop, tail, re.I | re.M)
            if e:
                tail = tail[:e.start()]
        lines.extend(line for line in tail.splitlines() if line.strip())
    if exempt:
        rx = re.compile(exempt, re.I)
        lines = [line for line in lines if not rx.search(line)]
    return lines


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
                   pattern=SOURCE),
    'rust':   dict(globs=['rust/src/**/*.rs'], skip=[], pattern=SOURCE),
    'java':   dict(globs=['java/src/**/*.java'], skip=['java/src/test/'],
                   pattern=SOURCE),
    'kotlin': dict(globs=['kotlin/src/main/**/*.kt'], skip=[], pattern=SOURCE),
    'csharp': dict(globs=['csharp/*.cs'], skip=[], pattern=SOURCE),
    'swift':  dict(globs=['swift/Sources/**/*.swift'], skip=[], pattern=SOURCE),
    'haskell': dict(globs=['haskell/src/**/*.hs'], skip=[], pattern=SOURCE),
    'python': dict(globs=['python/voxgig_struct/**/*.py'], skip=[], pattern=SOURCE),
    'ruby':   dict(globs=['ruby/voxgig_struct.rb'], skip=[], pattern=SOURCE),
    'php':    dict(globs=['php/src/**/*.php'], skip=[], pattern=SOURCE),
    'dart':   dict(globs=['dart/lib/**/*.dart'], skip=[], pattern=SOURCE),
    'elixir': dict(globs=['elixir/lib/**/*.ex'], skip=[], pattern=SOURCE),
    'lua':    dict(globs=['lua/src/**/*.lua'], skip=[], pattern=SOURCE),
    'clojure': dict(globs=['clojure/src/**/*.clj*'], skip=[], pattern=SOURCE),
    'scala':  dict(globs=['scala/src/**/*.scala'], skip=[], pattern=SOURCE),
    'c':      dict(globs=['c/src/**/*.[ch]'], skip=[], pattern=SOURCE),
    'cpp':    dict(globs=['cpp/src/**/*.[ch]pp', 'cpp/src/**/*.h'], skip=[],
                   pattern=SOURCE),
    'ocaml':  dict(globs=['ocaml/src/**/*.ml*'], skip=[], pattern=SOURCE),
    'perl':   dict(globs=['perl/lib/**/*.pm'], skip=[], pattern=SOURCE),
    'lean':   dict(globs=['lean/src/**/*.lean'], skip=[], pattern=SOURCE),
    'typescript': dict(globs=['typescript/src/**/*.ts'], skip=[], pattern=SOURCE),
    # Not migrated, and with no manifest - but its SOURCE still ships, so it
    # is scanned like any other. A port absent from this table is a port
    # nothing checks, which is how boru was missed the first time.
    'boru':       dict(globs=['boru/src/**/*.boru'], skip=[], pattern=SOURCE),
    # zig had a PORTS entry and no SOURCES entry, so its shipped source was
    # never read - found the moment the union check became a both-tables
    # check. Not migrated onto omni, but its source ships regardless.
    'zig':        dict(globs=['zig/src/**/*.zig'], skip=[], pattern=SOURCE),
    'javascript': dict(globs=['javascript/src/**/*.js'], skip=[], pattern=SOURCE),
}


def scan_sources(port):
    spec = SOURCES.get(port)
    if not spec:
        return [], 0
    rx = spec['pattern']
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
                if is_comment(line):
                    continue
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
                             lambda p: read_scoped(p, r'(\bdeps:\s*|defp\s+deps\b)',
                                                   r'^\s*end\b'))]),
    # `testImplementation`/`testRuntimeOnly`/`testCompileOnly` are Gradle's
    # test configurations and are never published to a consumer - kotlin's
    # equivalent of npm devDependencies, and how this port declares omni
    # (`testImplementation(omni.output)`, from its own source set). Every
    # other configuration - implementation, api, compileOnly, runtimeOnly - is
    # in scope.
    'kotlin':     dict(lib=[('kotlin/build.gradle.kts',
                             lambda p: read_scoped(
                                 p, r'^\s*dependencies\s*\{', r'^\}',
                                 exempt=r'^\s*test(Implementation|RuntimeOnly|CompileOnly)\b'))]),
    # `comment=';.*$'`: EDN comments are stripped first, because one of them
    # opened the scope - see read_scoped.
    'clojure':    dict(lib=[('clojure/deps.edn',
                             lambda p: read_scoped(p, r':deps\b', r':aliases\b',
                                                   comment=r';.*$'))]),
    'dart':       dict(lib=[('dart/pubspec.yaml',
                             lambda p: read_scoped(p, r'^dependencies:', r'^dev_dependencies:'))]),
    'perl':       dict(lib=[('perl/Makefile.PL',
                             lambda p: read_scoped(p, r'WriteMakefile'))]),

    # No manifest of any kind - reported, never silently passed.
    'c':          dict(lib=[], why='header/source tree, no manifest a consumer resolves'),
    'cpp':        dict(lib=[], why='header-only, no manifest a consumer resolves'),
    'scala':      dict(lib=[], why='no build file at all - scala-cli argument lists in the Makefile'),
    # Both run on omni now, and neither declares it anywhere a consumer
    # could resolve: zig takes the checkout through a `-Domni` build option
    # the Makefile sets, boru through a gitignored `.omni-runner` symlink the
    # Makefile creates. build.zig.zon and the boru source tree name omni in
    # no way at all, which is what leaves them UNCOVERED here - there is no
    # declaration to check, only an absence, and this file exists because an
    # absence is the weaker proof.
    'zig':        dict(lib=[], why='omni arrives as a -Domni build option, not a '
                                   'build.zig.zon dependency'),
    'boru':       dict(lib=[], why='no manifest a consumer resolves; omni arrives '
                                   'as a Makefile-made symlink the library never '
                                   'imports'),
}


def discover_ports():
    """Every port directory in the repo, found rather than listed.

    A port carries an AGENTS.md and a Makefile; that pair is what
    distinguishes one from `tools/`, `build/` and the rest. Discovering them
    is the point: `boru` was absent from both tables in the first version of
    this file, so its source was never read and the output still said
    everything was clean. A port this file does not know about is a port
    nothing checks, and that must be loud.
    """
    found = set()
    for entry in ROOT.iterdir():
        if not entry.is_dir() or entry.name.startswith('.'):
            continue
        if not (entry / 'AGENTS.md').exists():
            continue
        if not any((entry / n).exists() for n in ('Makefile', 'makefile')):
            continue
        found.add(entry.name)
    return found


def main():
    fails, uncovered, checked = [], [], []

    # Coverage first: no port may be absent from both tables.
    # BOTH tables, not their union. A port listed in only one is still
    # "known", so neither check fires while half its scanning is silently
    # skipped - and the error for a wholly new port said only to add "an
    # entry", which invites exactly that. A port with no manifest declares
    # `lib=[]` explicitly; there is no opting out of SOURCES.
    ports = discover_ports()
    for port in sorted(ports - set(PORTS)):
        fails.append(f'{port}: is a port directory with no PORTS entry - its '
                     'manifests are unchecked; add one (lib=[] with a `why` if '
                     'it has no manifest a consumer resolves)')
    for port in sorted(ports - set(SOURCES)):
        fails.append(f'{port}: is a port directory with no SOURCES entry - its '
                     'shipped source is unscanned; add one')
    for port in sorted((set(PORTS) | set(SOURCES)) - ports):
        fails.append(f'{port}: has an entry here but is not a port directory - '
                     'stale, and its checks read nothing')

    # An UNCOVERED port must still BE uncovered. `lib=[]` prints a reason
    # forever, so a port that later gains a real manifest - a pom.xml, a
    # gemspec - would keep printing it while an omni declaration in that new
    # manifest sailed through. Discovery already counts the port as known, so
    # nothing else would notice.
    MANIFEST_NAMES = ('go.mod', 'Cargo.toml', 'pom.xml', 'build.gradle',
                      'build.gradle.kts', 'deps.edn', 'pubspec.yaml', 'mix.exs',
                      'composer.json', 'pyproject.toml', 'setup.py',
                      'Package.swift', 'lakefile.toml', 'Makefile.PL',
                      'package.json')
    for port in sorted(PORTS):
        if PORTS[port]['lib']:
            continue
        found = [n for n in MANIFEST_NAMES if (ROOT / port / n).exists()]
        found += [q.name for q in (ROOT / port).glob('*.csproj')]
        found += [q.name for q in (ROOT / port).glob('*.gemspec')]
        if found:
            fails.append(f'{port}: is declared UNCOVERED ("{PORTS[port].get("why")}") '
                         f'but now has {", ".join(sorted(set(found)))} - give it a '
                         'real PORTS entry')

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

    # A SKIP MUST BE JUSTIFIED BY SOMETHING THIS FILE CHECKS, and derived
    # rather than hard-coded, so it stays true per repo.
    #
    # A port keeps its OMNI_HOME resolver out of the package with a `files`
    # negation, and SOURCES skips that path on that basis. Drop the negation
    # and the resolver ships again while the scan still looks away - the skip
    # would assert a fact nothing verified. python had exactly this shape and
    # no exclusion at all, which is how omnihome.py reached PyPI.
    #
    # A skip matching NO file is reported too: it is the same
    # silence-looks-like-success failure as a dead glob, and a skip copied
    # between repos is how one arrives.
    for port in sorted(SOURCES):
        for prefix in SOURCES[port]['skip']:
            matched = sorted(ROOT.glob(prefix + '*'))
            if not matched:
                fails.append(f'{port}: SOURCES skips {prefix!r} and nothing '
                             'matches it - a dead skip; remove it')
                continue
            manifest = ROOT / port / 'package.json'
            if not manifest.exists():
                continue
            files = json.loads(manifest.read_text(encoding='utf-8')).get('files')
            if not files:
                continue
            rel = prefix.split('/', 1)[1] if '/' in prefix else prefix
            if not any(f.startswith('!') and f.lstrip('!').startswith(rel.split('/')[0] + '/')
                       and rel.rsplit('/', 1)[-1] in f
                       for f in files):
                fails.append(f'{port}: package.json `files` no longer excludes '
                             f'{rel!r}, but SOURCES still skips it - the file '
                             'would ship unscanned')

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
