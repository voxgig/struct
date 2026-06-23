// Smoke check (not a test): prove the provider loads and normalizes.
// Run: node --experimental-strip-types test/proto/ts/smoke.ts
import { TestProvider, equal, equalStrict, errorMatches, structMatch } from './provider.ts'

const p = TestProvider.load()
const fns = p.functions()
console.log('functions:', fns.join(', '))

let total = 0
const kinds: Record<string, number> = {}
const inkinds: Record<string, number> = {}
for (const fn of fns) {
  for (const e of p.entries(fn)) {
    total++
    kinds[e.expect.kind] = (kinds[e.expect.kind] ?? 0) + 1
    inkinds[e.input.kind] = (inkinds[e.input.kind] ?? 0) + 1
  }
}
console.log('total entries:', total)
console.log('expect kinds:', JSON.stringify(kinds))
console.log('input kinds:', JSON.stringify(inkinds))

const first = p.entries('getpath', 'basic')[0]
console.log('sample getpath/basic[0]:', JSON.stringify({
  id: first.id, doc: first.doc, input: first.input, expect: first.expect,
}))

// helper sanity
console.log('equal(42,42):', equal(42, 42))
console.log('equal(null,undefined):', equal(null, undefined))
console.log('equalStrict(null,undefined):', equalStrict(null, undefined))
console.log('errorMatches(any):', errorMatches({ any: true, text: null, regex: false }, 'boom'))
console.log('errorMatches(substr):', errorMatches({ any: false, text: 'not found', regex: false }, 'Key NOT FOUND here'))
console.log('structMatch ok:', structMatch({ a: { b: 2 } }, { a: { b: 2 }, c: 9 }).ok)
console.log('structMatch fail:', JSON.stringify(structMatch({ a: { b: 2 } }, { a: { b: 3 } })))
