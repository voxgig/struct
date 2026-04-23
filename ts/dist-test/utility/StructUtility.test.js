"use strict";
// VERSION: @voxgig/struct 0.1.0
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const runner_1 = require("../runner");
const index_1 = require("./index");
const { equal, deepEqual } = node_assert_1.default;
// NOTE: tests are (mostly) in order of increasing dependence.
(0, node_test_1.describe)('StructUtility', async () => {
    let spec;
    let runset;
    let runsetflags;
    let client;
    let struct;
    (0, node_test_1.before)(async () => {
        const runner = await (0, runner_1.makeRunner)(index_1.TEST_JSON_FILE, await index_1.SDK.test());
        const runner_struct = await runner('struct');
        spec = runner_struct.spec;
        runset = runner_struct.runset;
        runsetflags = runner_struct.runsetflags;
        client = runner_struct.client;
        struct = client.utility().struct;
    });
    (0, node_test_1.test)('exists', () => {
        const s = struct;
        equal('function', typeof s.clone);
        equal('function', typeof s.delprop);
        equal('function', typeof s.escre);
        equal('function', typeof s.escurl);
        equal('function', typeof s.filter);
        equal('function', typeof s.flatten);
        equal('function', typeof s.getelem);
        equal('function', typeof s.getprop);
        equal('function', typeof s.getpath);
        equal('function', typeof s.haskey);
        equal('function', typeof s.inject);
        equal('function', typeof s.isempty);
        equal('function', typeof s.isfunc);
        equal('function', typeof s.iskey);
        equal('function', typeof s.islist);
        equal('function', typeof s.ismap);
        equal('function', typeof s.isnode);
        equal('function', typeof s.items);
        equal('function', typeof s.join);
        equal('function', typeof s.jsonify);
        equal('function', typeof s.keysof);
        equal('function', typeof s.merge);
        equal('function', typeof s.pad);
        equal('function', typeof s.pathify);
        equal('function', typeof s.select);
        equal('function', typeof s.setpath);
        equal('function', typeof s.size);
        equal('function', typeof s.slice);
        equal('function', typeof s.setprop);
        equal('function', typeof s.strkey);
        equal('function', typeof s.stringify);
        equal('function', typeof s.transform);
        equal('function', typeof s.typify);
        equal('function', typeof s.typename);
        equal('function', typeof s.validate);
        equal('function', typeof s.walk);
    });
    // minor tests
    // ===========
    (0, node_test_1.test)('minor-isnode', async () => {
        await runset(spec.minor.isnode, struct.isnode);
    });
    (0, node_test_1.test)('minor-ismap', async () => {
        await runset(spec.minor.ismap, struct.ismap);
    });
    (0, node_test_1.test)('minor-islist', async () => {
        await runset(spec.minor.islist, struct.islist);
    });
    (0, node_test_1.test)('minor-iskey', async () => {
        await runsetflags(spec.minor.iskey, { null: false }, struct.iskey);
    });
    (0, node_test_1.test)('minor-strkey', async () => {
        await runsetflags(spec.minor.strkey, { null: false }, struct.strkey);
    });
    (0, node_test_1.test)('minor-isempty', async () => {
        await runsetflags(spec.minor.isempty, { null: false }, struct.isempty);
    });
    (0, node_test_1.test)('minor-isfunc', async () => {
        const { isfunc } = struct;
        await runset(spec.minor.isfunc, isfunc);
        function f0() { return null; }
        equal(isfunc(f0), true);
        equal(isfunc(() => null), true);
    });
    (0, node_test_1.test)('minor-clone', async () => {
        await runsetflags(spec.minor.clone, { null: false }, struct.clone);
    });
    (0, node_test_1.test)('minor-edge-clone', async () => {
        const { clone } = struct;
        const f0 = () => null;
        deepEqual({ a: f0 }, clone({ a: f0 }));
        const x = { y: 1 };
        let xc = clone(x);
        deepEqual(x, xc);
        (0, node_assert_1.default)(x !== xc);
        class A {
            constructor() {
                this.x = 1;
            }
        }
        const a = new A();
        let ac = clone(a);
        deepEqual(a, ac);
        (0, node_assert_1.default)(a === ac);
        equal(a.constructor.name, ac.constructor.name);
    });
    (0, node_test_1.test)('minor-filter', async () => {
        const checkmap = {
            gt3: (n) => n[1] > 3,
            lt3: (n) => n[1] < 3,
        };
        await runset(spec.minor.filter, (vin) => struct.filter(vin.val, checkmap[vin.check]));
    });
    (0, node_test_1.test)('minor-flatten', async () => {
        await runset(spec.minor.flatten, (vin) => struct.flatten(vin.val, vin.depth));
    });
    (0, node_test_1.test)('minor-escre', async () => {
        await runset(spec.minor.escre, struct.escre);
    });
    (0, node_test_1.test)('minor-escurl', async () => {
        await runset(spec.minor.escurl, struct.escurl);
    });
    (0, node_test_1.test)('minor-stringify', async () => {
        await runset(spec.minor.stringify, (vin) => struct.stringify((runner_1.NULLMARK === vin.val ? "null" : vin.val), vin.max));
    });
    (0, node_test_1.test)('minor-edge-stringify', async () => {
        const { stringify } = struct;
        const a = {};
        a.a = a;
        equal(stringify(a), '__STRINGIFY_FAILED__');
        equal(stringify({ a: [9] }, -1, true), '\x1B[38;5;81m\x1B[38;5;118m{\x1B[38;5;118ma\x1B[38;5;118m:' +
            '\x1B[38;5;213m[\x1B[38;5;213m9\x1B[38;5;213m]\x1B[38;5;118m}\x1B[0m');
    });
    (0, node_test_1.test)('minor-jsonify', async () => {
        await runsetflags(spec.minor.jsonify, { null: false }, (vin) => struct.jsonify(vin.val, vin.flags));
    });
    (0, node_test_1.test)('minor-edge-jsonify', async () => {
        const { jsonify } = struct;
        equal(jsonify(() => 1), 'null');
    });
    (0, node_test_1.test)('minor-pathify', async () => {
        await runsetflags(spec.minor.pathify, { null: true }, (vin) => {
            let path = runner_1.NULLMARK == vin.path ? undefined : vin.path;
            let pathstr = struct.pathify(path, vin.from).replace('__NULL__.', '');
            pathstr = runner_1.NULLMARK === vin.path ? pathstr.replace('>', ':null>') : pathstr;
            return pathstr;
        });
    });
    (0, node_test_1.test)('minor-items', async () => {
        await runset(spec.minor.items, struct.items);
    });
    (0, node_test_1.test)('minor-edge-items', async () => {
        const { items } = struct;
        const a0 = [11, 22, 33];
        a0.x = 1;
        deepEqual(items(a0), [['0', 11], ['1', 22], ['2', 33]]);
    });
    (0, node_test_1.test)('minor-getelem', async () => {
        const { getelem } = struct;
        await runsetflags(spec.minor.getelem, { null: false }, (vin) => null == vin.alt ? getelem(vin.val, vin.key) : getelem(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('minor-edge-getelem', async () => {
        const { getelem } = struct;
        equal(getelem([], 1, () => 2), 2);
    });
    (0, node_test_1.test)('minor-getprop', async () => {
        const { getprop } = struct;
        await runsetflags(spec.minor.getprop, { null: false }, (vin) => undefined === vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('minor-edge-getprop', async () => {
        const { getprop } = struct;
        let strarr = ['a', 'b', 'c', 'd', 'e'];
        deepEqual(getprop(strarr, 2), 'c');
        deepEqual(getprop(strarr, '2'), 'c');
        let intarr = [2, 3, 5, 7, 11];
        deepEqual(getprop(intarr, 2), 5);
        deepEqual(getprop(intarr, '2'), 5);
    });
    (0, node_test_1.test)('minor-setprop', async () => {
        await runset(spec.minor.setprop, (vin) => struct.setprop(vin.parent, vin.key, vin.val));
    });
    (0, node_test_1.test)('minor-edge-setprop', async () => {
        const { setprop } = struct;
        let strarr0 = ['a', 'b', 'c', 'd', 'e'];
        let strarr1 = ['a', 'b', 'c', 'd', 'e'];
        deepEqual(setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e']);
        deepEqual(setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e']);
        let intarr0 = [2, 3, 5, 7, 11];
        let intarr1 = [2, 3, 5, 7, 11];
        deepEqual(setprop(intarr0, 2, 55), [2, 3, 55, 7, 11]);
        deepEqual(setprop(intarr1, '2', 555), [2, 3, 555, 7, 11]);
    });
    (0, node_test_1.test)('minor-delprop', async () => {
        await runset(spec.minor.delprop, (vin) => struct.delprop(vin.parent, vin.key));
    });
    (0, node_test_1.test)('minor-edge-delprop', async () => {
        const { delprop } = struct;
        let strarr0 = ['a', 'b', 'c', 'd', 'e'];
        let strarr1 = ['a', 'b', 'c', 'd', 'e'];
        deepEqual(delprop(strarr0, 2), ['a', 'b', 'd', 'e']);
        deepEqual(delprop(strarr1, '2'), ['a', 'b', 'd', 'e']);
        let intarr0 = [2, 3, 5, 7, 11];
        let intarr1 = [2, 3, 5, 7, 11];
        deepEqual(delprop(intarr0, 2), [2, 3, 7, 11]);
        deepEqual(delprop(intarr1, '2'), [2, 3, 7, 11]);
    });
    (0, node_test_1.test)('minor-haskey', async () => {
        await runsetflags(spec.minor.haskey, { null: false }, (vin) => struct.haskey(vin.src, vin.key));
    });
    (0, node_test_1.test)('minor-keysof', async () => {
        await runset(spec.minor.keysof, struct.keysof);
    });
    (0, node_test_1.test)('minor-edge-keysof', async () => {
        const { keysof } = struct;
        const a0 = [11, 22, 33];
        a0.x = 1;
        deepEqual(keysof(a0), [0, 1, 2]);
    });
    (0, node_test_1.test)('minor-join', async () => {
        await runsetflags(spec.minor.join, { null: false }, (vin) => struct.join(vin.val, vin.sep, vin.url));
    });
    (0, node_test_1.test)('minor-typename', async () => {
        await runset(spec.minor.typename, struct.typename);
    });
    (0, node_test_1.test)('minor-typify', async () => {
        await runsetflags(spec.minor.typify, { null: false }, struct.typify);
    });
    (0, node_test_1.test)('minor-edge-typify', async () => {
        const { typify, T_noval, T_scalar, T_function, T_symbol, T_any, T_node, T_instance, T_null } = struct;
        class X {
        }
        const x = new X();
        equal(typify(), T_noval);
        equal(typify(undefined), T_noval);
        equal(typify(NaN), T_noval);
        equal(typify(null), T_scalar | T_null);
        equal(typify(() => null), T_scalar | T_function);
        equal(typify(Symbol('S')), T_scalar | T_symbol);
        equal(typify(BigInt(1)), T_any);
        equal(typify(x), T_node | T_instance);
    });
    (0, node_test_1.test)('minor-size', async () => {
        await runsetflags(spec.minor.size, { null: false }, struct.size);
    });
    (0, node_test_1.test)('minor-slice', async () => {
        await runsetflags(spec.minor.slice, { null: false }, (vin) => struct.slice(vin.val, vin.start, vin.end));
    });
    (0, node_test_1.test)('minor-pad', async () => {
        await runsetflags(spec.minor.pad, { null: false }, (vin) => struct.pad(vin.val, vin.pad, vin.char));
    });
    (0, node_test_1.test)('minor-setpath', async () => {
        await runsetflags(spec.minor.setpath, { null: false }, (vin) => struct.setpath(vin.store, vin.path, vin.val));
    });
    (0, node_test_1.test)('minor-edge-setpath', async () => {
        const { setpath, DELETE } = struct;
        const x = { y: { z: 1, q: 2 } };
        deepEqual(setpath(x, 'y.q', DELETE), { z: 1 });
        deepEqual(x, { y: { z: 1 } });
    });
    // walk tests
    // ==========
    (0, node_test_1.test)('walk-log', async () => {
        const { clone, stringify, pathify, walk } = struct;
        const test = clone(spec.walk.log);
        let log = [];
        function walklog(key, val, parent, path) {
            log.push('k=' + stringify(key) +
                ', v=' + stringify(val) +
                ', p=' + stringify(parent) +
                ', t=' + pathify(path));
            return val;
        }
        walk(test.in, undefined, walklog);
        deepEqual(log, test.out.after);
        log = [];
        walk(test.in, walklog);
        deepEqual(log, test.out.before);
        log = [];
        walk(test.in, walklog, walklog);
        deepEqual(log, test.out.both);
    });
    (0, node_test_1.test)('walk-basic', async () => {
        function walkpath(_key, val, _parent, path) {
            return 'string' === typeof val ? val + '~' + path.join('.') : val;
        }
        await runset(spec.walk.basic, (vin) => struct.walk(vin, walkpath));
    });
    (0, node_test_1.test)('walk-depth', async () => {
        await runsetflags(spec.walk.depth, { null: false }, (vin) => {
            let top = undefined;
            let cur = undefined;
            function copy(key, val, _parent, _path) {
                if (undefined === key || struct.isnode(val)) {
                    let child = struct.islist(val) ? [] : {};
                    if (undefined === key) {
                        top = cur = child;
                    }
                    else {
                        cur = cur[key] = child;
                    }
                }
                else {
                    cur[key] = val;
                }
                return val;
            }
            struct.walk(vin.src, copy, undefined, vin.maxdepth);
            return top;
        });
    });
    (0, node_test_1.test)('walk-copy', async () => {
        const { walk, isnode, ismap, islist, size, setprop } = struct;
        let cur;
        function walkcopy(key, val, _parent, path) {
            if (undefined === key) {
                cur = [];
                cur[0] = ismap(val) ? {} : islist(val) ? [] : val;
                return val;
            }
            let v = val;
            let i = size(path);
            if (isnode(v)) {
                v = cur[i] = ismap(v) ? {} : [];
            }
            setprop(cur[i - 1], key, v);
            return val;
        }
        await runset(spec.walk.copy, (vin) => (walk(vin, walkcopy), cur[0]));
    });
    // merge tests
    // ===========
    (0, node_test_1.test)('merge-basic', async () => {
        const { clone, merge } = struct;
        const test = clone(spec.merge.basic);
        deepEqual(merge(test.in), test.out);
    });
    (0, node_test_1.test)('merge-cases', async () => {
        await runset(spec.merge.cases, struct.merge);
    });
    (0, node_test_1.test)('merge-array', async () => {
        await runset(spec.merge.array, struct.merge);
    });
    (0, node_test_1.test)('merge-integrity', async () => {
        await runset(spec.merge.integrity, struct.merge);
    });
    (0, node_test_1.test)('merge-depth', async () => {
        await runset(spec.merge.depth, (vin) => struct.merge(vin.val, vin.depth));
    });
    (0, node_test_1.test)('merge-special', async () => {
        const { merge } = struct;
        const f0 = () => null;
        deepEqual(merge([f0]), f0);
        deepEqual(merge([null, f0]), f0);
        deepEqual(merge([{ a: f0 }]), { a: f0 });
        deepEqual(merge([[f0]]), [f0]);
        deepEqual(merge([{ a: { b: f0 } }]), { a: { b: f0 } });
        // JavaScript only
        deepEqual(merge([{ a: global.fetch }]), { a: global.fetch });
        deepEqual(merge([[global.fetch]]), [global.fetch]);
        deepEqual(merge([{ a: { b: global.fetch } }]), { a: { b: global.fetch } });
        class Bar {
            constructor() {
                this.x = 1;
            }
        }
        const b0 = new Bar();
        let out;
        equal(merge([{ x: 10 }, b0]), b0);
        equal(b0.x, 1);
        equal(b0 instanceof Bar, true);
        deepEqual(merge([{ a: b0 }, { a: { x: 11 } }]), { a: { x: 11 } });
        equal(b0.x, 1);
        equal(b0 instanceof Bar, true);
        deepEqual(merge([b0, { x: 20 }]), { x: 20 });
        equal(b0.x, 1);
        equal(b0 instanceof Bar, true);
        out = merge([{ a: { x: 21 } }, { a: b0 }]);
        deepEqual(out, { a: b0 });
        equal(b0, out.a);
        equal(b0.x, 1);
        equal(b0 instanceof Bar, true);
        out = merge([{}, { b: b0 }]);
        deepEqual(out, { b: b0 });
        equal(b0, out.b);
        equal(b0.x, 1);
        equal(b0 instanceof Bar, true);
    });
    // getpath tests
    // =============
    (0, node_test_1.test)('getpath-basic', async () => {
        await runset(spec.getpath.basic, (vin) => struct.getpath(vin.store, vin.path));
    });
    (0, node_test_1.test)('getpath-relative', async () => {
        await runset(spec.getpath.relative, (vin) => struct.getpath(vin.store, vin.path, { dparent: vin.dparent, dpath: vin.dpath?.split('.') }));
    });
    (0, node_test_1.test)('getpath-special', async () => {
        await runset(spec.getpath.special, (vin) => struct.getpath(vin.store, vin.path, vin.inj));
    });
    (0, node_test_1.test)('getpath-handler', async () => {
        await runset(spec.getpath.handler, (vin) => struct.getpath({
            $TOP: vin.store,
            $FOO: () => 'foo',
        }, vin.path, {
            handler: (_inj, val, _cur, _ref) => {
                return val();
            }
        }));
    });
    // inject tests
    // ============
    (0, node_test_1.test)('inject-basic', async () => {
        const { clone, inject } = struct;
        const test = clone(spec.inject.basic);
        deepEqual(inject(test.in.val, test.in.store), test.out);
    });
    (0, node_test_1.test)('inject-string', async () => {
        await runset(spec.inject.string, (vin) => struct.inject(vin.val, vin.store, { modify: runner_1.nullModifier }));
    });
    (0, node_test_1.test)('inject-deep', async () => {
        await runset(spec.inject.deep, (vin) => struct.inject(vin.val, vin.store));
    });
    // transform tests
    // ===============
    (0, node_test_1.test)('transform-basic', async () => {
        const { clone, transform } = struct;
        const test = clone(spec.transform.basic);
        deepEqual(transform(test.in.data, test.in.spec), test.out);
    });
    (0, node_test_1.test)('transform-paths', async () => {
        await runset(spec.transform.paths, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-cmds', async () => {
        await runset(spec.transform.cmds, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-each', async () => {
        await runset(spec.transform.each, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-pack', async () => {
        await runset(spec.transform.pack, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-ref', async () => {
        await runset(spec.transform.ref, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-format', async () => {
        await runsetflags(spec.transform.format, { null: false }, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-apply', async () => {
        await runset(spec.transform.apply, (vin) => struct.transform(vin.data, vin.spec));
    });
    (0, node_test_1.test)('transform-edge-apply', async () => {
        const { transform } = struct;
        equal(2, transform({}, ['`$APPLY`', (v) => 1 + v, 1]));
    });
    (0, node_test_1.test)('transform-modify', async () => {
        await runset(spec.transform.modify, (vin) => struct.transform(vin.data, vin.spec, {
            modify: (val, key, parent) => {
                if (null != key && null != parent && 'string' === typeof val) {
                    val = parent[key] = '@' + val;
                }
            }
        }));
    });
    (0, node_test_1.test)('transform-extra', async () => {
        deepEqual(struct.transform({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' }, {
            extra: {
                b: 2, $UPPER: (state) => {
                    const { path } = state;
                    return ('' + struct.getprop(path, path.length - 1)).toUpperCase();
                }
            }
        }), {
            x: 1,
            b: 2,
            c: 'C'
        });
    });
    (0, node_test_1.test)('transform-funcval', async () => {
        const { transform } = struct;
        // f0 should never be called (no $ prefix).
        const f0 = () => 99;
        deepEqual(transform({}, { x: 1 }), { x: 1 });
        deepEqual(transform({}, { x: f0 }), { x: f0 });
        deepEqual(transform({ a: 1 }, { x: '`a`' }), { x: 1 });
        deepEqual(transform({ f0 }, { x: '`f0`' }), { x: f0 });
    });
    // validate tests
    // ===============
    (0, node_test_1.test)('validate-basic', async () => {
        await runsetflags(spec.validate.basic, { null: false }, (vin) => struct.validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-child', async () => {
        await runset(spec.validate.child, (vin) => struct.validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-one', async () => {
        await runset(spec.validate.one, (vin) => struct.validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-exact', async () => {
        await runset(spec.validate.exact, (vin) => struct.validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-invalid', async () => {
        await runsetflags(spec.validate.invalid, { null: false }, (vin) => struct.validate(vin.data, vin.spec));
    });
    (0, node_test_1.test)('validate-special', async () => {
        await runset(spec.validate.special, (vin) => struct.validate(vin.data, vin.spec, vin.inj));
    });
    (0, node_test_1.test)('validate-edge', async () => {
        const { validate } = struct;
        let errs = [];
        validate({ x: 1 }, { x: '`$INSTANCE`' }, { errs });
        equal(errs[0], 'Expected field x to be instance, but found integer: 1.');
        errs = [];
        validate({ x: {} }, { x: '`$INSTANCE`' }, { errs });
        equal(errs[0], 'Expected field x to be instance, but found map: {}.');
        errs = [];
        validate({ x: [] }, { x: '`$INSTANCE`' }, { errs });
        equal(errs[0], 'Expected field x to be instance, but found list: [].');
        class C {
        }
        const c = new C();
        errs = [];
        validate({ x: c }, { x: '`$INSTANCE`' }, { errs });
        equal(errs.length, 0);
    });
    (0, node_test_1.test)('validate-custom', async () => {
        const errs = [];
        const extra = {
            $INTEGER: (inj) => {
                const { key } = inj;
                // let out = getprop(current, key)
                let out = struct.getprop(inj.dparent, key);
                let t = typeof out;
                if ('number' !== t && !Number.isInteger(out)) {
                    inj.errs.push('Not an integer at ' + inj.path.slice(1).join('.') + ': ' + out);
                    return;
                }
                return out;
            },
        };
        const shape = { a: '`$INTEGER`' };
        let out = struct.validate({ a: 1 }, shape, { extra, errs });
        deepEqual(out, { a: 1 });
        equal(errs.length, 0);
        out = struct.validate({ a: 'A' }, shape, { extra, errs });
        deepEqual(out, { a: 'A' });
        deepEqual(errs, ['Not an integer at a: A']);
    });
    // select tests
    // ============
    (0, node_test_1.test)('select-basic', async () => {
        await runset(spec.select.basic, (vin) => struct.select(vin.obj, vin.query));
    });
    (0, node_test_1.test)('select-operators', async () => {
        await runset(spec.select.operators, (vin) => struct.select(vin.obj, vin.query));
    });
    (0, node_test_1.test)('select-edge', async () => {
        await runset(spec.select.edge, (vin) => struct.select(vin.obj, vin.query));
    });
    (0, node_test_1.test)('select-alts', async () => {
        await runset(spec.select.alts, (vin) => struct.select(vin.obj, vin.query));
    });
    // JSON Builder
    // ============
    (0, node_test_1.test)('json-builder', async () => {
        const { jsonify, jm, jt } = struct;
        equal(jsonify(jm('a', 1)), `{
  "a": 1
}`);
        equal(jsonify(jt('b', 2)), `[
  "b",
  2
]`);
        equal(jsonify(jm('c', 'C', 'd', jm('x', true), 'e', jt(null, false))), `{
  "c": "C",
  "d": {
    "x": true
  },
  "e": [
    null,
    false
  ]
}`);
        equal(jsonify(jt(3.3, jm('f', true, 'g', false, 'h', null, 'i', jt('y', 0), 'j', jm('z', -1), 'k'))), `[
  3.3,
  {
    "f": true,
    "g": false,
    "h": null,
    "i": [
      "y",
      0
    ],
    "j": {
      "z": -1
    },
    "k": null
  }
]`);
        equal(jsonify(jm(true, 1, false, 2, null, 3, ['a'], 4, { 'b': 0 }, 5)), `{
  "true": 1,
  "false": 2,
  "null": 3,
  "[a]": 4,
  "{b:0}": 5
}`);
    });
});
//# sourceMappingURL=StructUtility.test.js.map