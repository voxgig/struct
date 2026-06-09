/* Standalone smoke test for the vendored RE2-subset regex engine. */
#include "regex.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int passed = 0;
static int total = 0;

static void check(const char* pat, const char* input, bool expect, const char* label) {
  total++;
  char* err = NULL;
  voxgig_regex* re = voxgig_regex_compile(pat, &err);
  if (!re) {
    fprintf(stderr, "FAIL %s: compile failed for /%s/: %s\n", label, pat, err ? err : "?");
    free(err);
    return;
  }
  bool got = voxgig_regex_test(re, input, strlen(input));
  if (got == expect) {
    passed++;
  } else {
    fprintf(stderr, "FAIL %s: /%s/ on %s — expected %d got %d\n", label, pat, input, expect, got);
  }
  voxgig_regex_free(re);
}

int main(void) {
  /* Literal and anchors */
  check("hello", "say hello world", true, "literal sub");
  check("^cat", "cat sat", true, "^anchor hit");
  check("^cat", "a cat", false, "^anchor miss");
  check("end$", "the end", true, "$anchor hit");
  check("end$", "ended here", false, "$anchor miss");
  check("^abc$", "abc", true, "both anchors hit");
  check("^abc$", "xabc", false, "both anchors miss");

  /* Any-char */
  check("^a.c$", "abc", true, ".any hit");
  check("^a.c$", "ac", false, ".any miss");

  /* Quantifiers */
  check("^ab*c$", "ac", true, "* zero");
  check("^ab*c$", "abc", true, "* one");
  check("^ab*c$", "abbbc", true, "* many");
  check("^ab+c$", "ac", false, "+ zero miss");
  check("^ab+c$", "abc", true, "+ one");
  check("^colou?r$", "color", true, "? zero");
  check("^colou?r$", "colour", true, "? one");
  check("^colou?r$", "colouur", false, "? two miss");
  check("^a{3}$", "aaa", true, "{n}");
  check("^a{3}$", "aa", false, "{n} too few");
  check("^a{3}$", "aaaa", false, "{n} too many");
  check("^a{2,4}$", "aa", true, "{n,m} lo");
  check("^a{2,4}$", "aaa", true, "{n,m} mid");
  check("^a{2,4}$", "aaaa", true, "{n,m} hi");
  check("^a{2,4}$", "a", false, "{n,m} too few");
  check("^a{2,4}$", "aaaaa", false, "{n,m} too many");
  check("^a{2,}$", "aa", true, "{n,}");
  check("^a{2,}$", "aaaa", true, "{n,} many");

  /* Char classes */
  check("^[abc]$", "a", true, "class hit");
  check("^[abc]$", "d", false, "class miss");
  check("^[^xyz]$", "a", true, "neg class hit");
  check("^[^xyz]$", "x", false, "neg class miss");
  check("^[0-9]+$", "123", true, "range");
  check("^[0-9]+$", "12a", false, "range miss");

  /* Predefined classes */
  check("^\\d{3}$", "123", true, "\\d hit");
  check("^\\d{3}$", "abc", false, "\\d miss");
  check("^\\w+$", "abc_123", true, "\\w hit");
  check("^\\w+$", "hi there", false, "\\w miss");
  check("^a\\sb$", "a b", true, "\\s space");
  check("^a\\sb$", "a\tb", true, "\\s tab");
  check("^a\\sb$", "ab", false, "\\s miss");
  check("^\\D+$", "abc", true, "\\D hit");
  check("^\\D+$", "a1", false, "\\D miss");

  /* Alternation + groups */
  check("^(cat|dog)$", "cat", true, "alt cat");
  check("^(cat|dog)$", "dog", true, "alt dog");
  check("^(cat|dog)$", "fish", false, "alt miss");
  check("^(?:ab|cd)+$", "ab", true, "non-cap +");
  check("^(?:ab|cd)+$", "abcd", true, "non-cap + two");
  check("^(?:ab|cd)+$", "abc", false, "non-cap + miss");
  check("^a(bc)+d$", "abcd", true, "cap + once");
  check("^a(bc)+d$", "abcbcd", true, "cap + twice");
  check("^a(bc)+d$", "ad", false, "cap + miss");

  /* Word boundary */
  check("\\bword\\b", "a word here", true, "\\b word");
  check("\\bword\\b", "sword", false, "\\b inside");
  check("\\bword\\b", "word!", true, "\\b before punct");

  /* Escaped meta */
  check("^a\\.b$", "a.b", true, "escaped .");
  check("^a\\.b$", "aXb", false, "escaped . strict");

  /* Lazy */
  check("^a.*?b$", "ab", true, "lazy zero");
  check("^a.*?b$", "aXXXb", true, "lazy many");
  check("^a.*?b$", "aXY", false, "lazy no end");

  /* The original problem case */
  check("[aA][bB][cC]", "ABc", true, "case-classes hit");
  check("[aA][bB][cC]", "DEf", false, "case-classes miss");

  printf("regex engine: %d/%d passed\n", passed, total);
  return passed == total ? 0 : 1;
}
