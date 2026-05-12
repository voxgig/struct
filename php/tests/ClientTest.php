<?php

namespace Voxgig\Struct;

use PHPUnit\Framework\TestCase;

require_once __DIR__ . '/SDK.php';
require_once __DIR__ . '/Runner.php';

class ClientTest extends TestCase
{
    private const TEST_JSON_FILE = '../../build/test/test.json';

    public function testClientCheckBasic(): void
    {
        $runner = Runner::makeRunner(self::TEST_JSON_FILE, SDK::test());
        $runpack = $runner('check');

        $spec = $runpack['spec'];
        $runset = $runpack['runset'];
        $subject = $runpack['subject'];

        $runset($spec['basic'], $subject);

        // If we get here without exceptions, the test passed
        $this->assertTrue(true);
    }
}
