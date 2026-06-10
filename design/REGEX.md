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

**Conclusion:** the corpus is inside the RE2 subset, and every port now
locks that in — the in-tree engines (rs, zig, c, lua) only implement the
subset, so a port can't accidentally widen it.


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
| **perl** | native `qr//` (PCRE) | built-in | PCRE | superset of RE2 |
| **swift** | `NSRegularExpression` (Foundation/ICU) | built-in | ICU | superset of RE2 |
| **rs** | in-tree engine (`rust/src/re.rs`) | **none** | RE2 subset | zero runtime deps (`Cargo.toml` `[dependencies]` is empty) |
| **zig** | in-tree engine (`zig/src/regex.zig`) | **none** | RE2 subset | zero runtime deps (`build.zig.zon` `.dependencies = .{}`) |
| **c** | in-tree Thompson NFA (`c/src/regex.c`) | **none** | RE2 subset | wired into `$LIKE` + integer-key; no substring fallback |
| **lua** | in-tree engine (`lua/src/regex.lua`) | **none** | RE2 subset | pure-Lua matcher; replaces `string.match` |

All ports now ship within the RE2 subset with **no runtime regex
dependency beyond their stdlib**. The four ports that once needed work —
**rs**, **zig**, **c**, **lua** — have each shipped an in-tree engine
(see [Strategy by port](#strategy-by-port)).


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

### TypeScript / JavaScript / Python / Ruby / PHP / Java / Kotlin / C# / C++ / Perl / Swift

No action: stdlib engines already cover the subset. These ports use the
built-in (`RegExp`, `re.compile`, `Pattern.compile`, Perl's `qr//`,
Swift's `NSRegularExpression`, etc.); they just don't *write* tests that
step outside the subset. A corpus-level check (see below) enforces this
for the test suite.

### Go

Already the baseline. No action.

### Rust — shipped

`rust/Cargo.toml` no longer lists `regex` (its `[dependencies]` section
is empty). The regex engine is vendored in-tree at **`rust/src/re.rs`** —
a hand-written matcher covering the subset above, exposing the small
surface struct uses (`Regex::new` + `is_match` / `find` / `replace_all`).
Zero runtime crates.

### Zig — shipped

`zig/build.zig.zon` no longer depends on `mvzr` (its `.dependencies` is
`.{}`). The matcher is vendored in-tree at **`zig/src/regex.zig`** — a
small Thompson NFA for the subset. No network dependency, no `.zon` hash.

### C — shipped

The C port no longer uses substring containment for `$LIKE`. It ships a
Thompson-NFA matcher in **`c/src/regex.c`** (~1105 LOC) with a small
header (`c/src/regex.h`), wired into both `$LIKE` and integer-key
detection. The API is compact: `voxgig_regex_compile`,
`voxgig_regex_match`, `voxgig_regex_free`. No `libpcre`, no
`libregex.h` (which isn't portable to non-POSIX targets), and no
substring fallback.

### Lua — shipped

The Lua port no longer relies on `string.match` / Lua patterns (which
are intentionally not regex and can't express the full subset — no
alternation, no `{n,m}`, different `\d`/`%d` syntax). It ships a
pure-Lua RE2-subset matcher in **`lua/src/regex.lua`** (~658 LOC),
following the same approach as the C and Zig engines.


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

## Rollout — completed

All of the staged work below has shipped:

1. **Docs:**
   - This document landed at `REGEX.md`.
   - The subset constraint is documented for the corpus.
   - The parity scanner check is in place.

2. **C and Lua:**
   - C port: the `voxgig_regex_*` Thompson-NFA matcher
     (`c/src/regex.c`, ~1105 LOC) is wired into `$LIKE` and integer-key
     detection. The substring fallback is gone.
   - Lua port: the pure-Lua RE2-subset matcher (`lua/src/regex.lua`,
     ~658 LOC) replaced the Lua-pattern path.

3. **Zig and Rust:**
   - Zig: the in-tree matcher lives at `zig/src/regex.zig`; the `mvzr`
     `.zon` dependency is removed (`.dependencies = .{}`).
   - Rust: the in-tree matcher lives at `rust/src/re.rs`; the `regex`
     crate is removed (`[dependencies]` is empty).

With the four formerly-affected ports (rs, zig, c, lua) done, every port
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
