/* Copyright (c) 2025-2026 Voxgig Ltd. MIT LICENSE.
 *
 * Voxgig Struct — RE2-subset regex engine (pure C, no runtime deps).
 *
 * Dialect:
 *   - Literal chars and escapes (\n \t \\ \. ...)
 *   - Any char (.)
 *   - Anchors (^ $)
 *   - Quantifiers: * + ? {n} {n,} {n,m}, plus lazy *? +? ?? {..}?
 *   - Character classes: [abc] [^abc] [a-z] (predefined classes inside too)
 *   - Predefined classes: \d \D \s \S \w \W
 *   - Word boundary: \b \B
 *   - Groups: (...) and (?:...)
 *   - Alternation: a|b
 *
 * Not supported (out of RE2 too):
 *   - Backreferences, lookaround, possessive quantifiers, atomic groups.
 *
 * The matcher is a Thompson-NFA driver with explicit instruction set.
 * Performance: O(n*m). Captures supported up to VOXGIG_REGEX_MAX_GROUPS.
 */

#ifndef VOXGIG_STRUCT_REGEX_H
#define VOXGIG_STRUCT_REGEX_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VOXGIG_REGEX_MAX_GROUPS 16

typedef struct voxgig_regex voxgig_regex;

/* Compile a pattern. Returns NULL on syntax error; if `err` is non-NULL it
 * receives a malloc'd diagnostic (caller frees). */
voxgig_regex* voxgig_regex_compile(const char* pattern, char** err);

/* Free a compiled regex. */
void voxgig_regex_free(voxgig_regex* re);

/* Find the first match in `input[0..ilen)`. On success returns true and (if
 * `caps` non-NULL) fills caps with up to `ncaps` capture pairs:
 *   caps[2*i+0] = start offset (inclusive)
 *   caps[2*i+1] = end   offset (exclusive)
 * Group 0 is the whole match. Unmatched groups get (-1, -1). */
bool voxgig_regex_find(const voxgig_regex* re, const char* input, size_t ilen, int* caps,
                       int ncaps);

/* Boolean shortcut. */
bool voxgig_regex_test(const voxgig_regex* re, const char* input, size_t ilen);

/* Find all non-overlapping matches. Caller provides an integer array `caps`
 * of size `max_matches * 2 * VOXGIG_REGEX_MAX_GROUPS`. Returns the count.
 * caps[m * 2*VOXGIG_REGEX_MAX_GROUPS + 2*g + (0|1)] = group g's start/end for match m. */
int voxgig_regex_find_all(const voxgig_regex* re, const char* input, size_t ilen, int* caps,
                          int max_matches);

/* Replace every match in `input`. `replacement` may contain $& (whole match)
 * and $1..$9 (capture references). Returns a malloc'd C string (caller
 * frees). Returns NULL on allocation failure. */
char* voxgig_regex_replace(const voxgig_regex* re, const char* input, size_t ilen,
                           const char* replacement);

/* Callback variant: `cb` receives the captures array (length 2*ncaps where
 * ncaps is the number of groups in the regex + 1 for the whole match), the
 * input buffer, and `ud`. It returns a malloc'd replacement string for this
 * match. */
typedef char* (*voxgig_regex_replace_cb)(const int* caps, int ncaps, const char* input, void* ud);

char* voxgig_regex_replace_cb_fn(const voxgig_regex* re, const char* input, size_t ilen,
                                 voxgig_regex_replace_cb cb, void* ud);

/* Number of capture groups in the compiled regex (group 0 plus parenthesised
 * non-passthrough groups; (?:...) is not counted). */
int voxgig_regex_ngroups(const voxgig_regex* re);

#ifdef __cplusplus
}
#endif

#endif
