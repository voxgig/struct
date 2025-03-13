
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath


import { test, describe } from 'node:test'
import { equal, deepEqual } from 'node:assert'

import {
  clone,
  escre,
  escurl,
  getpath,
  getprop,
  haskey,
  inject,
  isempty,
  isfunc,
  iskey,
  islist,
  ismap,
  isnode,
  items,
  joinurl,
  keysof,
  merge,
  pathify,
  setprop,
  stringify,
  transform,
  typify,
  validate,
  walk,
} from '../dist/struct'

import type {
  Injection
} from '../dist/struct'

import {
  runner,
  nullModifier,
  NULLMARK,
} from './runner'


// NOTE: tests are in order of increasing dependence.
describe('struct', async () => {

  const { spec, runset, runsetflags } =
    await runner('struct', {}, '../../build/test/test.json', {
      test: async () => ({
        utility: () => ({
          struct: {
            clone,
            escre,
            escurl,
            getpath,
            getprop,
            inject,
            isempty,
            iskey,
            islist,
            ismap,
            isnode,
            items,
            haskey,
            keysof,
            merge,
            setprop,
            stringify,
            transform,
            typify,
            walk,
            validate,
            joinurl,
          }
        })
      })
    })

  const minorSpec = spec.minor
  const walkSpec = spec.walk
  const mergeSpec = spec.merge
  const getpathSpec = spec.getpath
  const injectSpec = spec.inject
  const transformSpec = spec.transform
  const validateSpec = spec.validate



  // minor tests
  // ===========

  test('minor-exists', () => {
    equal('function', typeof clone)
    equal('function', typeof escre)
    equal('function', typeof escurl)
    equal('function', typeof getprop)
    equal('function', typeof haskey)

    equal('function', typeof isempty)
    equal('function', typeof isfunc)
    equal('function', typeof iskey)
    equal('function', typeof islist)
    equal('function', typeof ismap)

    equal('function', typeof isnode)
    equal('function', typeof items)
    equal('function', typeof joinurl)
    equal('function', typeof keysof)
    equal('function', typeof pathify)

    equal('function', typeof setprop)
    equal('function', typeof stringify)
    equal('function', typeof typify)
  })


  test('minor-isnode', async () => {
    await runset(minorSpec.isnode, isnode)
  })


  test('minor-ismap', async () => {
    await runset(minorSpec.ismap, ismap)
  })


  test('minor-islist', async () => {
    await runset(minorSpec.islist, islist)
  })


  test('minor-iskey', async () => {
    await runsetflags(minorSpec.iskey, { null: false }, iskey)
  })


  test('minor-isempty', async () => {
    await runsetflags(minorSpec.isempty, { null: false }, isempty)
  })


  test('minor-isfunc', async () => {
    await runset(minorSpec.isfunc, isfunc)
    function f0() { return null }
    equal(isfunc(f0), true)
    equal(isfunc(() => null), true)
  })


  test('minor-clone', async () => {
    await runsetflags(minorSpec.clone, { null: false }, clone)
    const f0 = () => null
    deepEqual({ a: f0 }, clone({ a: f0 }))
  })


  test('minor-escre', async () => {
    await runset(minorSpec.escre, escre)
  })


  test('minor-escurl', async () => {
    await runset(minorSpec.escurl, escurl)
  })


  test('minor-stringify', async () => {
    await runset(minorSpec.stringify, (vin: any) =>
      stringify((NULLMARK === vin.val ? "null" : vin.val), vin.max))
  })


  test('minor-pathify', async () => {
    await runsetflags(
      minorSpec.pathify, { null: true },
      (vin: any) => {
        let path = NULLMARK == vin.path ? undefined : vin.path
        let pathstr = pathify(path, vin.from).replace('__NULL__.', '')
        pathstr = NULLMARK === vin.path ? pathstr.replace('>', ':null>') : pathstr
        return pathstr
      })
  })


  test('minor-items', async () => {
    await runset(minorSpec.items, items)
  })


  test('minor-getprop', async () => {
    await runsetflags(minorSpec.getprop, { null: false }, (vin: any) =>
      null == vin.alt ? getprop(vin.val, vin.key) : getprop(vin.val, vin.key, vin.alt))
  })


  test('minor-edge-getprop', async () => {
    let strarr = ['a', 'b', 'c', 'd', 'e']
    deepEqual(getprop(strarr, 2), 'c')
    deepEqual(getprop(strarr, '2'), 'c')

    let intarr = [2, 3, 5, 7, 11]
    deepEqual(getprop(intarr, 2), 5)
    deepEqual(getprop(intarr, '2'), 5)
  })


  test('minor-setprop', async () => {
    await runsetflags(minorSpec.setprop, { null: false }, (vin: any) =>
      setprop(vin.parent, vin.key, vin.val))
  })


  test('minor-edge-setprop', async () => {
    let strarr0 = ['a', 'b', 'c', 'd', 'e']
    let strarr1 = ['a', 'b', 'c', 'd', 'e']
    deepEqual(setprop(strarr0, 2, 'C'), ['a', 'b', 'C', 'd', 'e'])
    deepEqual(setprop(strarr1, '2', 'CC'), ['a', 'b', 'CC', 'd', 'e'])

    let intarr0 = [2, 3, 5, 7, 11]
    let intarr1 = [2, 3, 5, 7, 11]
    deepEqual(setprop(intarr0, 2, 55), [2, 3, 55, 7, 11])
    deepEqual(setprop(intarr1, '2', 555), [2, 3, 555, 7, 11])
  })


  test('minor-haskey', async () => {
    await runset(minorSpec.haskey, haskey)
  })


  test('minor-keysof', async () => {
    await runset(minorSpec.keysof, keysof)
  })


  test('minor-joinurl', async () => {
    await runsetflags(minorSpec.joinurl, { null: false }, joinurl)
  })


  test('minor-typify', async () => {
    await runsetflags(minorSpec.typify, { null: false }, typify)
  })


  // walk tests
  // ==========

  test('walk-exists', async () => {
    equal('function', typeof walk)
  })


  test('walk-log', async () => {
    const test = clone(walkSpec.log)

    const log: string[] = []

    function walklog(key: any, val: any, parent: any, path: any) {
      log.push('k=' + stringify(key) +
        ', v=' + stringify(val) +
        ', p=' + stringify(parent) +
        ', t=' + pathify(path))
      return val
    }

    walk(test.in, walklog)
    deepEqual(log, test.out)
  })


  test('walk-basic', async () => {
    function walkpath(_key: any, val: any, _parent: any, path: any) {
      return 'string' === typeof val ? val + '~' + path.join('.') : val
    }

    await runset(walkSpec.basic, (vin: any) => walk(vin, walkpath))
  })


  // merge tests
  // ===========

  test('merge-exists', async () => {
    equal('function', typeof merge)
  })


  test('merge-basic', async () => {
    const test = clone(mergeSpec.basic)
    deepEqual(merge(test.in), test.out)
  })


  test('merge-cases', async () => {
    await runset(mergeSpec.cases, merge)
  })


  test('merge-array', async () => {
    await runset(mergeSpec.array, merge)
  })


  test('merge-special', async () => {
    const f0 = () => null
    deepEqual(merge([f0]), f0)
    deepEqual(merge([null, f0]), f0)
    deepEqual(merge([{ a: f0 }]), { a: f0 })
    deepEqual(merge([{ a: { b: f0 } }]), { a: { b: f0 } })

    // JavaScript only
    deepEqual(merge([{ a: global.fetch }]), { a: global.fetch })
    deepEqual(merge([{ a: { b: global.fetch } }]), { a: { b: global.fetch } })
  })


  // getpath tests
  // =============

  test('getpath-exists', async () => {
    equal('function', typeof getpath)
  })


  test('getpath-basic', async () => {
    await runset(getpathSpec.basic, (vin: any) => getpath(vin.path, vin.store))
  })


  test('getpath-current', async () => {
    await runset(getpathSpec.current, (vin: any) =>
      getpath(vin.path, vin.store, vin.current))
  })


  test('getpath-state', async () => {
    const state: Injection = {
      handler: (state: any, val: any, _current: any, _ref: any, _store: any) => {
        let out = state.meta.step + ':' + val
        state.meta.step++
        return out
      },
      meta: { step: 0 },
      mode: ('val' as any),
      full: false,
      keyI: 0,
      keys: ['$TOP'],
      key: '$TOP',
      val: '',
      parent: {},
      path: ['$TOP'],
      nodes: [{}],
      base: '$TOP',
      errs: [],
    }
    await runset(getpathSpec.state, (vin: any) =>
      getpath(vin.path, vin.store, vin.current, state))
  })


  // inject tests
  // ============

  test('inject-exists', async () => {
    equal('function', typeof inject)
  })


  test('inject-basic', async () => {
    const test = clone(injectSpec.basic)
    deepEqual(inject(test.in.val, test.in.store), test.out)
  })


  test('inject-string', async () => {
    await runset(injectSpec.string, (vin: any) =>
      inject(vin.val, vin.store, nullModifier, vin.current))
  })


  test('inject-deep', async () => {
    await runset(injectSpec.deep, (vin: any) => inject(vin.val, vin.store))
  })


  // transform tests
  // ===============

  test('transform-exists', async () => {
    equal('function', typeof transform)
  })


  test('transform-basic', async () => {
    const test = clone(transformSpec.basic)
    deepEqual(transform(test.in.data, test.in.spec, test.in.store), test.out)
  })


  test('transform-paths', async () => {
    await runset(transformSpec.paths, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })


  test('transform-cmds', async () => {
    await runset(transformSpec.cmds, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })


  test('transform-each', async () => {
    await runset(transformSpec.each, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })


  test('transform-pack', async () => {
    await runset(transformSpec.pack, (vin: any) =>
      transform(vin.data, vin.spec, vin.store))
  })


  test('transform-modify', async () => {
    await runset(transformSpec.modify, (vin: any) =>
      transform(vin.data, vin.spec, vin.store,
        (val, key, parent) => {
          if (null != key && null != parent && 'string' === typeof val) {
            val = parent[key] = '@' + val
          }
        }
      ))
  })


  test('transform-extra', async () => {
    deepEqual(transform(
      { a: 1 },
      { x: '`a`', b: '`$COPY`', c: '`$UPPER`' },
      {
        b: 2, $UPPER: (state: any) => {
          const { path } = state
          return ('' + getprop(path, path.length - 1)).toUpperCase()
        }
      }
    ), {
      x: 1,
      b: 2,
      c: 'C'
    })
  })


  test('transform-funcval', async () => {
    const f0 = () => 99
    deepEqual(transform({}, { x: 1 }), { x: 1 })
    deepEqual(transform({}, { x: f0 }), { x: f0 })
    deepEqual(transform({ a: 1 }, { x: '`a`' }), { x: 1 })
    deepEqual(transform({ f0 }, { x: '`f0`' }), { x: f0 })
  })


  // validate tests
  // ===============

  test('validate-exists', async () => {
    equal('function', typeof validate)
  })


  test('validate-basic', async () => {
    await runset(validateSpec.basic, (vin: any) => validate(vin.data, vin.spec))
  })


  test('validate-node', async () => {
    await runset(validateSpec.node, (vin: any) => validate(vin.data, vin.spec))
  })


  test('validate-custom', async () => {
    const errs: any[] = []
    const extra = {
      $INTEGER: (state: any, _val: any, current: any) => {
        const { key } = state
        let out = getprop(current, key)

        let t = typeof out
        if ('number' !== t && !Number.isInteger(out)) {
          state.errs.push('Not an integer at ' + state.path.slice(1).join('.') + ': ' + out)
          return
        }

        return out
      },
    }

    const shape = { a: '`$INTEGER`' }

    let out = validate({ a: 1 }, shape, extra, errs)
    deepEqual(out, { a: 1 })
    equal(errs.length, 0)

    out = validate({ a: 'A' }, shape, extra, errs)
    deepEqual(out, { a: 'A' })
    deepEqual(errs, ['Not an integer at a: A'])
  })

})

