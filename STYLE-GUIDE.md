# Documentation style guide

How the Voxgig Struct documentation is written. This guide is normative
for the root [`README.md`](./README.md) and [`DOCS.md`](./DOCS.md) and for
every port's `README.md` and `DOCS.md` — 50 pages, the ones a reader lands
on from GitHub, npm, crates.io, PyPI, pkg.go.dev and the rest. It exists so
that a page written next year sounds like a page written this year, and so
that a reviewer can point at a rule instead of arguing taste.

It is a port of [voxgig/jostraca](https://github.com/jostraca/jostraca)'s
guide, which shares an author and a house voice with this project. The
structure and most of the rules are that project's. Where this one differs
— the em dash, the internal-document set, the shape of the four parts —
the difference is recorded with the measurement behind it, because a
divergence nobody wrote down reads later as drift.

Three sources feed the guide, in a fixed priority order. The same order is
encoded in [`.vale.ini`](./.vale.ini), and every rule switched off there
names the reason and the count it produced:

    house voice  ->  Google  ->  Vale defaults

1. **This file.** Where it rules, it rules. The house voice is Richard
   Rodger's blog register, and the places it wins are listed with their
   reasons rather than left as silent exceptions: the spaced em dash,
   first-person plural in tutorial sections, British spellings, and
   quotation punctuation outside the quotes.
2. The [Google developer documentation style
   guide](https://developers.google.com/style) for everything this file
   does not cover: second person, present tense, active voice,
   sentence-style capitalisation in headings, serial commas, one idea per
   sentence.
3. [Vale](https://vale.sh) defaults, which mostly means spelling.

Two gates check it, and both run in CI:

| Gate | Runs | Checks |
|---|---|---|
| `vale $(python3 tools/check_prose.py --files)` | `.github/workflows/docs.yml` | Google's rules plus the banned list, at the levels set in `.vale.ini` |
| `python3 tools/check_prose.py` | `make scan-prose`, and the same workflow | the banned list, the em-dash spacing and ration, the first-person rules, no emoji, no citations of a working document, that every relative link resolves, and that the page set is complete |

The banned list is read from one file by both, so they cannot drift. The
page set comes from one function, `tools/check_prose.py --files`, for the
same reason: a gate reading a smaller set than the other is a gate that
reports green on a page nobody checked.

A Google rule sitting at `warning` rather than `error` was tried at error
level first and found wrong for these pages; `.vale.ini` records what it
produced and why it was demoted.

## The structure: four parts, as sections rather than files

Every `DOCS.md` is a four-part guide: a tutorial, how-to recipes, a
reference, and an explanation, in that order. Upstream gives each part its
own file. This project has 24 ports and could not, so the part is a
**numbered section** inside each `DOCS.md`, and the rules attach to the
section:

| Part | Where | May | May not |
|---|---|---|---|
| Tutorial | `DOCS.md` §1 | teach step by step, show output for every step, defer detail with a link | argue design, list every function, assume the reader's goal |
| How-to | `DOCS.md` §2 | solve one named task, assume competence, link the reference | teach basics, explain design, drift into a second task |
| Reference | `DOCS.md` §3 | state facts exhaustively and dryly, pin claims to corpus entries | narrate, persuade, teach |
| Explanation | `DOCS.md` §4 | argue, compare, admit trade-offs, tell the design's story | be the only place a fact lives |

`README.md` is the doorway and belongs to no part: it routes, gives the
quick start, and states no fact of its own that a `DOCS.md` below it does
not also state.

One fact appears in all four parts at different altitudes — met in the
tutorial, used in a how-to, specified in the reference, argued in the
explanation — but the normative statement lives in the reference and
everything else links to it.

### The canonical page owns the behaviour

This project has a second axis upstream does not: 24 ports of one library.
The rule that falls out of it is the documentation half of the rule the
code already follows.

**Behaviour is documented once, on the language-neutral pages**, which are
the root `README.md` and `DOCS.md`. A port's pages document that port: its
spelling of the API, its types, its build, and any place it diverges. A
port page that re-explains what `getpath` does has taken on a copy of a
fact that will go stale the day the canonical changes, and there are 23
other copies of it that will not be updated in the same commit.

**A divergence is stated where it happens, and pointed at the record.**
The cross-port specifications under `design/` are where a divergence is
argued and pinned; a port page names the divergence, says what this port
does, and links there. Those pages are citable — see below.

## Documentation does not cite a working document

**A documentation page never sends a reader to a plan, an assessment, or
an agent instruction file.** Those are working documents: written for the
people changing this repository, argued rather than stated, and stale the
moment the code moves past them. A reader who follows a link out of the
documentation and lands in one has been handed the project's notes in
place of an answer.

The banned set, by name:

| Document | What it is |
|---|---|
| `AGENTS.md`, `CLAUDE.md` (root and per port) | instructions to contributors and agents working in the repository |
| `design/DOC_EXAMPLES.md` | the plan for the documentation-example anchors |
| `design/TESTPROVIDER_ASSESSMENT.md`, `design/SELECT_NULL_KEY_BACKPORT.md` | analysis and recommendations, revised as the code moves |
| any `*_PLAN.md` or `*_REVIEW.md`, and `BUILD_LOG.md` | the shapes this project has not needed yet, guarded in advance |

The ban covers the name as much as the link. "The full checklist is in
`AGENTS.md`" fails for the same reason the URL does: the reader still
cannot act on the sentence without leaving the documentation.

State the fact instead. "A behaviour change starts in the canonical
TypeScript, then the corpus, then every port" is what a reader needs, and
a link to the file that also says so adds nothing to it. Where the fact
belongs in the documentation and is missing, write it into the section
that owns it rather than pointing outside.

The rule runs one way. Working documents cite each other and cite the
documentation freely. Only the direction out of documentation is closed.

### What stays linkable, and why

**This project's `design/` directory is not upstream's.** There, the
equivalent folder holds plans and reviews only, and the ban covers all of
it. Here it holds two kinds of file, and half of it is normative:

| Linkable | Because |
|---|---|
| `design/REGEX.md`, `REGEX_API.md`, `REGEX_PATHOLOGICAL.md` | the regex subset is *defined* there and nowhere else; the six-function `re_*` API has no other specification |
| `design/UNDEF.md`, `design/UNDEF_SPEC.md` | the absent-versus-null rule, likewise |
| `design/TESTSPEC_MODEL.md` | the corpus schema, which the corpus is generated from |
| `design/REPORT.md` | the parity matrix: reference data, regenerated, cited by every port |
| `design/NOTES.md` | the register of cross-cutting quirks a port page points at when it records a divergence |
| source, tests, and the corpus under `build/test/` | code is the thing a claim is pinned to |
| this guide | normative rather than exploratory, and it names the working documents in order to ban them |

The rule behind the split: **a specification is citable, an argument is
not.** A reader sent to `UNDEF_SPEC.md` gets a rule they can apply. A
reader sent to an assessment gets somebody's reasoning, mid-flight.

`tools/check_prose.py` enforces this over the 50 reader-facing pages. Vale
does not, because Vale cannot tell the two halves of `design/` apart.

## The voice

The house voice is Richard Rodger's blog register, adapted per section.
The portable part of that voice is its *rhythm*, not its stock phrases. Ten habits, with the register they apply in:

1. **Open with a concrete fact or a plainly stated problem, then a short
   dry beat.** Tutorial and how-to sections. Reference sections open by
   stating what the thing is.
2. **Introduce code with a short colon-terminated sentence** — "Run the
   corpus:", "The Rust spelling is:". Never "The following code snippet
   demonstrates". Everywhere.
3. **After a code block, point at the one interesting thing.** Do not
   recap the code. Everywhere.
4. **Parentheses carry definitions, caveats, and at most one dry aside per
   section.** Tutorial and how-to sections. In reference sections,
   parentheses carry facts only — a type, a default, a corpus entry.
5. **A trade-off gets bolted on with a dash, and the dash earns its
   place.** One per paragraph at most, never two in a sentence.
6. **Alternate one long explanatory sentence with one short verdict
   sentence.** The short sentence is the payoff. Everywhere.
7. **Talk to the reader as "you", and route them** ("If you only want the
   Rust spelling, skip to…"). "We" appears only in a tutorial section,
   walking through code together. "I" appears nowhere.
8. **Show that the code is real.** A documentation example carries an
   `<!-- example: id -->` anchor binding it to a corpus entry, and
   `tools/check_doc_examples.py` fails the build if the declared output
   and the tested one disagree. When a page says the listing is what the
   corpus produced, that is checkable and checked.
9. **Jokes are self-directed or about the industry's mundanity, and the
   register goes fully serious the moment correctness or a user's data is
   on the table.** Never joke about the reader, other languages, or
   another port.
10. **Close by handing the reader something**: a link, a next step, one
    sentence. No summary paragraphs that restate the page.

Exclamation marks: at most one per page, in a tutorial section only, on a
genuine payoff.

## Banned phrases and patterns

These read as generated filler. Do not use them, in any document,
including commit messages that quote the docs.

**The list itself lives in
[`.vale/styles/config/vocabularies/Struct/reject.txt`](./.vale/styles/config/vocabularies/Struct/reject.txt)**,
one regular expression per line. That file is the single source of truth:
Vale reads it in CI, and `tools/check_prose.py` reads the same file rather
than keeping a second copy, so the two gates cannot disagree about what is
banned. Add a phrase there and both pick it up. What follows is a reader's
summary of it, not a second list; every phrase is shown as code so that
quoting a banned phrase in this guide does not fail the gate.

The list is upstream's, unchanged, and it draws on two sources: that
project's original house list, and [claudisms.ai](https://claudisms.ai/),
a catalogue of the patterns that mark machine-written prose. **It was
measured against these pages before it was adopted.** Three entries fired,
31 times: `comprehensive` in the title of all 25 `DOCS.md` files, two
`honest`, one `quietly`. All 31 were rewritten, and nothing was dropped
from the list to make it pass.

**Filler and false emphasis**: `worth noting` · `important to note` ·
`it cannot be overstated` · `at its core` · `when it comes to` ·
`let's break it down` · `here's where it gets interesting` ·
`the point is` · `because it matters`.

**Inflated vocabulary**: `delve` · `dive into` · `robust` · `seamless` ·
`comprehensive` · `holistic` · `intricate` · `leverage` · `foster` ·
`shed light on` · `pave the way` · `pivotal` · `transformative` ·
`game-changing` · `cutting-edge` · `groundbreaking` · `testament to` ·
`paradigm shift` · `realm` · `landscape of` · `underscores the` ·
`lean into` · `throughline` · `double-click on` · `mature setup`.

**Consultant register**: `north star` · `key takeaways` ·
`best practices` (name the practice instead) · `at the end of the day` ·
`pressure-test` · `right-size` · `strategic imperative` ·
`three things to know` · `dispatches from` · `best operators` ·
`lessons learned`.

**Metaphor inflation**: `load-bearing` · `heavy lifting` ·
`is doing the work` · `different physics` · `hits hardest` ·
`quietly` (say `silently`, which is the term of art for a failure that
reports nothing).

**The contrast frame and its cousins**: `not just` · `not only X but Y` ·
`it's not about` · `the whole game` · `the entire point` ·
`the only thing that matters`. Say what the thing is.

**False singularity**: `the right way/answer/tool/question` ·
`the best thing you can do` · `if I had to pick` · `what struck me` ·
`stuck with me` · `struck a chord` · `hit a nerve` ·
`we've seen this movie before`.

**Reflective pose**: `sit with` · `worth exploring/considering/asking` ·
`keeps coming back to` · `that's the tell` · `where I landed`.

**Invented observation about people**: `most people` ·
`everyone I've worked with` · `a lot of folks` · `nobody I know`. If it
did not happen, do not claim to have noticed it.

**Signposting**: `let's explore` · `now let's turn to` · `moving on to` ·
`in today's rapidly evolving` · `reflecting a broader trend` ·
`great question`.

**`honest`, and every form of it**, is banned differently from the rest.
The word is fine English; it is on the list because it had become a tic
across both repositories, where it flattered a sentence rather than said
anything the sentence did not already say. Two uses were here when the
list arrived: the Zig pages both called a divergence "the honest answer",
which is the sentence congratulating itself instead of describing the
divergence. In both, the word came out and nothing was lost.

**The gate is absolute, and the lack of an inline exemption is the
point.** There is no `allow` comment and no suppression the second gate
would honour, because an escape hatch that exists is an escape hatch that
gets used. A use the author wants kept is approved by changing
`reject.txt`: one line, in one file, visible in review, which is where an
approval belongs.

### What is not banned, and why

Several entries on claudisms.ai are deliberately absent, because they name
things this project documents. A gate that fires on the subject matter is
a gate people learn to switch off. The same standard governs
`Struct.WordChoice`, which drops upstream's `regex` substitution for
exactly this reason — 163 uses, and the word names a thing here.

| Not banned | Because |
|---|---|
| `regex` | Struct ships its own RE2-subset engine, a six-function `re_*` API, and three specification pages named for it. |
| `real` | `real filesystem` and `real number` are both distinctions this project has to draw. |
| `shape` | The corpus describes the *shape* of a value; it is the domain's own word. |
| `surface` | `the public API surface` is what `tools/check_parity.py` compares across ports. |
| `hold`, `carry`, `hands` | A node holds children, a corpus entry carries its expected output, a function hands back a value. |
| `lives` | `the normative statement lives in the reference` is this guide, one section up. |
| `canonical` | It is this project's word for the TypeScript source every port is a port of. |

The rule behind the list: ban the phrase that adds nothing, never the word
that names a thing.

**Matching spans a line wrap.** These pages hard-wrap, and most of the
list is multi-word, so the gate joins each paragraph before matching:
`worth\nnoting` fails exactly as `worth noting` does. Upstream records
that the day its gate started reading paragraphs it found two phrases that
had been passing since the gate was written, each saved only by where its
line happened to break.

**Patterns** (not mechanically checkable, enforced at review):

- Announcing structure before delivering it ("There are three things to
  understand").
- Restating the question before answering it.
- A closing one-liner that restates the thesis.
- Stacked short declaratives (four or more in a row).
- Superlative self-ranking ("the most important thing", "the part that
  matters most").
- A list of `**Bold term**: explanation` pairs, which is the single most
  recognisable machine-written list. Write sentences, or a table.

## Punctuation rulings

**The em dash is spaced here**: `a dash — like this`. This is the one
place where the guide contradicts both Google and upstream, and it is
a convention rather than drift — 589 spaced dashes across the 50 pages
when the gate was written, and **not one unspaced**. Rewriting 589 dashes
to satisfy a rule the prose has never once broken would be the tail
wagging the dog. `Google.EmDash` is therefore off, and
`tools/check_prose.py` `em-dashes-are-spaced` enforces the convention in
the other direction: an unspaced dash fails.

Dashes stay **rationed to one aside per line**: either a single dash
before a trailing clause, or one matched pair around a parenthetical,
never both and never two asides. Three on a line is the stacking the
ration exists to stop. Prefer a comma or parentheses when the aside is
mild.

The rest:

- In a link list, separate the link from its gloss with a full stop, not a
  dash:

  ```markdown
  - [Rust](rust/README.md). The port, with its own RE2-subset engine.
  ```

- **Every relative link must resolve, and stay inside the repository.**
  `tools/check_prose.py` checks the path, not the anchor, since a heading
  slug depends on the renderer; it reads both `[text](target)` and
  `[text][label]` with its definition. A target that resolves on a Linux
  runner but climbs out of the checkout resolves nowhere on GitHub or in a
  published package, so it fails too. The check found four dead links the
  day it was written: four ports named a `runner` file that has never
  existed here, all shipping as 404s on GitHub, npm and PyPI.
- No emoji in documentation.
- Sentence-style capitalisation in headings (Google style), except where
  the heading names a proper noun: `Regex API`, `Struct for Rust`.
- British spellings (`-ise`, `-isation`). Google style is US English; this
  is one of the places the house voice wins, and
  [`accept.txt`](./.vale/styles/config/vocabularies/Struct/accept.txt)
  carries them — **listed one by one**, never matched by suffix, because
  `\w+ise` accepts any word ending in those three letters and punches a
  hole straight through the spelling gate.
- Quotation punctuation goes **outside** the quotes, against US
  convention, because putting a period inside a quoted `code span` is
  actively wrong when the quote is a literal.

## Terminology

- The project is **Voxgig Struct**, or **Struct** in prose; the packages
  are `@voxgig/struct`, `voxgig-struct`, `voxgig_struct` and their
  per-ecosystem spellings. Lowercase `struct` is the C keyword and the
  Go/Rust/Zig type, never this project.
- **canonical** — the TypeScript source in `typescript/src/`. Every other
  language is a **port** of it. Never "reference implementation"; the
  corpus is the reference.
- **the corpus** — `build/test/*.aon` and the `test.json` compiled from
  them. It is the **contract**: a port that disagrees with it is wrong.
  Never "the test suite", which is a port's own runner.
- **a corpus entry** — one named case. Not "a fixture", not "a test".
- **absent** and **null** are different, and the difference is the
  project's hardest edge. Say **absent** for a property that is not there
  and **null** for one whose value is null. Never "undefined", which is
  one language's spelling of absent.
- **node** — a map or a list. **leaf** — anything else. These are the
  words `isnode` and `isleaf` are named for.
- **inject** — substituting `` `$...` `` values into a structure.
  **transform** — running a template over a model. They are different
  operations; do not use one for the other.
- **the regex subset** — the RE2-compatible fragment every port's `re_*`
  layer implements. Say "subset", not "flavour" or "dialect".
- **parity** — the property `tools/check_parity.py` checks: the same
  public names in every port. Not "consistency".

## Documentation examples are pinned to the corpus

An example that shows what a call returns carries an anchor binding it to
a corpus entry:

```markdown
<!-- example: minor/jsonify#brace -->
```

`tools/check_doc_examples.py` resolves the anchor, checks that the entry
is one the tests actually run, and compares the declared output marker
against the corpus. `tools/gen_doc_examples.py --check` fails the build if
a marker is missing or stale; `make gen-docs` writes them. An author
writes the anchor and the prose, and the generator types the output.

Two rules of taste:

- A documentation example shows a moment: one call, a small structure, a
  short result. Anything needing a large structure belongs in the corpus,
  and the page names the entry.
- An example is written in the language of the page it is on. The root
  pages use the canonical TypeScript; a port page uses that port.

## Templates, part by part

**Tutorial section** (`DOCS.md` §1): goal sentence → snippet → output →
the one observation → forward link. Every step's output shown.

**How-to section** (`DOCS.md` §2): the task as a heading in imperative or
"-ing" form; one sentence of situation; the recipe; one paragraph of what
to watch for; links to the reference for the constructs.

**Reference section** (`DOCS.md` §3): definition, then behaviour, then
edge cases, then a pinned example. Every claim that has a corpus entry
names it.

**Explanation section** (`DOCS.md` §4): the question, the answer, the
argument, the trade-off admitted. May quote history when the history is
the argument. In a port's pages this is where a divergence is explained,
and it links to the specification under `design/` that pins it.

## Updating this guide

Change it the way behaviour changes: in the same commit as the first page
that follows the new rule, with the reasoning in the commit message.

To ban a phrase, add the regular expression to
[`reject.txt`](./.vale/styles/config/vocabularies/Struct/reject.txt) and
summarise it in the preceding list. Both gates pick it up from that one
file; there is no second list to update, and `tools/check_prose.py` names
this file, so a drift is a build failure with a pointer.

To change a Google rule's level, edit [`.vale.ini`](./.vale.ini) and write
down what the rule produced on a clean run. "It was noisy" is not a
reason; "it maps `touch` to `tap`, and it objects to `snake_case`, which
this project names on purpose — 143 hits" is. A rule demoted without that
note reads later as an oversight, and gets re-promoted by someone
repeating the work.

To widen what the gates read, change `pages()` in `tools/check_prose.py`.
Both gates take their file set from it, so widening it once widens both —
and a page added to the repository without being added there is a page
neither gate has ever read.
