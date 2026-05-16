/* Discovery test: pathological regex inputs run against the port's vs_re_*
 * API. Goal is to surface failures across ports, not to assert behaviour.
 * The panel is the same in every port (see REGEX.md).
 *
 * C has no exception machinery, so this records the return value (or NULL)
 * for each case. A crash here means the engine aborted on that input.
 */

#include "voxgig_struct.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static char* repeat(char c, size_t n) {
  char* s = (char*)malloc(n + 1);
  memset(s, c, n);
  s[n] = '\0';
  return s;
}

static void print_strvec(const vs_strvec* v) {
  printf("[");
  for (size_t i = 0; i < v->len; i++) {
    printf("%s\"%s\"", i ? "," : "", v->data[i] ? v->data[i] : "");
  }
  printf("]");
}

int main(void) {
  char* a22 = repeat('a', 22);
  char* p1_in = (char*)malloc(strlen(a22) + 2);
  sprintf(p1_in, "%s!", a22);

  char* opens = repeat('(', 40);
  char* closes = repeat(')', 40);
  char* nest40 = (char*)malloc(40 + 1 + 40 + 1);
  sprintf(nest40, "%sa%s", opens, closes);

  double t0, ms;

  /* P1 */
  t0 = now_ms();
  bool b1 = vs_re_test("^(a+)+$", p1_in);
  ms = now_ms() - t0;
  printf("[regex-discovery] P1_redos_nested_plus | %.2fms | OK | %s\n", ms, b1 ? "true" : "false");

  /* P2 */
  t0 = now_ms();
  bool b2 = vs_re_test("^(a|aa)+$", p1_in);
  ms = now_ms() - t0;
  printf("[regex-discovery] P2_redos_alt_overlap | %.2fms | OK | %s\n", ms, b2 ? "true" : "false");

  /* P3 */
  t0 = now_ms();
  char* p3 = vs_re_replace("a*", "abc", "X");
  ms = now_ms() - t0;
  printf("[regex-discovery] P3_empty_repeat_replace | %.2fms | OK | \"%s\"\n", ms, p3 ? p3 : "(null)");
  free(p3);

  /* P4 */
  t0 = now_ms();
  char* p4 = vs_re_replace("\\.", "café.au.lait", "/");
  ms = now_ms() - t0;
  printf("[regex-discovery] P4_unicode_replace_dot | %.2fms | OK | \"%s\"\n", ms, p4 ? p4 : "(null)");
  free(p4);

  /* P5 */
  t0 = now_ms();
  vs_strvec p5 = vs_re_find("é", "café au lait");
  ms = now_ms() - t0;
  printf("[regex-discovery] P5_unicode_find_codepoint | %.2fms | OK | ", ms);
  print_strvec(&p5);
  printf("\n");
  vs_strvec_free(&p5);

  /* P6 */
  t0 = now_ms();
  bool b6 = vs_re_test(nest40, "a");
  ms = now_ms() - t0;
  printf("[regex-discovery] P6_deep_nesting_compile | %.2fms | OK | %s\n", ms, b6 ? "true" : "false");

  /* P7 */
  t0 = now_ms();
  char* p7_in = (char*)malloc(12);
  sprintf(p7_in, "%sb", "aaaaaaaaaa");
  bool b7 = vs_re_test("^a{0,10000}b$", p7_in);
  ms = now_ms() - t0;
  printf("[regex-discovery] P7_big_bounded_quantifier | %.2fms | OK | %s\n", ms, b7 ? "true" : "false");
  free(p7_in);

  /* P8 — invalid pattern. vs_re_compile returns NULL on error. */
  t0 = now_ms();
  vs_regex* p8 = vs_re_compile("[abc");
  ms = now_ms() - t0;
  if (p8) {
    printf("[regex-discovery] P8_invalid_pattern | %.2fms | OK | \"compiled-without-error\"\n", ms);
    /* leak: no vs_regex_free in public header */
  } else {
    printf("[regex-discovery] P8_invalid_pattern | %.2fms | ERR | compile returned NULL\n", ms);
  }

  /* P9 */
  t0 = now_ms();
  bool b9 = vs_re_test("^(a+)\\1$", "aaaa");
  ms = now_ms() - t0;
  printf("[regex-discovery] P9_backref_re2_forbidden | %.2fms | OK | %s\n", ms, b9 ? "true" : "false");

  /* P10 */
  t0 = now_ms();
  vs_strvec_vec p10 = vs_re_find_all("a*", "bbb");
  ms = now_ms() - t0;
  printf("[regex-discovery] P10_find_all_zero_width | %.2fms | OK | [", ms);
  for (size_t i = 0; i < p10.len; i++) {
    if (i) printf(",");
    print_strvec(&p10.data[i]);
  }
  printf("]\n");
  vs_strvec_vec_free(&p10);

  free(a22);
  free(p1_in);
  free(opens);
  free(closes);
  free(nest40);
  return 0;
}
