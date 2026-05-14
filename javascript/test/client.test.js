// RUN: npm test
// RUN-SOME: npm run test-some --pattern=getpath

const { test, describe } = require('node:test')

const { makeRunner } = require('./runner')

const { SDK } = require('./sdk.js')

const TEST_JSON_FILE = '../../build/test/test.json'

describe('client', async () => {
  const runner = await makeRunner(TEST_JSON_FILE, await SDK.test())

  const { spec, runset, subject } = await runner('check')

  test('client-check-basic', async () => {
    await runset(spec.basic, subject)
  })
})
