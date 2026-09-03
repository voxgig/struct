"use strict";
// VERSION: @voxgig/struct 0.3.3
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const node_assert_1 = __importDefault(require("node:assert"));
const omni_1 = require("../omni");
const index_1 = require("./index");
const { equal, deepEqual, throws } = node_assert_1.default;
// NOTE: tests are (mostly) in order of increasing dependence.
(0, node_test_1.describe)('StructUtility', async () => {
    let spec;
    let runset;
    let runsetflags;
    let client;
    let struct;
    (0, node_test_1.before)(async () => {
        const runner = await (0, omni_1.makeRunner)(index_1.TEST_JSON_FILE, await index_1.SDK.test());
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
    // ===========
    // CONDENSE
    // ===========
    (0, node_test_1.test)('condense-condense', async () => {
        await runsetflags(spec.condense.condense, { null: false }, struct.condense);
    });
    (0, node_test_1.test)('condense-expand', async () => {
        await runsetflags(spec.condense.expand, { null: false }, struct.expand);
    });
    (0, node_test_1.test)('condense-iscondensed', async () => {
        await runsetflags(spec.condense.iscondensed, { null: false }, struct.iscondensed);
    });
    // Properties the corpus shape cannot express: identity, sharing, laziness
    // and the immutability contract.
    (0, node_test_1.test)('condense-deterministic', () => {
        const s = struct;
        const src = { b: { m: 'GET' }, a: { m: 'GET' }, l: [1, 'x', true] };
        equal(JSON.stringify(s.condense(src)), JSON.stringify(s.condense(src)));
        // Insertion order must not change the bytes: keys are stored by symbol id.
        const reordered = { l: [1, 'x', true], a: { m: 'GET' }, b: { m: 'GET' } };
        equal(JSON.stringify(s.condense(src)), JSON.stringify(s.condense(reordered)));
    });
    (0, node_test_1.test)('condense-shares-identical-subtrees', () => {
        const s = struct;
        const one = s.condense({ x: { m: 'GET', p: '/1' } });
        const two = s.condense({ x: { m: 'GET', p: '/1' }, y: { m: 'GET', p: '/1' } });
        // Adding a SECOND reference to an identical subtree costs nothing: the
        // subtree interns to the same node and the root simply gains a ref, so
        // the node count is unchanged.
        equal(two.node.length, one.node.length);
        // Three distinct values would cost three nodes, so this is real sharing
        // rather than an artefact of the example being small.
        const three = s.condense({ x: { m: 'GET' }, y: { m: 'PUT' }, z: { m: 'POST' } });
        equal(true, three.node.length > two.node.length);
    });
    (0, node_test_1.test)('condense-round-trips-by-value', () => {
        const s = struct;
        const src = { a: { b: [1, 'x', true, null, {}] }, c: 'z' };
        deepEqual(s.expand(s.condense(src)), src);
    });
    (0, node_test_1.test)('condense-getpath-is-transparent', () => {
        const s = struct;
        const src = { entity: { p: { op: { list: { method: 'GET' } } } } };
        const c = s.condense(src);
        deepEqual(s.getpath(c, ['entity', 'p', 'op', 'list']), s.getpath(src, ['entity', 'p', 'op', 'list']));
        equal(s.getpath(c, ['entity', 'p', 'op', 'list', 'method']), 'GET');
        equal(undefined, s.getpath(c, ['entity', 'nope']));
    });
    (0, node_test_1.test)('condense-view-reads-without-materialising', () => {
        const s = struct;
        const c = s.condense({ entity: { a: { v: 1 }, b: { v: 2 } }, other: 9 });
        const v = s.condenseview(c);
        // keys() answers from the node and symbol tables alone.
        deepEqual(v.keys('entity'), ['a', 'b']);
        equal(v.at('entity').at('b').get('v'), 2);
        equal(v.has('entity.a'), true);
        equal(v.has('entity.zz'), false);
        equal(v.size(), 2);
    });
    (0, node_test_1.test)('condense-value-copies-and-ref-shares', () => {
        const s = struct;
        const c = s.condense({ a: { m: 'GET' }, b: { m: 'GET' } });
        const v = s.condenseview(c);
        // a and b share one node. value() must not let that be observable.
        const x = v.get('a');
        const y = v.get('b');
        deepEqual(x, y);
        equal(false, x === y);
        x.m = 'MUTATED';
        equal('GET', v.get('b').m);
        // ref() is the opt-in escape hatch and DOES share.
        equal(true, v.at('a').ref() === v.at('a').ref());
    });
    (0, node_test_1.test)('condense-preserves-proto-named-keys-and-values', () => {
        // Valid JSON, and plain assignment to `__proto__` hits the inherited
        // setter instead of creating an own property - so both the symbol table
        // and the materialised map need prototype-safe writes.
        const s = struct;
        const asValue = JSON.parse('{"x":"__proto__"}');
        deepEqual(s.expand(s.condense(asValue)), asValue);
        const asKey = JSON.parse('{"__proto__":1}');
        deepEqual(JSON.stringify(s.expand(s.condense(asKey))), '{"__proto__":1}');
    });
    (0, node_test_1.test)('condense-getpath-matches-plain-on-null-and-options', () => {
        const s = struct;
        // Group A null-as-absent: a stored null reads as absent either way.
        equal(s.getpath(s.condense({ a: null }), 'a'), s.getpath({ a: null }, 'a'));
        equal(undefined, s.getpath(s.condense({ a: null }), 'a'));
        // injdef.base must not be ignored by the condensed fast path.
        const store = { base: { x: 1 } };
        equal(s.getpath(s.condense(store), 'x', { base: 'base' }), s.getpath(store, 'x', { base: 'base' }));
    });
    (0, node_test_1.test)('condense-list-keys-are-canonical-integers', () => {
        const s = struct;
        const plain = { l: [10, 20] };
        const c = s.condense(plain);
        // Unary + would accept these; an ordinary list lookup does not, so
        // condensing must not change which value a path selects.
        for (const k of ['01', '1e0', ' 1', '+1', '1.0', '-0']) {
            equal(s.getpath(c, ['l', k]), s.getpath(plain, ['l', k]), `list key ${k}`);
        }
        equal(s.getpath(c, ['l', '1']), 20);
    });
    (0, node_test_1.test)('condense-symbols-sort-by-code-point', () => {
        // JavaScript's default sort compares UTF-16 code units and would put the
        // astral character FIRST; Python, Go and Rust compare by code point. The
        // format specifies code point order so every port emits the same bytes.
        const s = struct;
        const sym = s.condense({ a: '\u{10000}', b: '\uFFFF' }).sym;
        equal(true, sym.indexOf('\uFFFF') < sym.indexOf('\u{10000}'), 'symbol table is not in code-point order: ' + JSON.stringify(sym));
    });
    (0, node_test_1.test)('condense-invalid-key-mutations-stay-no-ops', () => {
        // Both helpers define an invalid key as ignored, so a call that cannot
        // write must not start throwing just because the store is condensed.
        const s = struct;
        const c = s.condense({ a: 1 });
        equal(c, s.delprop(c, undefined));
        equal(c, s.setprop(c, undefined, 1));
        // A call that COULD write still raises.
        throws(() => s.delprop(c, 'sym'), /immutable/);
    });
    (0, node_test_1.test)('condense-is-immutable', () => {
        const s = struct;
        const c = s.condense({ a: 1 });
        throws(() => s.setpath(c, 'a', 2), /immutable/);
        throws(() => s.setprop(c, 'a', 2), /immutable/);
        throws(() => s.delprop(c, 'sym'), /immutable/);
        // The expanded copy is ordinary and mutable.
        const e = s.expand(c);
        s.setpath(e, 'a', 2);
        equal(e.a, 2);
    });
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
        function f0() {
            return null;
        }
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
        const xc = clone(x);
        deepEqual(x, xc);
        (0, node_assert_1.default)(x !== xc);
        class A {
            constructor() {
                this.x = 1;
            }
        }
        const a = new A();
        const ac = clone(a);
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
        await runset(spec.minor.stringify, (vin) => struct.stringify(omni_1.NULLMARK === vin.val ? 'null' : vin.val, vin.max));
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
            const path = omni_1.NULLMARK == vin.path ? undefined : vin.path;
            let pathstr = struct.pathify(path, vin.from).replace('__NULL__.', '');
            pathstr = omni_1.NULLMARK === vin.path ? pathstr.replace(/>/g, ':null>') : pathstr;
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
        deepEqual(items(a0), [
            ['0', 11],
            ['1', 22],
            ['2', 33],
        ]);
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
        const strarr = ['a', 'b', 'c', 'd', 'e'];
        deepEqual(getprop(strarr, 2), 'c');
        deepEqual(getprop(strarr, '2'), 'c');
        const intarr = [2, 3, 5, 7, 11];
        deepEqual(getprop(intarr, 2), 5);
        deepEqual(getprop(intarr, '2'), 5);
    });
    (0, node_test_1.test)('minor-setprop', async () => {
        await runset(spec.minor.setprop, (vin) => struct.setprop(vin.parent, vin.key, vin.val));
    });
    (0, node_test_1.test)('minor-edge-setprop', async () => {
        const { setprop } = struct;
        const strarr0 = ['a', 'b', 'c', 'd', 'e'];
        const strarr1 = ['a', 'b', 'c', 'd', 'e'];
        deepEqual(setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e']);
        deepEqual(setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e']);
        const intarr0 = [2, 3, 5, 7, 11];
        const intarr1 = [2, 3, 5, 7, 11];
        deepEqual(setprop(intarr0, 2, 55), [2, 3, 55, 7, 11]);
        deepEqual(setprop(intarr1, '2', 555), [2, 3, 555, 7, 11]);
    });
    (0, node_test_1.test)('minor-delprop', async () => {
        await runset(spec.minor.delprop, (vin) => struct.delprop(vin.parent, vin.key));
    });
    (0, node_test_1.test)('minor-edge-delprop', async () => {
        const { delprop } = struct;
        const strarr0 = ['a', 'b', 'c', 'd', 'e'];
        const strarr1 = ['a', 'b', 'c', 'd', 'e'];
        deepEqual(delprop(strarr0, 2), ['a', 'b', 'd', 'e']);
        deepEqual(delprop(strarr1, '2'), ['a', 'b', 'd', 'e']);
        const intarr0 = [2, 3, 5, 7, 11];
        const intarr1 = [2, 3, 5, 7, 11];
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
            log.push('k=' +
                stringify(key) +
                ', v=' +
                stringify(val) +
                ', p=' +
                stringify(parent) +
                ', t=' +
                pathify(path));
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
                    const child = struct.islist(val) ? [] : {};
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
            const i = size(path);
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
            },
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
        await runset(spec.inject.string, (vin) => struct.inject(vin.val, vin.store, { modify: omni_1.nullModifier }));
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
            },
        }));
    });
    (0, node_test_1.test)('transform-extra', async () => {
        deepEqual(struct.transform({ a: 1 }, { x: '`a`', b: '`$COPY`', c: '`$UPPER`' }, {
            extra: {
                b: 2,
                $UPPER: (state) => {
                    const { path } = state;
                    return ('' + struct.getprop(path, path.length - 1)).toUpperCase();
                },
            },
        }), {
            x: 1,
            b: 2,
            c: 'C',
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
                const out = struct.getprop(inj.dparent, key);
                const t = typeof out;
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
    (0, node_test_1.test)('select-nullkey', async () => {
        // { null: false } keeps JSON null as an ACTUAL null (not the "__NULL__"
        // marker) so select sees a present-null field — the case that exercises the
        // Group-A/literal-presence unexpected-keys defect.
        await runsetflags(spec.select.nullkey, { null: false }, (vin) => struct.select(vin.obj, vin.query));
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
        equal(jsonify(jm(true, 1, false, 2, null, 3, ['a'], 4, { b: 0 }, 5)), `{
  "true": 1,
  "false": 2,
  "null": 3,
  "[a]": 4,
  "{b:0}": 5
}`);
    });
    // Group A conformance — null and absent unified on observation.
    // ============================================================
    // regex (parity floor: Go stdlib regexp — see design/REGEX_API.md)
    (0, node_test_1.test)('regex-test', async () => {
        const { re_test } = struct;
        await runset(spec.regex.test, (vin) => re_test(vin.pattern, vin.input));
    });
    (0, node_test_1.test)('regex-find', async () => {
        const { re_find } = struct;
        await runset(spec.regex.find, (vin) => {
            const m = re_find(vin.pattern, vin.input);
            return m ? Array.from(m) : null;
        });
    });
    (0, node_test_1.test)('regex-find_all', async () => {
        const { re_find_all } = struct;
        await runset(spec.regex.find_all, (vin) => re_find_all(vin.pattern, vin.input).map((m) => Array.from(m)));
    });
    (0, node_test_1.test)('regex-replace', async () => {
        const { re_replace } = struct;
        await runset(spec.regex.replace, (vin) => re_replace(vin.pattern, vin.input, vin.replacement));
    });
    (0, node_test_1.test)('regex-escape', async () => {
        const { re_escape } = struct;
        await runset(spec.regex.escape, (vin) => re_escape(vin.val));
    });
    (0, node_test_1.test)('sentinels-getprop_unify', async () => {
        const { getprop } = struct;
        await runsetflags(spec.sentinels.getprop_unify, { null: false }, (vin) => getprop(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('sentinels-getelem_absent', async () => {
        const { getelem } = struct;
        await runsetflags(spec.sentinels.getelem_absent, { null: false }, (vin) => getelem(vin.val, vin.key, vin.alt));
    });
    (0, node_test_1.test)('sentinels-haskey_unify', async () => {
        const { haskey } = struct;
        await runsetflags(spec.sentinels.haskey_unify, { null: false }, (vin) => haskey(vin.val, vin.key));
    });
    (0, node_test_1.test)('sentinels-isempty_unify', async () => {
        await runsetflags(spec.sentinels.isempty_unify, { null: false }, struct.isempty);
    });
    (0, node_test_1.test)('sentinels-isnode_unify', async () => {
        await runsetflags(spec.sentinels.isnode_unify, { null: false }, struct.isnode);
    });
    (0, node_test_1.test)('sentinels-stringify_null', async () => {
        await runsetflags(spec.sentinels.stringify_null, { null: false }, struct.stringify);
    });
});
//# sourceMappingURL=StructUtility.test.js.map