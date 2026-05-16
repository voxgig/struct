"use strict";
// VERSION: @voxgig/struct 0.1.0
//
// Discovery test: pathological regex inputs run against the port's re_* API.
// Each case wraps the call so one failure does not mask the others.
// The panel is the same in every port (see REGEX.md).
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const StructUtility_1 = require("../dist/StructUtility");
function rep(s, n) {
    return new Array(n + 1).join(s);
}
function record(label, fn) {
    const t0 = process.hrtime.bigint();
    let outcome;
    try {
        const r = fn();
        outcome = `OK | ${JSON.stringify(r)}`;
    }
    catch (e) {
        outcome = `ERR | ${e && e.message ? e.message : String(e)}`;
    }
    const ms = Number(process.hrtime.bigint() - t0) / 1e6;
    // eslint-disable-next-line no-console
    console.log(`[regex-discovery] ${label} | ${ms.toFixed(2)}ms | ${outcome}`);
}
(0, node_test_1.test)('regex pathological discovery', () => {
    const A22 = rep('a', 22);
    const NEST40 = rep('(', 40) + 'a' + rep(')', 40);
    record('P1_redos_nested_plus', () => (0, StructUtility_1.re_test)('^(a+)+$', A22 + '!'));
    record('P2_redos_alt_overlap', () => (0, StructUtility_1.re_test)('^(a|aa)+$', A22 + '!'));
    record('P3_empty_repeat_replace', () => (0, StructUtility_1.re_replace)('a*', 'abc', 'X'));
    record('P4_unicode_replace_dot', () => (0, StructUtility_1.re_replace)('\\.', 'café.au.lait', '/'));
    record('P5_unicode_find_codepoint', () => (0, StructUtility_1.re_find)('é', 'café au lait'));
    record('P6_deep_nesting_compile', () => (0, StructUtility_1.re_test)(NEST40, 'a'));
    record('P7_big_bounded_quantifier', () => (0, StructUtility_1.re_test)('^a{0,10000}b$', rep('a', 10) + 'b'));
    record('P8_invalid_pattern', () => (0, StructUtility_1.re_compile)('[abc'));
    record('P9_backref_re2_forbidden', () => (0, StructUtility_1.re_test)('^(a+)\\1$', 'aaaa'));
    record('P10_find_all_zero_width', () => (0, StructUtility_1.re_find_all)('a*', 'bbb'));
});
//# sourceMappingURL=regex_pathological.test.js.map