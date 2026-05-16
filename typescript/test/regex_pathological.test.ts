// VERSION: @voxgig/struct 0.1.0
//
// Discovery test: pathological regex inputs run against the port's re_* API.
// Each case wraps the call so one failure does not mask the others.
// The panel is the same in every port (see REGEX.md).

import { test } from 'node:test'

import {
  re_compile, re_test, re_find, re_find_all, re_replace,
} from '../dist/StructUtility'

function rep(s: string, n: number): string {
  return new Array(n + 1).join(s)
}

function record(label: string, fn: () => unknown): void {
  const t0 = process.hrtime.bigint()
  let outcome: string
  try {
    const r = fn()
    outcome = `OK | ${JSON.stringify(r)}`
  } catch (e: any) {
    outcome = `ERR | ${e && e.message ? e.message : String(e)}`
  }
  const ms = Number(process.hrtime.bigint() - t0) / 1e6
  // eslint-disable-next-line no-console
  console.log(`[regex-discovery] ${label} | ${ms.toFixed(2)}ms | ${outcome}`)
}

test('regex pathological discovery', () => {
  const A22 = rep('a', 22)
  const NEST40 = rep('(', 40) + 'a' + rep(')', 40)

  record('P1_redos_nested_plus',     () => re_test('^(a+)+$', A22 + '!'))
  record('P2_redos_alt_overlap',     () => re_test('^(a|aa)+$', A22 + '!'))
  record('P3_empty_repeat_replace',  () => re_replace('a*', 'abc', 'X'))
  record('P4_unicode_replace_dot',   () => re_replace('\\.', 'café.au.lait', '/'))
  record('P5_unicode_find_codepoint',() => re_find('é', 'café au lait'))
  record('P6_deep_nesting_compile',  () => re_test(NEST40, 'a'))
  record('P7_big_bounded_quantifier',() => re_test('^a{0,10000}b$', rep('a', 10) + 'b'))
  record('P8_invalid_pattern',       () => re_compile('[abc'))
  record('P9_backref_re2_forbidden', () => re_test('^(a+)\\1$', 'aaaa'))
  record('P10_find_all_zero_width',  () => re_find_all('a*', 'bbb'))
})
