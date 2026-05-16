# RUN: python -m unittest discover -s tests
#
# Discovery test: pathological regex inputs run against the port's re_* API.
# The goal is to surface which inputs cause errors, hangs, or surprising
# output across ports — NOT to assert any specific behaviour. Each case
# wraps the call so one failure does not mask the others.
# The panel is the same in every port (see REGEX.md).

import json
import time
import unittest

from voxgig_struct.voxgig_struct import (
    re_compile,
    re_find,
    re_find_all,
    re_replace,
    re_test,
)


def record(label, fn):
    t0 = time.perf_counter()
    try:
        r = fn()
        outcome = f'OK | {json.dumps(r, default=str)}'
    except Exception as e:
        outcome = f'ERR | {type(e).__name__}: {e}'
    ms = (time.perf_counter() - t0) * 1000.0
    print(f'[regex-discovery] {label} | {ms:.2f}ms | {outcome}')


class PathologicalRegex(unittest.TestCase):
    def test_panel(self):
        A22 = 'a' * 22
        NEST40 = '(' * 40 + 'a' + ')' * 40

        record('P1_redos_nested_plus', lambda: re_test('^(a+)+$', A22 + '!'))
        record('P2_redos_alt_overlap', lambda: re_test('^(a|aa)+$', A22 + '!'))
        record('P3_empty_repeat_replace', lambda: re_replace('a*', 'abc', 'X'))
        record('P4_unicode_replace_dot', lambda: re_replace(r'\.', 'café.au.lait', '/'))
        record('P5_unicode_find_codepoint', lambda: re_find('é', 'café au lait'))
        record('P6_deep_nesting_compile', lambda: re_test(NEST40, 'a'))
        record('P7_big_bounded_quantifier', lambda: re_test('^a{0,10000}b$', 'a' * 10 + 'b'))
        record('P8_invalid_pattern', lambda: re_compile('[abc'))
        record('P9_backref_re2_forbidden', lambda: re_test(r'^(a+)\1$', 'aaaa'))
        record('P10_find_all_zero_width', lambda: re_find_all('a*', 'bbb'))


if __name__ == '__main__':
    unittest.main()
