# Pathological Regex — Cross-Port Discovery & Fixes

> Discovery panel that runs 10 deliberately pathological regex inputs
> against every port's `re_*` API. The first pass surfaced where port
> wrappers misbehaved on edge cases; this document records the panel,
> the **fixed** porting variations, and the irreconcilable
> engine-bound differences that remain.

The same 10-case panel runs in every port via the port's `re_*` API
(see `REGEX_API.md`). Each port has a `regex_pathological*` test file
under its own tests directory.

## The panel

| # | Name | Call | What it stresses |
|---|---|---|---|
| P1  | `redos_nested_plus`         | `re_test("^(a+)+$", "a"*22 + "!")`         | Catastrophic backtracking via nested quantifier |
| P2  | `redos_alt_overlap`         | `re_test("^(a\|aa)+$", "a"*22 + "!")`      | Catastrophic backtracking via overlapping alternation |
| P3  | `empty_repeat_replace`      | `re_replace("a*", "abc", "X")`             | Zero-width-match convention in `replace_all` |
| P4  | `unicode_replace_dot`       | `re_replace("\\.", "café.au.lait", "/")`   | UTF-8 char-boundary handling |
| P5  | `unicode_find_codepoint`    | `re_find("é", "café au lait")`             | Non-ASCII patterns |
| P6  | `deep_nesting_compile`      | `re_test("(((…40…(a)…)))","a")`            | Parser/compiler stack |
| P7  | `big_bounded_quantifier`    | `re_test("^a{0,10000}b$", "a"*10+"b")`     | Large bounded quantifier |
| P8  | `invalid_pattern`           | `re_compile("[abc")`                        | Error reporting |
| P9  | `backref_re2_forbidden`     | `re_test("^(a+)\\1$", "aaaa")`             | RE2 strictness on backrefs |
| P10 | `find_all_zero_width`       | `re_find_all("a*", "bbb")`                 | Zero-width `find_all` enumeration |

## Post-fix results (14 of 16 ports runnable in this env)

| Port       | P1 (ms) | P2 (ms) | P3 result    | P4 result      | P7    | P8                | P9        |
|------------|--------:|--------:|--------------|----------------|-------|-------------------|-----------|
| typescript |  180    | 3       | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| javascript |  179    | 3       | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| python     |  191    | 4       | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| ruby       |    0.04 | 0.05    | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| php        |    3    | 0.3     | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| perl       |    0.06 | 0.06    | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| go         |    0.03 | 0.02    | `"XbXcX"`    | `café/au/lait` | PANIC | PANIC             | PANIC     |
| rust       |    0.01 | 0.01    | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | non-match |
| java       |   13    | 0.2     | `"XXbXcX"`   | `caf?/au/lait` | OK    | ERR (clean)       | matches   |
| cpp        | **1190**| 24      | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| c          |    0.01 | 0.01    | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (NULL return) | non-match |
| lua        |    0.12 | 0.10    | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | non-match |
| csharp     |  393    | 8       | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| kotlin     |   24    | 0.3     | `"XXbXcX"`   | `café/au/lait` | OK    | ERR (clean)       | matches   |
| swift      | n/r     |         |              |                |       |                   |           |
| zig        | n/r     |         |              |                |       |                   |           |

n/r = toolchain unavailable in this environment.

## Fixes — porting variations resolved

1. **rust — stack overflow on `a{0,10000}b$`** (`rust/src/re.rs`).
   The Thompson engine's `add()` epsilon-closure was recursive; 10 000
   chained `Split` instructions blew the call stack with SIGABRT.
   Rewrote as iterative with an explicit work stack (priority preserved
   by pushing `y` then `x`). All 15 tests still pass; the in-tree corpus
   (1200 cases via the TS-shared spec) still passes.

2. **php — `re_compile` silently accepted invalid patterns**
   (`php/src/Struct.php`). The wrapper returned a delimited string
   without ever running PCRE on it, and every other helper used
   `@preg_match` to suppress warnings. Now `re_compile` issues a
   no-op `preg_match` to surface compile errors, throws
   `InvalidArgumentException` on failure, and the `@` is dropped from
   the read helpers. 85 PHPUnit tests still pass.

3. **c / lua — `re_replace("a*", "abc", "X")` returned `"XaXbXcX"`**
   (`c/src/regex.c`, `lua/src/regex.lua`). The in-tree Thompson NFA
   driver's `OP_MATCH` branch had `if (!found) { … }`, which froze
   the first match found and prevented surviving higher-priority
   threads from overriding at a later `sp`. That made greedy
   quantifiers behave lazily — `a*` matched empty at every position
   instead of consuming the leading `"a"`. Always overwriting on
   `OP_MATCH` (within the priority-pruned thread set) makes greedy
   `a*` consume the `"a"` correctly. C corpus 1200/1200 still passes;
   Lua regex unit tests 53/53 still pass.

4. **c — `re_find_all` missing from public header**
   (`c/src/voxgig_struct.h`, `c/src/re_util.c`). Added
   `vs_strvec_vec` + `vs_re_find_all` / `vs_re_find_all_re`. The
   engine already supported the operation; only the wrapper was
   missing.

5. **zig — `re_find` / `re_find_all` / `re_replace` not exposed**
   (`zig/src/struct.zig`, `zig/src/regex.zig`). The engine had
   `matchAt` but only `re_compile` / `re_test` / `re_escape` were
   public. Made `findFirst` public, added `findFrom(input, start)`,
   and added the three wrappers using the page allocator (matching
   the existing `re_test` style). **Not run in this environment**
   (no zig toolchain); the wrappers compile against the engine but
   need a host-side smoke pass.

6. **perl — discovery test showed `cafÃ©/au/lait`** (`perl/t/regex_pathological.t`).
   This turned out to be a test-script bug, not a port bug:
   `encode_json` returns UTF-8-encoded bytes and `binmode STDOUT,
   ':utf8'` then re-encoded them as Latin-1. Switched the test to
   `JSON::PP->new->utf8(0)->encode` so the `:utf8` layer encodes
   once. The Perl port's `re_replace` was correct all along.

**Deliberately not fixed — Go `re_replace` zero-width convention.**
Go's `regexp.ReplaceAllString` suppresses an empty match immediately
after a non-empty match at the same offset, so
`re_replace("a*", "abc", "X")` returns `"XbXcX"` here, not the
ECMA-canonical `"XXbXcX"`. This is RE2's chosen rule — it's
host-package behaviour we don't own. An earlier attempt wrapped
`ReplaceAllString` with a manual emit loop to align the output; it
was reverted in line with "don't modify inherent language regex
variance, just document it." Callers writing portable code should
not assume zero-width replacement semantics are identical across
ports.

## Irreconcilable — engine-bound, documented for callers

Cases where the host language's regex engine fundamentally differs
from another's. The cross-port contract documented in `REGEX.md`
already requires patterns to live in the RE2 subset; these are the
sharp edges that come with the host engines we don't own.

1. **P1 / P2 catastrophic backtracking.** ECMA / PCRE / .NET / Java
   regex engines use backtracking. `^(a+)+$` against 22 a's plus a
   non-match suffix is:
   - C++ libstdc++ `<regex>`: 1190 ms
   - C# `System.Text.RegularExpressions`: 393 ms
   - Python `re`: 191 ms
   - TS/JS `RegExp`: ~180 ms
   - Java `java.util.regex`: 13 ms
   - Ruby (Onigmo) / Perl / PHP (PCRE+JIT): <3 ms (engine-side ReDoS mitigations)
   - Go (RE2) / Rust (in-tree) / C / Lua (Thompson NFA): <0.1 ms (no backtracking)

   The RE2-subset contract avoids the worst classes (no backrefs,
   no lookaround), but nested quantifiers like `(a+)+` are still
   inside the subset and can still backtrack catastrophically on
   the non-RE2 engines. **Callers are responsible for writing
   linear-friendly patterns** (a single `a+` would already be
   linear on every engine here). See `REGEX.md` for the dialect.

2. **P7 — RE2's bounded-quantifier limit.** Go's stdlib `regexp`
   refuses to compile `a{0,10000}` with *"invalid repeat count"*:
   RE2 caps `{n,m}` at 1000 to keep the compiled program size
   bounded. Every other engine compiles it. Internal call sites
   in the corpus stay well below the limit; user-facing `$LIKE`
   operators should too. There is no portable workaround — RE2's
   limit is hard-coded in the host stdlib.

3. **P8 — Go panics on invalid pattern.** `ReCompile` is a
   passthrough to `regexp.MustCompile`, which panics. This is the
   Go-idiomatic shape and matches the throw/raise behaviour of
   every other port; callers wrap in `recover()` the same way other
   ports use `try/catch`. (Not a divergence in semantics — just in
   how the failure is named.)

4. **P9 — backreferences (`\1`, `(?P=name)`).** Three families:
   - PCRE / ECMAScript / .NET / Java / Onigmo / Perl: backrefs work.
     `^(a+)\1$` on "aaaa" matches.
   - Go (RE2): rejects at compile time (panics).
   - In-tree engines (Rust, C, Lua): parse `\1` as a literal "1"
     (or similar fallback) — the pattern compiles but never matches
     the back-reference semantically, so the test returns `false`.

   `REGEX.md` already documents this: **backreferences are outside
   the supported dialect.** None of the canonical patterns use them.
   The `$LIKE` operator does not document them. Callers that need
   backrefs are running outside the contract on every RE2-family
   port.

5. **P3 zero-width `replace_all` convention varies between engines.**
   `re_replace("a*", "abc", "X")` produces:
   - `"XXbXcX"` — every PCRE / ECMA / .NET / Java engine, plus the
     in-tree Thompson NFA ports (Rust, C, Lua) after the engine fix.
   - `"XbXcX"` — Go (RE2). RE2 deliberately suppresses an empty match
     that immediately follows a non-empty match at the same offset.
   This is inherent to RE2 / Go's `regexp` package; there is no
   portable workaround that doesn't replace the engine. Don't rely on
   zero-width replacement output being identical across ports.

6. **Java / .NET stdout encoding.** Java printed `caf?` for P4/P5,
   not because the regex returned the wrong string but because
   `System.out`'s default `PrintStream` uses the platform's default
   charset on JVMs without `-Dfile.encoding=UTF-8`. The in-memory
   `String` is correct UTF-16. .NET's default `Console.Out` is
   UTF-8 on .NET 6+, so C# was unaffected. This is orthogonal to
   the regex contract.

7. **Time-of-iteration variance on backtracking engines.** P1 / P2
   numbers vary across runs depending on JIT warmup, GC, and host
   load. The qualitative split (linear vs catastrophic) is stable;
   the specific milliseconds aren't a regression signal.

## Where the tests live

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
