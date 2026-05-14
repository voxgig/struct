# Voxgig Struct — Regex Utility API

> **Purpose.** Define the small set of regex operations the library uses, so
> every port exposes the *same* call sites with the *same* names. Internal
> code uses these helpers instead of the host language's native regex
> machinery. That way the canonical TS source and every port read the same.

## The API

The library needs five operations on regex. Every port exposes them at the
top of its source file (the names below; the per-language casing matches the
rest of that port — see the casing table further down):

| Function | Inputs | Returns | Maps to (TS canonical) |
|---|---|---|---|
| `re_compile(pattern)` | `pattern: string` | opaque compiled regex (host's native type, cached when possible) | `new RegExp(pattern)` |
| `re_find(pattern, input)` | compiled-or-string `pattern`, `input: string` | `[whole, capture1, ...]` array, or `null` if no match (first match only) | `input.match(pattern)` for *non-global* `pattern` |
| `re_find_all(pattern, input)` | as above | array of `[whole, capture1, ...]` arrays, one per match (left-to-right, non-overlapping) | `[...input.matchAll(pattern)]` |
| `re_replace(pattern, input, replacement)` | `replacement` is a string with `$&` (whole match) and `$1`..`$9` (captures) supported, or a callback `(match) => string` taking the same array as `re_find` | new string | `input.replace(pattern, replacement)` for *global* `pattern` |
| `re_test(pattern, input)` | as `re_find` | bool | `pattern.test(input)` |
| `re_escape(literal)` | `literal: string` | string with regex metacharacters escaped | the existing `escre()` |

Port implementers may add `re_*` overloads (e.g. `re_find_at(pattern, input, start_idx)`) if a port already needs them. The names above are mandatory.

## Pattern dialect

Every port supports the **RE2 subset** documented in `/REGEX.md`. The library's
canonical patterns all live inside this subset, and the `$LIKE` test cases in
the corpus exercise the operator's full advertised feature set. Specifically:

- Literal characters and escapes (`\n`, `\t`, `\\`, `\.`, …)
- Any char (`.`)
- Anchors (`^`, `$`)
- Quantifiers `*`, `+`, `?`, `{n}`, `{n,}`, `{n,m}` (greedy + lazy)
- Character classes `[abc]`, `[^abc]`, `[a-z]` (and intersections of these)
- Predefined classes `\d`, `\D`, `\s`, `\S`, `\w`, `\W`
- Word boundary `\b`, `\B`
- Groups `(...)`, `(?:...)`, named groups `(?P<name>...)`
- Alternation `a|b`

Disallowed (RE2 does not support):
- Backreferences `\1`, `(?P=name)`
- Lookahead / lookbehind `(?=…)`, `(?!…)`, `(?<=…)`, `(?<!…)`
- Possessive quantifiers `a++` etc.
- Atomic groups `(?>…)`

## Why uniform call sites

The canonical TS source uses regex liberally — it's idiomatic JS. Every other
port should do the same so the source can be diff-read against the canonical.
This prevents drift where one port quietly hand-rolls something the canonical
delegates to regex (or vice versa).

A side benefit: when a port needs to swap its regex backend (e.g. removing the
`regex` crate from the Rust port), only the wrapper module changes.

## Per-port backend

Ports group into three categories:

**A. Host language ships a regex engine that is an RE2 superset.**

| Port | Backend |
|---|---|
| ts, js | `RegExp` (ECMAScript) |
| py | `re` module |
| go | `regexp` (RE2) |
| php | PCRE built-in |
| rb | Onigmo built-in |
| java | `java.util.regex` |
| cs | `System.Text.RegularExpressions` |
| kt | `kotlin.text.Regex` (Java backend) |
| cpp | `<regex>` (C++11 ECMAScript) |
| zig | currently `mvzr`; long-term: vendored or in-tree engine |
| rs | currently `regex` crate; long-term: vendored or in-tree engine |

For each, the `re_*` wrappers are five-to-ten-line functions that delegate.

**B. Host language has no regex engine.**

| Port | Backend |
|---|---|
| c | Vendored RE2-subset engine in `c/src/regex.c` (~700 LOC). No external dep. |
| lua | RE2-subset engine in pure Lua in `lua/src/regex.lua` (~500 LOC). No external dep. |

These ports include a compact Thompson-NFA matcher covering the dialect above.
Performance is not the goal — correctness on the RE2 subset is.

**C. Host language has a regex engine with a different syntax (Lua patterns).**

Already covered above: Lua falls into category B because Lua's built-in pattern
language is intentionally not regex.

## Casing per port

Function names follow the host language's convention but always map to the
same underlying operation:

| TS canonical | py / rb / lua / php / c | go / cs / cpp | java / kt / js |
|---|---|---|---|
| `re_compile` | `re_compile` | `ReCompile` | `reCompile` |
| `re_find` | `re_find` | `ReFind` | `reFind` |
| `re_find_all` | `re_find_all` | `ReFindAll` | `reFindAll` |
| `re_replace` | `re_replace` | `ReReplace` | `reReplace` |
| `re_test` | `re_test` | `ReTest` | `reTest` |
| `re_escape` | `re_escape` (alias of the existing `escre`) | `ReEscape` / `EscRe` | `reEscape` / `escRe` |

The existing `escre` / `EscRe` / `escapeRegex` etc. stays — `re_escape` is just
an alias so call sites read naturally next to the other `re_*` calls.

## Internal refactor targets

Every port that currently hand-rolls a check that the TS canonical writes as a
regex must move to `re_*`. The full list:

| TS regex constant | Used for | What every port should now do |
|---|---|---|
| `R_INTEGER_KEY` | accept list indices | `re_test(R_INTEGER_KEY, key)` |
| `R_ESCAPE_REGEXP` | drives `escre` | already centralised in `escre`; just `re_replace` inside it |
| `R_QUOTES` | strip `"` for `stringify` | `re_replace(R_QUOTES, …, '')` |
| `R_DOT` | strip `.` in `pathify` | `re_replace(R_DOT, …, '')` |
| `R_CLONE_REF` | recognise `` `$REF:N` `` | `re_find(R_CLONE_REF, s)` |
| `R_META_PATH` | recognise `name$=val` / `name$~val` | `re_find(R_META_PATH, s)` |
| `R_DOUBLE_DOLLAR` | `$$` → `$` | `re_replace(R_DOUBLE_DOLLAR, s, '$')` |
| `R_TRANSFORM_NAME` | extract `NAME` from `` `$NAME` `` | `re_find_all(R_TRANSFORM_NAME, s)` |
| `R_INJECTION_FULL` | detect full-string injection | `re_find(R_INJECTION_FULL, s)` |
| `R_INJECTION_PARTIAL` | walk `` `…` `` segments | `re_replace(R_INJECTION_PARTIAL, s, cb)` |
| `R_BT_ESCAPE`, `R_DS_ESCAPE` | `$BT`/`$DS` escapes | `re_replace(R_BT_ESCAPE, s, "`")` etc. |
| dynamic patterns in `join()` | URL-style sep collapsing | `re_replace(re_compile(…), s, …)` |

This is the call-site spec every port follows.
