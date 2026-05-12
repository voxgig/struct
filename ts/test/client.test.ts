// RUN: npm test
// RUN-SOME: npm run test-some --pattern=check

import { test, describe } from 'node:test'

import { makeRunner } from './runner'

import { SDK } from './sdk.js'

const TEST_JSON_FILE = '../../build/test/test.json'

describe('client', async () => {
  const runner = await makeRunner(TEST_JSON_FILE, await SDK.test())

  const { spec, runset, subject } = await runner('check')

  test('client-check-basic', async () => {
    await runset(spec.basic, subject)
  })
})
