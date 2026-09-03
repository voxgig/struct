#!/usr/bin/env python3
"""The second prose gate: the rules Vale cannot express.

Vale carries Google's rules and the banned list (see `.vale.ini`). This
carries the five house rules that need to know something Vale does not:
which pages are which, where a section boundary falls, and where a
paragraph ends.

    banned-phrases          reject.txt, matched across a line wrap
    em-dashes-are-spaced    the house convention Google rules the other way
    em-dashes-are-rationed  one aside per line
    we-appears-only-in-tutorials
    first-person-singular   stricter than Google's rule
    no-emoji
    internal-documents      documentation never cites a working document
    relative-links-resolve  a link's target exists, inside the repository
    page-set-is-complete    every port carries both required pages

Run it directly, or `make scan-prose`. `--files` prints the page set both
gates read, so the Vale invocation and this one cannot drift apart.

Every rule here exists because `.vale.ini` switches a Google rule off in
its favour, or because Google has no rule for it. A rule switched off in
favour of a house rule that is not real is worse than no rule at all --
upstream (voxgig/jostraca, whose gate this is a port of) records finding
exactly that, twice.

Usage:
    python3 tools/check_prose.py            # gate the reader-facing pages
    python3 tools/check_prose.py --files    # print the page set, one per line
    python3 tools/check_prose.py a.md b.md  # gate named pages instead
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

REJECT_FILE = (ROOT / ".vale" / "styles" / "config" / "vocabularies"
               / "Struct" / "reject.txt")

STYLE_GUIDE = ROOT / "STYLE-GUIDE.md"


# ---------------------------------------------------------------------
# The page set.
#
# Reader-facing means: the root README.md and DOCS.md, and each port's
# README.md and DOCS.md. That is what a reader lands on from GitHub, npm,
# crates.io, pkg.go.dev and the rest.
#
# design/ is NOT in it. It holds the cross-port specifications, which are
# normative and freely citable, and the working documents, which are not;
# neither is an authored page. build/ and test/ are harness documentation.
# AGENTS.md and CLAUDE.md are instructions to contributors and agents.
#
# STYLE-GUIDE.md is exempt for the reason upstream gives: it quotes the
# banned phrases in order to ban them, and names the internal documents in
# order to ban citations of them.
#
# patch/ is not in it either. It is a TRANSIENT delivery folder -- a change
# an agent session could not push, because `.github/workflows/` is refused
# to it, handed over as a `git format-patch` file (AGENTS.md, "Repository
# map"). Its README is an apply note for whoever lands the patch, not an
# authored page: it names the working documents the patch edits, which the
# citation rule forbids a page from doing, and it has no DOCS.md companion
# because there is nothing to write one about. Without this the gate reads
# the folder as a port and demands both pages of it.
# ---------------------------------------------------------------------

NOT_PORTS = ("build", "test", "design", "tools", "patch", "node_modules")

REQUIRED = ("README.md", "DOCS.md")


def port_dirs() -> list[Path]:
    """Directories that carry at least one of the two required pages."""
    out = []
    for child in sorted(ROOT.iterdir()):
        if not child.is_dir() or child.name.startswith("."):
            continue
        if child.name in NOT_PORTS:
            continue
        if any((child / name).is_file() for name in REQUIRED):
            out.append(child)
    return out


def pages() -> list[Path]:
    found = [ROOT / name for name in REQUIRED]
    for child in port_dirs():
        found += [child / name for name in REQUIRED]
    return [p for p in found if p.is_file()]


def check_page_set() -> list[str]:
    """EXISTENCE IS NOT MEMBERSHIP. `pages()` can only return files that
    are there, so deleting one used to shrink the set silently -- both
    gates would report on 49 pages and pass, and nothing said the fiftieth
    had stopped being read. Every port carries BOTH pages, so ask for both
    and fail on the gap rather than absorbing it.

    A directory carrying neither is not a port and is not missed; that is
    why the rule is written as both-or-neither rather than a hardcoded
    list, which would itself go stale when a port is added.
    """
    hits = []
    for name in REQUIRED:
        if not (ROOT / name).is_file():
            hits.append(f"missing required page: {name}")
    for child in port_dirs():
        for name in REQUIRED:
            if not (child / name).is_file():
                hits.append(
                    f"missing required page: {child.name}/{name} "
                    f"(the directory carries the other one)")
    return hits


def label(path: Path) -> str:
    """Repo-relative where possible; a path named on the command line may
    sit outside the tree (a scratch file being probed), and reporting it
    should not be a crash."""
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


# ---------------------------------------------------------------------
# Text handling.
# ---------------------------------------------------------------------

FENCE_OPEN = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")


def lf(text: str) -> str:
    """Line endings are the checkout's business, not this file's."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def fenceless(md: str) -> str:
    """Fenced blocks BLANKED rather than dropped, so a reported line
    number still matches the file. Inline code spans are kept: `AGENTS.md`
    in a sentence is the citation being banned, not an incidental token.
    """
    lines = lf(md).split("\n")
    out = list(lines)
    i = 0
    while i < len(lines):
        match = FENCE_OPEN.match(lines[i])
        if not match:
            i += 1
            continue
        marker = match.group(1)
        out[i] = ""
        j = i + 1
        while j < len(lines) and not lines[j].lstrip().startswith(marker):
            out[j] = ""
            j += 1
        if j < len(lines):
            out[j] = ""
        i = j + 1
    return "\n".join(out)


# A code span may be broken by a line wrap. `ocamlc -I src` wrapped
# mid-span in ocaml/DOCS.md and the first-person rule then read the
# compiler's -I flag as the pronoun, which is the shape of false positive
# that gets a gate switched off.
#
# BALANCED RUNS, not single backticks. Markdown closes a span with a run of
# exactly as many backticks as opened it, which is how code containing a
# backtick is written -- ``{"`$FN`": f/v}`` in boru's pages, for one. A
# pattern matching one pair at a time strips the delimiters of such a span
# and leaves its CONTENTS in the prose stream, so ``my`` or ``quietly``
# would fail a gate for a word only ever shown as code. The lookarounds
# pin the run length; the bound keeps an unmatched backtick to a sentence
# rather than the rest of the file.
CODE_SPAN = re.compile(r"(?<!`)(`+)(?!`)(.{0,400}?)(?<!`)\1(?!`)", re.S)


# A link's DESTINATION is not prose: the reader never sees it. Left in, a
# perfectly ordinary URL with a path segment like /our/ or /mine trips the
# first-person rule, and one with /quietly trips the banned list -- a false
# positive on compliant copy, in the checks that .vale.ini switches
# Google.We and Google.FirstPerson off in favour of.
#
# The destination is blanked to spaces rather than removed, and the link
# TEXT is kept, so both the visible words and every character position
# survive. `check_links` reads fenceless() instead, which keeps the
# destinations it exists to resolve.
INLINE_LINK = re.compile(r"(\[[^\]]*\])(\([^)\n]*\)|\[[^\]]*\])")

LINK_DEF = re.compile(r"(?m)^(\s{0,3}\[[^\]]+\]:)(.*)$")


def _blank(match: re.Match, keep: int, blank: int) -> str:
    return match.group(keep) + " " * len(match.group(blank))


def prose(md: str) -> str:
    """Strip frontmatter, fenced blocks and inline code spans; what
    remains is prose.

    Spans are replaced by their own newlines rather than removed, so a
    reported line number still matches the file.
    """
    text = fenceless(md)
    text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S)
    text = CODE_SPAN.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    text = INLINE_LINK.sub(lambda m: _blank(m, 1, 2), text)
    return LINK_DEF.sub(lambda m: _blank(m, 1, 2), text)


class Para:
    """A paragraph joined for matching, with each piece's physical line
    kept so a hit can still name a line the reader can open."""

    __slots__ = ("text", "starts", "lines", "pieces")

    def __init__(self, pieces: list[tuple[int, str]]):
        self.pieces = [p for _, p in pieces]
        self.lines = [n for n, _ in pieces]
        self.starts = []
        at = 0
        for piece in self.pieces:
            self.starts.append(at)
            at += len(piece) + 1
        self.text = " ".join(self.pieces)

    def at(self, index: int) -> tuple[int, str]:
        k = 0
        for n, start in enumerate(self.starts):
            if start <= index:
                k = n
        return self.lines[k], self.pieces[k]


def paragraphs(text: str) -> list[Para]:
    """Markdown treats a newline inside a paragraph as whitespace, and
    these pages are hard-wrapped -- so "worth\\nnoting" is the ORDINARY
    shape of a multiword phrase here, not an exotic one. A gate matching
    physical lines would miss most of them, which makes wrapping a way
    through it.
    """
    out: list[Para] = []
    buf: list[tuple[int, str]] = []
    for i, line in enumerate(text.split("\n"), 1):
        if not line.strip():
            if buf:
                out.append(Para(buf))
                buf = []
            continue
        buf.append((i, re.sub(r"\s+", " ", line.strip())))
    if buf:
        out.append(Para(buf))
    return out


# ---------------------------------------------------------------------
# The banned list, read from the file Vale reads.
#
# Vale matches reject.txt entries case-insensitively on word boundaries;
# mirror exactly that, so a phrase cannot pass one gate and fail the
# other.
# ---------------------------------------------------------------------

def load_banned() -> list[tuple[re.Pattern, str]]:
    if not REJECT_FILE.is_file():
        sys.exit(f"missing banned list: {REJECT_FILE}")
    out = []
    for line in REJECT_FILE.read_text(encoding="utf-8").split("\n"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        out.append((re.compile(r"\b(?:%s)\b" % line, re.I), line))
    return out


# ---------------------------------------------------------------------
# Internal working documents.
#
# THE SET IS NARROWER THAN UPSTREAM'S, and the difference is this
# project's document taxonomy rather than a softer rule. jostraca's
# `docs/design/` holds plans and reviews only. This repository's `design/`
# holds two kinds of file:
#
#   SPECIFICATION, freely citable -- REGEX.md, REGEX_API.md,
#   REGEX_PATHOLOGICAL.md, UNDEF.md, UNDEF_SPEC.md, TESTSPEC_MODEL.md,
#   REPORT.md, NOTES.md. These are normative: the absent-vs-null rule and
#   the regex subset are defined there and nowhere else, and a port page
#   recording a deliberate divergence has to be able to point at the
#   record of it. They are the same exemption upstream grants source and
#   tests.
#
#   WORKING DOCUMENT, banned -- the assessments, the backport notes, the
#   doc-example plan, and anything matching the *_PLAN / *_REVIEW /
#   BUILD_LOG shapes that this project has not needed yet. Plus AGENTS.md
#   and CLAUDE.md, which instruct contributors and agents.
#
# The NAME is banned as well as the link: "the full checklist is in
# AGENTS.md" strands a reader exactly as the URL does.
# ---------------------------------------------------------------------

WORKING_DOCS = [
    (re.compile(r"\bAGENTS\.md\b"), "AGENTS.md"),
    (re.compile(r"\bCLAUDE\.md\b"), "CLAUDE.md"),
    (re.compile(r"\bDOC_EXAMPLES\.md\b"), "DOC_EXAMPLES.md"),
    (re.compile(r"\bTESTPROVIDER_ASSESSMENT\.md\b"),
     "TESTPROVIDER_ASSESSMENT.md"),
    (re.compile(r"\bSELECT_NULL_KEY_BACKPORT\.md\b"),
     "SELECT_NULL_KEY_BACKPORT.md"),
    (re.compile(r"\b[A-Z][A-Z0-9_]*_(?:PLAN|REVIEW)\.md\b"),
     "a plan or review file"),
    (re.compile(r"\bBUILD_LOG\.md\b"), "BUILD_LOG.md"),
    # The citation SHAPE, for a document named by description rather than
    # by filename. The bare noun is not a citation: "notes for AI coding
    # agents" describes the repository layout and sends nobody anywhere,
    # while "see the agent notes" leans on it as a source.
    (re.compile(r"\b(?:see|per|as|in) the (?:agent|contributor) "
                r"(?:notes|instructions|guide)\b", re.I),
     "an internal document, cited"),
    (re.compile(r"\bthe (?:agent|contributor) (?:notes|instructions|guide) "
                r"(?:explains?|notes?|records?|says?|covers?|lists?)\b", re.I),
     "an internal document, cited"),
]


# ---------------------------------------------------------------------
# The checks.
# ---------------------------------------------------------------------

EMOJI = re.compile(
    "[\U0001F300-\U0001FAFF☀-➿️⬀-⯿]")

# "I" is stricter than Google's rule and applies to every page. I/O is a
# word, not a pronoun; the negative lookahead keeps it.
FIRST_SINGULAR = re.compile(
    r"\bI(?!/O)\b|\bI'(?:m|ve|ll|d)\b|\b(?:my|mine|myself)\b")

FIRST_PLURAL = re.compile(
    r"\b(we|we'(?:ll|ve|re|d)|us|our|ours|let's)\b", re.I)

# Section 1 of a DOCS.md is the tutorial: it walks through code with the
# reader, and voice rule 7 allows "we" there and nowhere else. A README
# has no tutorial section.
TUTORIAL_HEAD = re.compile(r"^##\s*1\.\s", re.M)
SECTION_HEAD = re.compile(r"^##\s", re.M)


def tutorial_lines(md: str) -> set[int]:
    """Physical line numbers inside the tutorial section, if the page has
    one. Empty for a page whose first `##` is not `## 1.`."""
    lines = lf(md).split("\n")
    start = None
    for i, line in enumerate(lines):
        if SECTION_HEAD.match(line):
            if start is None and TUTORIAL_HEAD.match(line):
                start = i
            elif start is not None:
                return set(range(start + 1, i + 1))
    if start is not None:
        return set(range(start + 1, len(lines) + 1))
    return set()


def check(paths: list[Path]) -> list[str]:
    banned = load_banned()
    hits: list[str] = []

    def add(hit: str) -> None:
        if hit not in hits:
            hits.append(hit)

    for path in paths:
        name = label(path)
        raw = path.read_text(encoding="utf-8")
        text = prose(raw)
        plain = fenceless(raw)
        tutorial = tutorial_lines(raw)

        # banned-phrases: paragraph-joined, so a line wrap is not a way
        # through the gate.
        for para in paragraphs(text):
            for pattern, source in banned:
                for match in pattern.finditer(para.text):
                    line, piece = para.at(match.start())
                    add(f'{name}:{line}  banned "{source}": {piece}')

        # internal-documents: paragraph-joined for the same reason.
        for para in paragraphs(plain):
            for pattern, source in WORKING_DOCS:
                for match in pattern.finditer(para.text):
                    line, piece = para.at(match.start())
                    add(f'{name}:{line}  cites {source}: {piece}')

        for i, line in enumerate(text.split("\n"), 1):
            # em-dashes-are-spaced. Google rules the other way and
            # `.vale.ini` switches Google.EmDash off; this is the rule it
            # is switched off in favour of, so it has to be real.
            for match in re.finditer(r"(.?)—(.?)", line):
                before, after = match.group(1), match.group(2)
                if before not in ("", " ") or after not in ("", " "):
                    add(f"{name}:{i}  unspaced em dash: {line.strip()}")

            # em-dashes-are-rationed: one ASIDE per line, so a single
            # trailing dash or one matched pair. Three is the stacking the
            # ration exists to stop.
            if line.count("—") > 2:
                add(f"{name}:{i}  {line.count(chr(0x2014))} em dashes on "
                    f"one line: {line.strip()}")

            match = FIRST_SINGULAR.search(line)
            if match:
                add(f'{name}:{i}  first-person singular "{match.group(0)}": '
                    f"{line.strip()}")

            if i not in tutorial:
                match = FIRST_PLURAL.search(line)
                if match:
                    add(f'{name}:{i}  first-person plural outside a tutorial '
                        f'"{match.group(1)}": {line.strip()}')

        for i, line in enumerate(lf(raw).split("\n"), 1):
            if EMOJI.search(line):
                add(f"{name}:{i}  emoji: {line.strip()}")

    return hits


# ---------------------------------------------------------------------
# Relative links.
#
# Ported from upstream's `relative-links-resolve`. It earns its place
# immediately: four pages named a `runner` file that has never existed in
# this repository -- csharp/DOCS.md, javascript/DOCS.md, lua/DOCS.md and
# python/DOCS.md each pointed at `runner.*` when the corpus loader is
# `omni.*`. All four had been shipping on GitHub, npm and PyPI as 404s.
#
# Only the PATH is resolved, not the anchor: a heading slug depends on the
# renderer, and a gate that guesses one would fail on correct links.
# ---------------------------------------------------------------------

# BOTH MARKDOWN LINK FORMS. The inline `[text](target)` is the common one
# here, but `[text][label]` with a `[label]: target` definition is equally
# standard and the root README already uses it (for external links today,
# and nothing stops a relative one). A gate that reads only the first form
# would report success on a broken reference link while promising to check
# every link, which is worse than not having the check.
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")

LINK_TARGET = re.compile(r"(?m)^\s{0,3}\[[^\]]+\]:\s*<?([^>\s]+)>?")

EXTERNAL = ("http://", "https://", "mailto:", "#", "//")


def broken(page: Path, target: str) -> bool:
    """A target is good only if it exists AND stays inside the repository.

    Existing is not enough: `../../etc/passwd` from a root page resolves on
    a Linux runner and would pass, while resolving nowhere on GitHub or
    inside a published package. Both halves have to hold.
    """
    relative = target.split("#", 1)[0]
    if not relative:
        return False
    resolved = (page.parent / relative).resolve()
    if not resolved.exists():
        return True
    return not resolved.is_relative_to(ROOT)


def check_links(paths: list[Path]) -> list[str]:
    hits = []
    for path in paths:
        name = label(path)
        text = fenceless(path.read_text(encoding="utf-8"))
        for i, line in enumerate(text.split("\n"), 1):
            targets = [m.group(1) for m in LINK.finditer(line)]
            targets += [m.group(1) for m in LINK_TARGET.finditer(line)]
            for target in targets:
                if target.startswith(EXTERNAL):
                    continue
                if broken(path, target):
                    hits.append(f"{name}:{i}  broken link: {target}")
    return hits


def check_guide_names_this_gate() -> list[str]:
    """The guide and this gate must agree; the guide names this file, so a
    reader of either finds the other."""
    if not STYLE_GUIDE.is_file():
        return [f"missing {label(STYLE_GUIDE)}"]
    text = STYLE_GUIDE.read_text(encoding="utf-8")
    out = []
    if "tools/check_prose.py" not in text:
        out.append("STYLE-GUIDE.md should point at tools/check_prose.py")
    if "reject.txt" not in text:
        out.append("STYLE-GUIDE.md should name the banned list file")
    return out


def main(argv: list[str]) -> int:
    if "--files" in argv:
        problems = check_page_set()
        if problems:
            for problem in problems:
                print(problem, file=sys.stderr)
            return 1
        try:
            for path in pages():
                print(label(path))
            sys.stdout.flush()
        except BrokenPipeError:
            # `--files | head` closes the pipe early. Not a failure.
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0

    named = [Path(a).resolve() for a in argv if not a.startswith("-")]
    paths = named or pages()

    hits = check(paths) + check_links(paths)
    if not named:
        hits += check_page_set() + check_guide_names_this_gate()

    print(f"prose gate: {len(paths)} pages")
    if hits:
        for hit in hits:
            print(f"  {hit}")
        print(f"\n{len(hits)} finding(s) — see STYLE-GUIDE.md")
        return 1
    print("  ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
