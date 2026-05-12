import { validate, transform, M_KEYPRE } from '..'

let out: any
let errs: any

// errs = []
// out = transform(undefined, undefined, { errs })
// console.log('transform-OUT', out, errs)

// errs = []
// out = transform(null, undefined, { errs })
// console.log('transform-OUT', out, errs)

// errs = []
// out = transform(undefined, null, { errs })
// console.log('transform-OUT', out, errs)

// errs = []
// out = transform(undefined, undefined, { errs })
// console.log('transform-OUT', out, errs)

// errs = []
// out = validate(undefined, undefined, { errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate(undefined, { x: 1 }, { errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate({ x: 2 }, undefined, { errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate({ x: 3 }, { y: '`dm$=a`' }, { meta: { dm: { a: 4 } }, errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate({ x: 4 }, { y: '`dm$=a`' }, { meta: { dm: {} }, errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate({ x: 5 }, { y: '`dm$=a.b`' }, { meta: { dm: { a: 5 } }, errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate(undefined, {
//   // x: '`dm$=a`'
//   // x: 9
//   x: ['`$EXACT`', 9]
// }, { meta: { dm: { a: 9 } }, errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate({}, { '`$OPEN`': true, z: 1 }, { errs })
// console.log('validate-OUT', out, errs)

// errs = []
// out = validate(1000, 1001, { errs })
// console.log('validate-OUT', out, errs)

const extra = {
  $CAPTURE: (inj: any) => {
    if (M_KEYPRE === inj.mode) {
      const { val, prior } = inj
      const { dparent, key } = prior
      const dval = dparent[key]
      if (undefined !== dval) {
        inj.meta.capture[val] = dval
      }
    }
  },
}

const meta = { capture: {} }
out = transform(
  { a: { b: 1, c: 2 } },
  { a: { b: { '`$CAPTURE`': 'x' }, c: { '`$CAPTURE`': 'x' } } },
  { extra, errs, meta },
)
console.dir(out, { depth: null })
console.dir(errs, { depth: null })
console.dir(meta, { depth: null })
