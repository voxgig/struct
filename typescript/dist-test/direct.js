"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const __1 = require("..");
const errs = [];
const extra = {
    $CAPTURE: (inj) => {
        if (__1.M_KEYPRE === inj.mode) {
            const { val, prior } = inj;
            const { dparent, key } = prior;
            const dval = dparent[key];
            if (undefined !== dval) {
                inj.meta.capture[val] = dval;
            }
        }
    },
};
const meta = { capture: {} };
const out = (0, __1.transform)({ a: { b: 1, c: 2 } }, { a: { b: { '`$CAPTURE`': 'x' }, c: { '`$CAPTURE`': 'x' } } }, { extra, errs, meta });
console.dir(out, { depth: null });
console.dir(errs, { depth: null });
console.dir(meta, { depth: null });
//# sourceMappingURL=direct.js.map