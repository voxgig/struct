"use strict";
// RUN: npm test
// RUN-SOME: npm run test-some --pattern=check
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const runner_1 = require("./runner");
const sdk_js_1 = require("./sdk.js");
const TEST_JSON_FILE = '../../build/test/test.json';
(0, node_test_1.describe)('client', async () => {
    const runner = await (0, runner_1.makeRunner)(TEST_JSON_FILE, await sdk_js_1.SDK.test());
    const { spec, runset, subject } = await runner('check');
    (0, node_test_1.test)('client-check-basic', async () => {
        await runset(spec.basic, subject);
    });
});
//# sourceMappingURL=client.test.js.map