"use strict";
var __classPrivateFieldSet = (this && this.__classPrivateFieldSet) || function (receiver, state, value, kind, f) {
    if (kind === "m") throw new TypeError("Private method is not writable");
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a setter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot write private member to an object whose class did not declare it");
    return (kind === "a" ? f.call(receiver, value) : f ? f.value = value : state.set(receiver, value)), value;
};
var __classPrivateFieldGet = (this && this.__classPrivateFieldGet) || function (receiver, state, kind, f) {
    if (kind === "a" && !f) throw new TypeError("Private accessor was defined without a getter");
    if (typeof state === "function" ? receiver !== state || !f : !state.has(receiver)) throw new TypeError("Cannot read private member from an object whose class did not declare it");
    return kind === "m" ? f : kind === "a" ? f.call(receiver) : f ? f.value : state.get(receiver);
};
var _SDK_opts, _SDK_utility;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SDK = void 0;
const StructUtility_1 = require("../dist/StructUtility");
class SDK {
    constructor(opts) {
        _SDK_opts.set(this, {});
        _SDK_utility.set(this, {});
        __classPrivateFieldSet(this, _SDK_opts, opts || {}, "f");
        __classPrivateFieldSet(this, _SDK_utility, {
            struct: new StructUtility_1.StructUtility(),
            contextify: (ctxmap) => ctxmap,
            makeContext: (ctxmap) => ctxmap,
            check: (ctx) => {
                return {
                    zed: 'ZED' +
                        (null == __classPrivateFieldGet(this, _SDK_opts, "f") ? '' : null == __classPrivateFieldGet(this, _SDK_opts, "f").foo ? '' : __classPrivateFieldGet(this, _SDK_opts, "f").foo) +
                        '_' +
                        (null == ctx.meta?.bar ? '0' : ctx.meta.bar),
                };
            },
        }, "f");
    }
    static async test(opts) {
        return new SDK(opts);
    }
    async tester(opts) {
        return new SDK(opts || __classPrivateFieldGet(this, _SDK_opts, "f"));
    }
    utility() {
        return __classPrivateFieldGet(this, _SDK_utility, "f");
    }
}
exports.SDK = SDK;
_SDK_opts = new WeakMap(), _SDK_utility = new WeakMap();
//# sourceMappingURL=sdk.js.map