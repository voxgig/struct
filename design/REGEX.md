# Regex Strategy — Cross-Port

> **Goal:** every port supports at least the regex feature set of Go's
> built-in `regexp` package (RE2 syntax), and **no port carries a runtime
> regex dependency** beyond what its standard library ships with.
> Build-time tooling (formatters, linters, test runners, package
> managers) is unaffected.

## Where regex actually appears

The library uses regular expressions in two places:

1. **Internal**: parsing path syntax, splitting backtick injections, the
   meta-path delimiter, the `$$`/`$BT`/`$DS` escapes, the
   `$NAME[digits]` transform pattern, integer-key detection, etc. Every
   internal pattern in `typescript/src/StructUtility.ts` is RE2-compatible:

   | Pattern | What it matches | RE2 OK? |
   |---|---|---|
   | `^[-0-9]+$` | integer key | yes |
   | `[.*+?^${}()|[\]\\]` | regex meta-chars (for `escre`) | yes |
   | `"` | double quote | yes |
   | `\.` | literal dot | yes |
   | `^\`\$REF:([0-9]+)\`$` | clone back-ref | yes |
   | `^([^$]+)\$([=~])(.+)$` | meta-path `name$=val` / `name$~val` | yes |
   | `\$\$` | `$$` escape | yes |
   | `\`\$([A-Z]+)\`` | extract `NAME` from `` `$NAME` `` | yes |
   | `^\`(\$[A-Z]+|[^\`]*)[0-9]*\`$` | full-string injection | yes |
   | `\$BT` / `\$DS` | backtick / dollar escapes | yes |
   | `\`([^\`]+)\`` | partial-string injection | yes |
   | `/+$` / `^/+` / `([^/])/+([^/])` | URL joiner internals | yes |

2. **User-facing**: the `$LIKE` select operator. The shared corpus has
   **one** `$LIKE` case in `build/test/select.jsonic`:

   ```
   { query: {s0: '`$LIKE`':'[aA][bB][cC]'}, obj: [{s0:'DEf'},{s0:'ABc'}] }
   ```

   `[aA][bB][cC]` is just character classes — RE2-compatible.

**Conclusion:** the corpus today is already inside the RE2 subset. We
just need to lock that in and stop ports from accidentally widening it.


## Per-port status

| Port | Engine | Runtime dep? | Pattern flavour | Notes |
|---|---|---|---|---|
| **ts** / **js** | ECMAScript `RegExp` | built-in | ECMAScript | superset of RE2 (lookbehind, backrefs) |
| **py** | `re` (stdlib) | built-in | Python | superset of RE2 |
| **go** | `regexp` (stdlib) | built-in | RE2 | baseline |
| **php** | PCRE (built-in) | built-in | PCRE | superset of RE2 |
| **rb** | Onigmo (stdlib) | built-in | Oniguruma | superset of RE2 |
| **java** | `java.util.regex` | built-in | Java regex | superset of RE2 |
| **cs** | `System.Text.RegularExpressions` | built-in | .NET | superset of RE2 |
| **kt** | `kotlin.text.Regex` | built-in (uses Java backend) | Java regex | superset of RE2 |
| **cpp** | `<regex>` (C++11) | built-in | ECMAScript by default | superset of RE2 |
| **rs** | `regex` crate | **runtime dep** | RE2 (the crate is the source of RE2) | violates "no runtime deps" goal |
| **zig** | `mvzr` package | **runtime dep** | small NFA subset | violates "no runtime deps" goal |
| **c** | (none) | substring fallback | no patterns | sub-RE2 |
| **lua** | `string.match` | built-in | Lua patterns, **not regex** | character classes work, but `\d` / `?` lazy / lookaround don't |

Three groups need work:

- **rs**, **zig** — drop the runtime regex dep (currently held by
  external libraries).
- **c** — add a minimal RE2-subset matcher (currently substring only).
- **lua** — different syntax; document or remap.


## Recommended portable subset

The "Go-or-better" subset every port commits to is the RE2 syntax minus
features RE2 itself doesn't expose. Implementers can rely on:

- Literal characters and escapes (`\n`, `\t`, `\\`, `\.`, etc.)
- Any-char: `.`
- Anchors: `^`, `$`
- Quantifiers: `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}` (greedy and lazy `*?`/`+?`/`??`)
- Character classes: `[abc]`, `[^abc]`, `[a-z]`
- Predefined classes: `\d`, `\D`, `\s`, `\S`, `\w`, `\W`
- Word boundary: `\b`, `\B`
- Groups: `(...)`, `(?:...)`, named groups `(?P<name>...)` (RE2 form)
- Alternation: `a|b`
- Unicode property classes: `\p{L}`, `\P{L}` (optional — many embedded
  matchers skip Unicode)

What ports must **not** rely on, even in tests:

- Backreferences (`\1`, `(?P=name)`)
- Lookahead / lookbehind (`(?=...)`, `(?!...)`, `(?<=...)`, `(?<!...)`)
- Possessive quantifiers (`a++`, `a*+`)
- Atomic groups (`(?>...)`)
- Inline flags scoped to subpatterns (`(?i:...)`) — RE2 has them, but
  not every minimal port will

This is exactly the RE2 feature set, intersected with what an
NFA-derivative matcher can implement in a few hundred lines.


## Strategy by port

### TypeScript / JavaScript / Python / Ruby / PHP / Java / Kotlin / C# / C++

No action: stdlib engines already cover the subset. Keep using the
built-in (`RegExp`, `re.compile`, `Pattern.compile`, etc.); just don't
*write* tests that step outside the subset. A corpus-level check
(see below) enforces this for the test suite.

### Go

Already the baseline. No action.

### Rust

`rust/Cargo.toml` currently lists `regex = "1"` as a runtime dependency.
Two routes:

1. **Vendor a minimal matcher.** Implement `voxgig_struct::_regex` —
   roughly an NFA with the subset above. About 400–600 LOC. Drops the
   `regex` crate entirely.
2. **Use `regex-lite`** (~50 KB compiled, same syntax minus a few
   esoteric bits). Still a third-party crate but ~10× smaller and
   no Unicode tables. Doesn't satisfy "no runtime deps" but it's the
   smallest possible delta.

Recommend option 1 — the surface used by struct is so small (`Regex::new`
+ `is_match` / `find` / `replace_all`) that the vendored matcher needs
maybe four public methods.

### Zig

`zig/build.zig.zon` currently depends on `mvzr` (≈1500 LOC). Two
routes:

1. **Vendor mvzr in-tree.** Copy `mvzr.zig` into `zig/src/vendor/` and
   drop the dependency entry. Zig licences allow this; mvzr is MIT.
2. **Write a tiny matcher** for the subset (Zig is well-suited to NFA
   work; ~400 LOC).

Recommend option 1 — same code, just inlined. Removes the network
dependency and the `.zon` hash without adding new code to maintain.

### C

My port currently uses substring containment for `$LIKE`. Add a
minimal NFA matcher in `c/src/regex.c` / `c/src/regex.h`. A reasonable
prior-art reference is `tiny-regex-c`
(<https://github.com/kokke/tiny-regex-c>, public domain, ~500 LOC) — its
feature set is *almost* the subset above (it's missing `{n,m}`
quantifiers and lazy modifiers). Either:

1. **Vendor tiny-regex-c** and extend it for `{n,m}` + lazy quantifiers
   (~50 extra LOC).
2. **Write fresh** — Russ Cox's "regular expression matching can be
   simple and fast" approach builds a Thompson NFA in ~200 LOC plus
   another ~100 for the parser.

Either way, the API is small: `vs_regex_compile`, `vs_regex_match`,
`vs_regex_free`. No `libpcre`, no `libregex.h` (which isn't portable
to non-POSIX targets).

### Lua

`string.match` / `string.find` use **Lua patterns**, not regex. The
syntax differences for the corpus subset:

| Subset | Lua pattern | Lua-compatible? |
|---|---|---|
| `.` | `.` | yes |
| `^`, `$` | `^`, `$` | yes (anchors only at ends of pattern) |
| `[abc]`, `[^abc]`, `[a-z]` | same | yes |
| `*`, `+`, `?` | `*`, `+`, `?` (no lazy `*?`) | partial |
| `\d` | `%d` | no — different syntax |
| `\w`, `\s`, `\b` | `%w`, `%s` (no `\b`) | partial |
| `(...)` capture | `(...)` | yes |
| `a|b` alternation | not supported | **no** |
| `{n,m}` | not supported | **no** |

So Lua's built-in pattern engine can't express the full subset.
Options:

1. **Accept the divergence.** The corpus only exercises character
   classes via `$LIKE`, which Lua patterns support natively. Document
   the limitation in `lua/README.md`. If a future test needs `|` or
   `{n,m}` it must come with a Lua-friendly equivalent.
2. **Add a Lua-native pattern compiler.** Implement a tiny pattern
   matcher in pure Lua (around 400 LOC). Same approach as the C/Zig
   recommendations.
3. **Vendor LPeg as a source file.** LPeg is the standard Lua parsing
   library and supports more general grammars. Not a "regex engine"
   exactly but covers the subset. ~1500 LOC.

Recommend option 1 for now — the cost/benefit ratio of writing a Lua
regex engine to support one test pattern is poor. If the corpus later
grows a pattern that Lua patterns can't express, revisit then.


## Test-corpus enforcement

To keep the corpus inside the portable subset:

1. **Document the subset** at the top of
   `build/test/select.jsonic` (and any future file that adds `$LIKE`
   patterns).
2. **Add a parity-scan check** in `tools/check_parity.py` (or a sibling
   `tools/check_corpus_regex.py`) that:
   - Walks every `.jsonic` test file.
   - Extracts strings under `$LIKE` (and any other regex slot we add
     later).
   - Runs each pattern through Go's `regexp.Compile` (via a shell-out)
     OR re-implements the subset check.
   - Fails the build if any pattern is RE2-incompatible.
3. **Add a tests-only Go program** `tools/check_regex.go` that
   compiles all known patterns. CI runs `make scan-regex`.

## Suggested rollout order

1. **Now (docs only):**
   - Land this document at `REGEX.md` or in `REPORT.md`.
   - Document the subset constraint in `build/test/.../README.md`.
   - Add the parity scanner check.

2. **Next (small code touches):**
   - C port: implement `vs_regex_*` matcher (~500 LOC). Wire `$LIKE`
     to it. Drop the substring fallback and update the parity-matrix
     entry from `Y*` to `Y`.
   - Lua: add an explicit divergence note in `lua/README.md`. No code
     change.

3. **Later (larger refactors):**
   - Zig: copy `mvzr.zig` in-tree under `zig/src/vendor/` (MIT licence
     allows). Remove the `.zon` dependency.
   - Rust: replace the `regex` crate with a vendored matcher. ~600 LOC
     in `rust/src/regex.rs`.

Once the four affected ports (rs, zig, c, lua) are done, every port
guarantees the subset and **no port carries a runtime regex dep beyond
its stdlib**.


## Why not adopt JS / PCRE as the baseline instead?

ECMAScript regex (the canonical TS uses it) allows backreferences and
lookaround, neither of which RE2 supports. Adopting JS as the baseline
would force every non-PCRE-capable port to ship a heavier engine —
defeating the "no runtime deps" goal. Conversely, requiring only RE2
means every port can implement the matcher in a few hundred LOC, or
defer to its stdlib.

The current corpus doesn't use any extra-RE2 feature, so picking RE2
as the floor costs nothing today and keeps the door open for ports
written in languages without rich stdlib regex.
