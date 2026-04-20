// VERSION: @voxgig/struct 0.1.0
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath

import { test, describe, before } from 'node:test'
import assert from 'node:assert'

import {
  makeRunner,
  nullModifier,
  NULLMARK,
} from '../runner'


import {
  SDK,
  TEST_JSON_FILE
} from './index'


const { equal, deepEqual } = assert


// NOTE: tests are (mostly) in order of increasing dependence.
describe('StructUtility', async () => {

  let spec: any
  let runset: any
  let runsetflags: any
  let client: any
  let struct: any

  before(async () => {
    const runner = await makeRunner(TEST_JSON_FILE, await SDK.test())
    const runner_struct = await runner('struct')

    spec = runner_struct.spec

    runset = runner_struct.runset
    runsetflags = runner_struct.runsetflags
    client = runner_struct.client

    struct = client.utility().struct
  })



  test('exists', () => {
    const s = struct

    equal('function', typeof s.clone)
    equal('function', typeof s.delprop)
    equal('function', typeof s.escre)
    equal('function', typeof s.escurl)
    equal('function', typeof s.filter)

    equal('function', typeof s.flatten)
    equal('function', typeof s.getelem)
    equal('function', typeof s.getprop)

    equal('function', typeof s.getpath)
    equal('function', typeof s.haskey)
    equal('function', typeof s.inject)
    equal('function', typeof s.isempty)
    equal('function', typeof s.isfunc)

    equal('function', typeof s.iskey)
    equal('function', typeof s.islist)
    equal('function', typeof s.ismap)
    equal('function', typeof s.isnode)
    equal('function', typeof s.items)

    equal('function', typeof s.join)
    equal('function', typeof s.jsonify)
    equal('function', typeof s.keysof)
    equal('function', typeof s.merge)
    equal('function', typeof s.pad)
    equal('function', typeof s.pathify)

    equal('function', typeof s.select)
    equal('function', typeof s.setpath)
    equal('function', typeof s.size)
    equal('function', typeof s.slice)
    equal('function', typeof s.setprop)

    equal('function', typeof s.strkey)
    equal('function', typeof s.stringify)
    equal('function', typeof s.transform)
    equal('function', typeof s.typify)
    equal('function', typeof s.typename)

    equal('function', typeof s.validate)
    equal('function', typeof s.walk)
  })


  // minor tests
  // ===========

  test('minor-isnode', async () => {
    await runset(spec.minor.isnode, struct.isnode)
  })


  test('minor-ismap', async () => {
    await runset(spec.minor.ismap, struct.ismap)
  })


  test('minor-islist', async () => {
    await runset(spec.minor.islist, struct.islist)
  })


  test('minor-iskey', async () => {
    await runsetflags(spec.minor.iskey, { null: false }, struct.iskey)
  })


  test('minor-strkey', async () => {
    await runsetflags(spec.minor.strkey, { null: false }, struct.strkey)
  })


  test('minor-isempty', async () => {
    await runsetflags(spec.minor.isempty, { null: false }, struct.isempty)
  })


  test('minor-isfunc', async () => {
    const { isfunc } = struct
    await runset(spec.minor.isfunc, isfunc)
    function f0() { return null }
    equal(isfunc(f0), true)
    equal(isfunc(() => null), true)
  })


  test('minor-clone', async () => {
    await runsetflags(spec.minor.clone, { null: false }, struct.clone)
  })


  test('minor-edge-clone', async () => {
    const { clone } = struct

    const f0 = () => null
    deepEqual({ a: f0 }, clone({ a: f0 }))

    const x = { y: 1 }
    let xc = clone(x)
    deepEqual(x, xc)
    assert(x !== xc)

    class A { x = 1 }
    const a = new A()
    let ac = clone(a)
    deepEqual(a, ac)
    assert(a === ac)
    equal(a.constructor.name, ac.constructor.name)
  })


  test('minor-filter', async () => {
    const checkmap: any = {
      gt3: (n: any) => n[1] > 3,
      lt3: (n: any) => n[1] < 3,
    }
    await runset(spec.minor.filter, (vin: any) => struct.filter(vin.val, checkmap[vin.check]))
  })


  test('minor-flatten', async () => {
    await runset(spec.minor.flatten, (vin: any) => struct.flatten(vin.val, vin.depth))
  })


  test('minor-escre', async () => {
    await runset(spec.minor.escre, struct.escre)
  })


  test('minor-escurl', async () => {
    await runset(spec.minor.escurl, struct.escurl)
  })


  test('minor-stringify', async () => {
    await runset(spec.minor.stringify, (vin: any) =>
      struct.stringify((NULLMARK === vin.val ? "null" : vin.val), vin.max))
  })


  test('minor-edge-stringify', async () => {
    const { stringify } = struct
    const a: any = {}
    a.a = a
    equal(stringify(a), '__STRINGIFY_FAILED__')

    equal(stringify({ a: [9] }, -1, true),
      '\x1B[38;5;81m\x1B[38;5;118m{\x1B[38;5;118ma\x1B[38;5;118m:' +
      '\x1B[38;5;213m[\x1B[38;5;213m9\x1B[38;5;213m]\x1B[38;5;118m}\x1B[0m')
  })


  test('minor-jsonify', async () => {
    await runsetflags(spec.minor.jsonify, { null: false },
      (vin: any) => struct.jsonify(vin.val, vin.flags))
  })


  test('minor-edge-jsonify', async () => {
    const { jsonify } = struct
    equal(jsonify(() => 1), 'null')
  })


  test('minor-pathify', async () => {
    await runsetflags(
      spec.minor.pathify, { null: true },
      (vin: any) => {
        let path = NULLMARK == vin.path ? undefined : vin.path
        let pathstr = struct.pathify(path, vin.from).replace('__NULL__.', '')
        pathstr = NULLMARK === vin.path ? pathstr.replace('>', ':null>') : pathstr
        return pathstr
      })
  })


  test('minor-items', async () => {
    await runset(spec.minor.items, struct.items)
  })


  test('minor-edge-items', async () => {
    const { items } = struct
    const a0: any = [11, 22, 33]
    a0.x = 1
    deepEqual(items(a0), [['0', 11], ['1', 22], ['2', 33]])
  })


  test('minor-getelem', async () => {
    const { getelem } = struct
    await runsetflags(spec.minor.getelem, { null: false }, (vin: any) =>
      null == vin.alt ? getelem(vin.val, vin.key) : getelem(vin.val, vin.key, vin.alt))
  })


  test('minor-edge-getelem', async () => {
    const { getelem } = struct
    equal(getelem([], 1, () => 2), 2)
  })


  test('minor-getprop', async () => {
    const { getprop } = struct
    await runsetflags(spec.minor.getprop, { null: false }, (vin: any) =>
      undefined === vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt))
  })


  test('minor-edge-getprop', async () => {
    const { getprop } = struct

    let strarr = ['a', 'b', 'c', 'd', 'e']
    deepEqual(getprop(strarr, 2), 'c')
    deepEqual(getprop(strarr, '2'), 'c')

    let intarr = [2, 3, 5, 7, 11]
    deepEqual(getprop(intarr, 2), 5)
    deepEqual(getprop(intarr, '2'), 5)
  })


  test('minor-setprop', async () => {
    await runset(spec.minor.setprop, (vin: any) =>
      struct.setprop(vin.parent, vin.key, vin.val))
  })


  test('minor-edge-setprop', async () => {
    const { setprop } = struct

    let strarr0 = ['a', 'b', 'c', 'd', 'e']
    let strarr1 = ['a', 'b', 'c', 'd', 'e']
    deepEqual(setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e'])
    deepEqual(setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e'])

    let intarr0 = [2, 3, 5, 7, 11]
    let intarr1 = [2, 3, 5, 7, 11]
    deepEqual(setprop(intarr0, 2, 55), [2, 3, 55, 7, 11])
    deepEqual(setprop(intarr1, '2', 555), [2, 3, 555, 7, 11])
  })


  test('minor-delprop', async () => {
    await runset(spec.minor.delprop, (vin: any) =>
      struct.delprop(vin.parent, vin.key))
  })


  test('minor-edge-delprop', async () => {
    const { delprop } = struct

    let strarr0 = ['a', 'b', 'c', 'd', 'e']
    let strarr1 = ['a', 'b', 'c', 'd', 'e']
    deepEqual(delprop(strarr0, 2), ['a', 'b', 'd', 'e'])
    deepEqual(delprop(strarr1, '2'), ['a', 'b', 'd', 'e'])

    let intarr0 = [2, 3, 5, 7, 11]
    let intarr1 = [2, 3, 5, 7, 11]
    deepEqual(delprop(intarr0, 2), [2, 3, 7, 11])
    deepEqual(delprop(intarr1, '2'), [2, 3, 7, 11])
  })


  test('minor-haskey', async () => {
    await runsetflags(spec.minor.haskey, { null: false }, (vin: any) =>
      struct.haskey(vin.src, vin.key))
  })


  test('minor-keysof', async () => {
    await runset(spec.minor.keysof, struct.keysof)
  })

  test('minor-edge-keysof', async () => {
    const { keysof } = struct
    const a0: any = [11, 22, 33]
    a0.x = 1
    deepEqual(keysof(a0), [0, 1, 2])
  })



  test('minor-join', async () => {
    await runsetflags(spec.minor.join, { null: false },
      (vin: any) => struct.join(vin.val, vin.sep, vin.url))
  })


  test('minor-typename', async () => {
    await runset(spec.minor.typename, struct.typename)
  })


  test('minor-typify', async () => {
    await runsetflags(spec.minor.typify, { null: false }, struct.typify)
  })


  test('minor-edge-typify', async () => {
    const {
      typify, T_noval, T_scalar, T_function, T_symbol, T_any, T_node, T_instance, T_null
    } = struct
    class X { }
    const x = new X()
    equal(typify(), T_noval)
    equal(typify(undefined), T_noval)
    equal(typify(NaN), T_noval)
    equal(typify(null), T_scalar | T_null)
    equal(typify(() => null), T_scalar | T_function)
    equal(typify(Symbol('S')), T_scalar | T_symbol)
    equal(typify(BigInt(1)), T_any)
    equal(typify(x), T_node | T_instance)
  })


  test('minor-size', async () => {
    await runsetflags(spec.minor.size, { null: false }, struct.size)
  })


  test('minor-slice', async () => {
    await runsetflags(spec.minor.slice, { null: false },
      (vin: any) => struct.slice(vin.val, vin.start, vin.end))
  })


  test('minor-pad', async () => {
    await runsetflags(spec.minor.pad, { null: false },
      (vin: any) => struct.pad(vin.val, vin.pad, vin.char))
  })


  test('minor-setpath', async () => {
    await runsetflags(spec.minor.setpath, { null: false },
      (vin: any) => struct.setpath(vin.store, vin.path, vin.val))
  })


  test('minor-edge-setpath', async () => {
    const { setpath, DELETE } = struct
    const x = { y: { z: 1, q: 2 } }
    deepEqual(setpath(x, 'y.q', DELETE), { z: 1 })
    deepEqual(x, { y: { z: 1 } })
  })



  // walk tests
  // ==========

  test('walk-log', async () => {
    const { clone, stringify, pathify, walk } = struct

    const test = clone(spec.walk.log)

    let log: string[] = []

    function walklog(key: any, val: any, parent: any, path: any) {
      log.push('k=' + stringify(key) +
        ', v=' + stringify(val) +
        ', p=' + stringify(parent) +
        ', t=' + pathify(path))
      return val
    }

    walk(test.in, undefined, walklog)
    deepEqual(log, test.out.after)

    log = []
    walk(test.in, walklog)
    deepEqual(log, test.out.before)

    log = []
    walk(test.in, walklog, walklog)
    deepEqual(log, test.out.both)
  })


  test('walk-basic', async () => {
    function walkpath(_key: any, val: any, _parent: any, path: any) {
      return 'string' === typeof val ? val + '~' + path.join('.') : val
    }

    await runset(spec.walk.basic, (vin: any) => struct.walk(vin, walkpath))
  })


  test('walk-depth', async () => {

    await runsetflags(spec.walk.depth, { null: false },
      (vin: any) => {
        let top: any = undefined
        let cur: any = undefined
        function copy(key: any, val: any, _parent: any, _path: any) {
          if (undefined === key || struct.isnode(val)) {
            let child = struct.islist(val) ? [] : {}
            if (undefined === key) {
              top = cur = child
            }
            else {
              cur = cur[key] = child
            }
          }
          else {
            cur[key] = val
          }
          return val
        }
        struct.walk(vin.src, copy, undefined, vin.maxdepth)
        return top
      })
  })


  test('walk-copy', async () => {
    const { walk, isnode, ismap, islist, size, setprop } = struct

    let cur: any[]
    function walkcopy(key: any, val: any, _parent: any, path: any) {
      if (undefined === key) {
        cur = []
        cur[0] = ismap(val) ? {} : islist(val) ? [] : val
        return val
      }

      let v = val
      let i = size(path)

      if (isnode(v)) {
        v = cur[i] = ismap(v) ? {} : []
      }

      setprop(cur[i - 1], key, v)

      return val
    }

    await runset(spec.walk.copy, (vin: any) => (walk(vin, walkcopy), cur[0]))
  })



  // merge tests
  // ===========

  test('merge-basic', async () => {
    const { clone, merge } = struct
    const test = clone(spec.merge.basic)
    deepEqual(merge(test.in), test.out)
  })


  test('merge-cases', async () => {
    await runset(spec.merge.cases, struct.merge)
  })


  test('merge-array', async () => {
    await runset(spec.merge.array, struct.merge)
  })


  test('merge-integrity', async () => {
    await runset(spec.merge.integrity, struct.merge)
  })


  test('merge-depth', async () => {
    await runset(spec.merge.depth, (vin: any) => struct.merge(vin.val, vin.depth))
  })


  test('merge-special', async () => {
    const { merge } = struct
    const f0 = () => null
    deepEqual(merge([f0]), f0)
    deepEqual(merge([null, f0]), f0)
    deepEqual(merge([{ a: f0 }]), { a: f0 })
    deepEqual(merge([[f0]]), [f0])
    deepEqual(merge([{ a: { b: f0 } }]), { a: { b: f0 } })

    // JavaScript only
    deepEqual(merge([{ a: global.fetch }]), { a: global.fetch })
    deepEqual(merge([[global.fetch]]), [global.fetch])
    deepEqual(merge([{ a: { b: global.fetch } }]), { a: { b: global.fetch } })

    class Bar { x = 1 }
    const b0 = new Bar()
    let out

    equal(merge([{ x: 10 }, b0]), b0)
    equal(b0.x, 1)
    equal(b0 instanceof Bar, true)

    deepEqual(merge([{ a: b0 }, { a: { x: 11 } }]), { a: { x: 11 } })
    equal(b0.x, 1)
    equal(b0 instanceof Bar, true)

    deepEqual(merge([b0, { x: 20 }]), { x: 20 })
    equal(b0.x, 1)
    equal(b0 instanceof Bar, true)

    out = merge([{ a: { x: 21 } }, { a: b0 }])
    deepEqual(out, { a: b0 })
    equal(b0, out.a)
    equal(b0.x, 1)
    equal(b0 instanceof Bar, true)

    out = merge([{}, { b: b0 }])
    deepEqual(out, { b: b0 })
    equal(b0, out.b)
    equal(b0.x, 1)
    equal(b0 instanceof Bar, true)
  })


  // getpath tests
  // =============

  test('getpath-basic', async () => {
    await runset(spec.getpath.basic, (vin: any) => struct.getpath(vin.store, vin.path))
  })


  test('getpath-relative', async () => {
    await runset(spec.getpath.relative, (vin: any) =>
      struct.getpath(vin.store, vin.path,
        { dparent: vin.dparent, dpath: vin.dpath?.split('.') }))
  })


  test('getpath-special', async () => {
    await runset(spec.getpath.special, (vin: any) =>
      struct.getpath(vin.store, vin.path, vin.inj))
  })


  test('getpath-handler', async () => {
    await runset(spec.getpath.handler, (vin: any) =>
      struct.getpath(
        {
          $TOP: vin.store,
          $FOO: () => 'foo',
        },
        vin.path,
        {
          handler: (_inj: any, val: any, _cur: any, _ref: any) => {
            return val()
          }
        }
      ))
  })


  // inject tests
  // ============

  test('inject-basic', async () => {
    const { clone, inject } = struct
    const test = clone(spec.inject.basic)
    deepEqual(inject(test.in.val, test.in.store), test.out)
  })


  test('inject-string', async () => {
    await runset(spec.inject.string, (vin: any) =>
      struct.inject(vin.val, vin.store, { modify: nullModifier }))
  })


  test('inject-deep', async () => {
    await runset(spec.inject.deep, (vin: any) => struct.inject(vin.val, vin.store))
  })


  // transform tests
  // ===============

  test('transform-basic', async () => {
    const { clone, transform } = struct
    const test = clone(spec.transform.basic)
    deepEqual(transform(test.in.data, test.in.spec), test.out)
  })


  test('transform-paths', async () => {
    await runset(spec.transform.paths, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })


  test('transform-cmds', async () => {
    await runset(spec.transform.cmds, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })


  test('transform-each', async () => {
    await runset(spec.transform.each, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })


  test('transform-pack', async () => {
    await runset(spec.transform.pack, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })


  test('transform-ref', async () => {
    await runset(spec.transform.ref, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })


  test('transform-format', async () => {
    await runsetflags(spec.transform.format, { null: false }, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })


  test('transform-apply', async () => {
    await runset(spec.transform.apply, (vin: any) =>
      struct.transform(vin.data, vin.spec))
  })

  test('transform-edge-apply', async () => {
    const { transform } = struct
    equal(2, transform({}, ['`$APPLY`', (v: any) => 1 + v, 1]))
  })



  test('transform-modify', async () => {
    await runset(spec.transform.modify, (vin: any) =>
      struct.transform(
        vin.data,
        vin.spec,
        {
          modify: (val: any, key: any, parent: any) => {
            if (null != key && null != parent && 'string' === typeof val) {
              val = parent[key] = '@' + val
            }
          }
        }
      ))
  })


  test('transform-extra', async () => {
    deepEqual(struct.transform(
      { a: 1 },
      { x: '`a`', b: '`$COPY`', c: '`$UPPER`' },
      {
        extra: {
          b: 2, $UPPER: (state: any) => {
            const { path } = state
            return ('' + struct.getprop(path, path.length - 1)).toUpperCase()
          }
        }
      }
    ), {
      x: 1,
      b: 2,
      c: 'C'
    })
  })


  test('transform-funcval', async () => {
    const { transform } = struct
    // f0 should never be called (no $ prefix).
    const f0 = () => 99
    deepEqual(transform({}, { x: 1 }), { x: 1 })
    deepEqual(transform({}, { x: f0 }), { x: f0 })
    deepEqual(transform({ a: 1 }, { x: '`a`' }), { x: 1 })
    deepEqual(transform({ f0 }, { x: '`f0`' }), { x: f0 })
  })


  // validate tests
  // ===============

  test('validate-basic', async () => {
    await runsetflags(spec.validate.basic, { null: false },
      (vin: any) => struct.validate(vin.data, vin.spec))
  })


  test('validate-child', async () => {
    await runset(spec.validate.child, (vin: any) => struct.validate(vin.data, vin.spec))
  })


  test('validate-one', async () => {
    await runset(spec.validate.one, (vin: any) => struct.validate(vin.data, vin.spec))
  })


  test('validate-exact', async () => {
    await runset(spec.validate.exact, (vin: any) => struct.validate(vin.data, vin.spec))
  })


  test('validate-invalid', async () => {
    await runsetflags(spec.validate.invalid, { null: false },
      (vin: any) => struct.validate(vin.data, vin.spec))
  })


  test('validate-special', async () => {
    await runset(spec.validate.special, (vin: any) =>
      struct.validate(vin.data, vin.spec, vin.inj))
  })


  test('validate-edge', async () => {
    const { validate } = struct
    let errs: any[] = []
    validate({ x: 1 }, { x: '`$INSTANCE`' }, { errs })
    equal(errs[0], 'Expected field x to be instance, but found integer: 1.')

    errs = []
    validate({ x: {} }, { x: '`$INSTANCE`' }, { errs })
    equal(errs[0], 'Expected field x to be instance, but found map: {}.')

    errs = []
    validate({ x: [] }, { x: '`$INSTANCE`' }, { errs })
    equal(errs[0], 'Expected field x to be instance, but found list: [].')

    class C { }
    const c = new C()
    errs = []
    validate({ x: c }, { x: '`$INSTANCE`' }, { errs })
    equal(errs.length, 0)
  })


  test('validate-custom', async () => {
    const errs: any[] = []
    const extra = {
      $INTEGER: (inj: any) => {
        const { key } = inj
        // let out = getprop(current, key)
        let out = struct.getprop(inj.dparent, key)

        let t = typeof out
        if ('number' !== t && !Number.isInteger(out)) {
          inj.errs.push('Not an integer at ' + inj.path.slice(1).join('.') + ': ' + out)
          return
        }

        return out
      },
    }

    const shape = { a: '`$INTEGER`' }

    let out = struct.validate({ a: 1 }, shape, { extra, errs })
    deepEqual(out, { a: 1 })
    equal(errs.length, 0)

    out = struct.validate({ a: 'A' }, shape, { extra, errs })
    deepEqual(out, { a: 'A' })
    deepEqual(errs, ['Not an integer at a: A'])
  })


  // select tests
  // ============

  test('select-basic', async () => {
    await runset(spec.select.basic, (vin: any) => struct.select(vin.obj, vin.query))
  })


  test('select-operators', async () => {
    await runset(spec.select.operators, (vin: any) => struct.select(vin.obj, vin.query))
  })


  test('select-edge', async () => {
    await runset(spec.select.edge, (vin: any) => struct.select(vin.obj, vin.query))
  })


  test('select-alts', async () => {
    await runset(spec.select.alts, (vin: any) => struct.select(vin.obj, vin.query))
  })


  // JSON Builder
  // ============

  test('json-builder', async () => {
    const { jsonify, jm, jt } = struct
    equal(jsonify(jm(
      'a', 1
    )), `{
  "a": 1
}`)

    equal(jsonify(jt(
      'b', 2
    )), `[
  "b",
  2
]`)

    equal(jsonify(jm(
      'c', 'C',
      'd', jm('x', true),
      'e', jt(null, false)
    )), `{
  "c": "C",
  "d": {
    "x": true
  },
  "e": [
    null,
    false
  ]
}`)

    equal(jsonify(jt(
      3.3, jm(
        'f', true,
        'g', false,
        'h', null,
        'i', jt('y', 0),
        'j', jm('z', -1),
        'k')
    )), `[
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
]`)

    equal(jsonify(jm(
      true, 1,
      false, 2,
      null, 3,
      ['a'], 4,
      { 'b': 0 }, 5
    )), `{
  "true": 1,
  "false": 2,
  "null": 3,
  "[a]": 4,
  "{b:0}": 5
}`)

  })


})

