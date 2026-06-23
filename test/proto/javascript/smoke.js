// Smoke test for the JavaScript test-provider port.
// Loads the corpus and prints summary stats plus one normalized entry.

import { TestProvider } from './provider.js'

const provider = TestProvider.load()

const functions = provider.functions()
console.log('functions: ' + functions.join(', '))

const expectCounts = {}
const inputCounts = {}
let total = 0

for (const fn of functions) {
  for (const entry of provider.entries(fn)) {
    total++
    expectCounts[entry.expect.kind] = (expectCounts[entry.expect.kind] || 0) + 1
    inputCounts[entry.input.kind] = (inputCounts[entry.input.kind] || 0) + 1
  }
}

console.log('total entries: ' + total)

console.log(
  'expect kinds: ' +
    Object.keys(expectCounts)
      .map((k) => `${k}=${expectCounts[k]}`)
      .join(', '),
)

console.log(
  'input kinds: ' +
    Object.keys(inputCounts)
      .map((k) => `${k}=${inputCounts[k]}`)
      .join(', '),
)

const e = provider.entries('getpath', 'basic')[0]
console.log(
  'getpath/basic[0]: id=' +
    e.id +
    ', doc=' +
    e.doc +
    ', input.kind=' +
    e.input.kind +
    ', expect.kind=' +
    e.expect.kind +
    ', expect.value=' +
    JSON.stringify(e.expect.value),
)
