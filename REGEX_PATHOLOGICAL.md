# Pathological Regex — Cross-Port Discovery

> First-pass discovery test. Goal is to surface where each port's regex
> wrapper misbehaves on pathological inputs. **Not for assertion** —
> behaviour differs across engines and the test files do not enforce a
> specific outcome. Fixes come later; this run is to find them.

The same 10-case panel runs in every port via the port's `re_*` API
(see `REGEX_API.md`). Each port has a `regex_pathological*` test file
under its own tests directory.

## The panel

| # | Name | Call | What it stresses |
|---|---|---|---|
| P1  | `redos_nested_plus`         | `re_test("^(a+)+$", "a"*22 + "!")` | Catastrophic backtracking via nested quantifier |
| P2  | `redos_alt_overlap`         | `re_test("^(a\|aa)+$", "a"*22 + "!")` | Catastrophic backtracking via overlapping alternation |
| P3  | `empty_repeat_replace`      | `re_replace("a*", "abc", "X")` | Zero-width-match convention in `replace_all` |
| P4  | `unicode_replace_dot`       | `re_replace("\\.", "café.au.lait", "/")` | UTF-8 char-boundary handling |
| P5  | `unicode_find_codepoint`    | `re_find("é", "café au lait")` | Non-ASCII patterns |
| P6  | `deep_nesting_compile`      | `re_test("(((…40…(a)…)))","a")` | Parser/compiler stack |
| P7  | `big_bounded_quantifier`    | `re_test("^a{0,10000}b$", "a"*10+"b")` | Large bounded quantifier |
| P8  | `invalid_pattern`           | `re_compile("[abc")` | Error reporting |
| P9  | `backref_re2_forbidden`     | `re_test("^(a+)\\1$", "aaaa")` | RE2 strictness on backrefs |
| P10 | `find_all_zero_width`       | `re_find_all("a*", "bbb")` | Zero-width `find_all` enumeration |

## Findings (first run)

Times in ms — wall-clock per case.

| Port       | P1 (ms) | P2  | P3 result    | P4 result        | P7  | P8                | P9 result |
|------------|--------:|----:|--------------|------------------|----:|-------------------|-----------|
| typescript |  169    | 3   | `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| javascript |  172    | 3   | `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| python     |  185    | 4   | `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| ruby       |    0.04 | 0.03| `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| php        |    2    | 0.3 | `"XXbXcX"`   | `café/au/lait`   | OK  | **OK (silent!)**  | matches   |
| perl       |    0.06 | 0.04| `"XXbXcX"`   | **`cafÃ©/au/lait`** | OK  | ERR (clean)    | matches   |
| go         |    0.05 | 0.02| **`"XbXcX"`** | `café/au/lait`  | **PANIC** | **PANIC**   | **PANIC** |
| rust       |    0.04 | 0.02| `"XXbXcX"`   | `café/au/lait`   | **STACK-OVERFLOW** | — (binary aborted) | — |
| java       |   16    | 0.2 | `"XXbXcX"`   | `caf?/au/lait`†  | OK  | ERR (clean)       | matches   |
| cpp        | **1349**| 28  | `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| c          |    0.01 | 0.01| **`"XaXbXcX"`** | `café/au/lait`| OK  | ERR (NULL return) | non-match |
| lua        |    0.10 | 0.13| **`"XaXbXcX"`** | `café/au/lait`| OK  | ERR (clean)       | non-match |
| csharp     |  359    | 7   | `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| kotlin     |   30    | 0.2 | `"XXbXcX"`   | `café/au/lait`   | OK  | ERR (clean)       | matches   |
| swift      | n/r     |     |              |                  |     |                   |           |
| zig        | n/r     |     |              |                  |     |                   |           |

n/r = not run (toolchain unavailable in this environment).
† Java prints `?` because stdout's default encoding is platform-dependent, not the regex; the JVM-internal string is correctly `café`.

## Failures discovered

1. **rust — `re_test("^a{0,10000}b$", …)` overflows the matcher's stack.**
   The in-tree Thompson engine appears to allocate per-repeat state on the
   call stack. The whole test binary aborts (SIGABRT). `panic::catch_unwind`
   cannot recover from stack-exhaustion. P8/P9/P10 are never reached.

2. **php — `re_compile("[abc")` returns a valid-looking delimited pattern
   and `re_test` returns `false` silently.** `php/src/Struct.php:565` does
   `'/' . str_replace('/', '\\/', $pattern) . '/'` without ever compiling;
   `re_test` uses `@preg_match` which suppresses warnings. Callers can't
   tell a bad pattern from a no-match.

3. **go — `ReCompile`/`ReTest`/`ReReplace` all use `regexp.MustCompile`
   and panic** on (a) bounded quantifiers > 1000 (`a{0,10000}` — RE2 limit),
   (b) invalid patterns, and (c) backrefs (not supported by RE2). The Go
   API has no shape that lets a caller catch a compile error.

4. **Three distinct P3 conventions for zero-width `replace_all`:**
   - JS/TS/Python/Ruby/PHP/Java/.NET/Kotlin/Rust/C++ → `"XXbXcX"`
   - Go → `"XbXcX"`
   - C / Lua (in-tree engines) → `"XaXbXcX"` (the matching `a` is replaced AND a zero-width insertion is emitted)
   Internal call sites that depend on the exact shape will diverge.

5. **C and Lua return `false` for the backref pattern P9** rather than
   erroring; the parser silently consumes `\1` as something other than a
   backref. RE2 ports (Go) reject it; PCRE/ECMA ports (everyone else) match.

6. **C++ libstdc++ regex shows catastrophic backtracking** — 1349 ms on
   `(a+)+` over 22 a's. C# (.NET) and Python next worst (~350 ms / ~185 ms).
   Go / Rust / Ruby / Perl / C / Lua are all sub-millisecond (no backtracking).

7. **perl — UTF-8 round-tripping in `re_replace` corrupts output.** P4
   returned `cafÃ©/au/lait`. Either the regex returns octets or the JSON
   encoder treats characters-as-bytes — encoding boundary is wrong in the
   port.

8. **C public header omits `re_find_all`** — surface gap vs the rest of
   the ports.

9. **Zig public surface omits `re_find`, `re_find_all`, `re_replace`** —
   only `re_compile`, `re_test`, `re_escape` are exported. Half the
   `REGEX_API.md` contract is unimplemented.

## Where the test files live

| Port       | Path |
|------------|------|
| typescript | `typescript/test/regex_pathological.test.ts` |
| javascript | `javascript/test/regex_pathological.test.js` |
| python     | `python/tests/test_regex_pathological.py` |
| ruby       | `ruby/test_regex_pathological.rb` |
| php        | `php/tests/RegexPathologicalTest.php` |
| perl       | `perl/t/regex_pathological.t` |
| go         | `go/regex_pathological_test.go` |
| rust       | `rust/tests/regex_pathological.rs` |
| java       | `java/src/test/RegexPathologicalTest.java` |
| cpp        | `cpp/tests/regex_pathological.cpp` |
| c          | `c/tests/regex_pathological.c` |
| lua        | `lua/test/regex_pathological.lua` |
| csharp     | `csharp/tests/RegexPathologicalTest.cs` |
| kotlin     | `kotlin/src/test/kotlin/voxgig/struct/RegexPathologicalTest.kt` |
| swift      | `swift/Tests/VoxgigStructTests/RegexPathologicalTests.swift` |
| zig        | `zig/test/regex_pathological.zig` |
