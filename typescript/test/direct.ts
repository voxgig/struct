import { transform, M_KEYPRE } from '..'

const errs: any = []














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
const out = transform(
  { a: { b: 1, c: 2 } },
  { a: { b: { '`$CAPTURE`': 'x' }, c: { '`$CAPTURE`': 'x' } } },
  { extra, errs, meta },
)
console.dir(out, { depth: null })
console.dir(errs, { depth: null })
console.dir(meta, { depth: null })
