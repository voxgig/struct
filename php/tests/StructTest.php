<?php

use PHPUnit\Framework\TestCase;
require_once __DIR__ . '/../src/Struct.php'; // Ensure this path is correct

use Voxgig\Struct\Struct; // Import the Struct class

class StructTest extends TestCase {

    private array $testSpec;

    protected function setUp(): void {
        $jsonPath = __DIR__ . '/../../build/test/test.json';

        if (!file_exists($jsonPath)) {
            throw new RuntimeException("Test JSON file not found: $jsonPath");
        }

        $jsonContent = file_get_contents($jsonPath);
        if ($jsonContent === false) {
            throw new RuntimeException("Failed to read test JSON: $jsonPath");
        }

        $this->testSpec = json_decode($jsonContent, true);

        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new RuntimeException("Invalid JSON: " . json_last_error_msg());
        }

        if (!isset($this->testSpec['minor'])) {
            throw new RuntimeException("Missing 'minor' section in test JSON.");
        }

        $this->testSpec = $this->testSpec['minor'];
    }

    private function testSet(array $tests, callable $apply) {
        foreach ($tests['set'] as $entry) {
            if (isset($entry['out'])) {
                $this->assertEquals($entry['out'], $apply($entry['in']));
            } else {
                $this->expectException(TypeError::class);
                $apply($entry['in']);
            }
        }
    }

    public function testMinorFunctionsExist() {
        $this->assertTrue(method_exists(Struct::class, 'clone'), "Method clone() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'isNode'), "Method isNode() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'isMap'), "Method isMap() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'isList'), "Method isList() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'isKey'), "Method isKey() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'isEmpty'), "Method isEmpty() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'stringify'), "Method stringify() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'escre'), "Method escre() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'escurl'), "Method escurl() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'items'), "Method items() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'getProp'), "Method getProp() does not exist");
        $this->assertTrue(method_exists(Struct::class, 'setProp'), "Method setProp() does not exist");
    }

    public function testClone() {
        $this->testSet($this->testSpec['clone'], [Struct::class, 'clone']);
    }

    public function testIsNode() {
        $this->testSet($this->testSpec['isnode'], [Struct::class, 'isNode']);
    }

    public function testIsMap() {
        $this->testSet($this->testSpec['ismap'], [Struct::class, 'isMap']);
    }

    public function testIsList() {
        $this->testSet($this->testSpec['islist'], [Struct::class, 'isList']);
    }

    public function testIsKey() {
        $this->testSet($this->testSpec['iskey'], [Struct::class, 'isKey']);
    }

    public function testIsEmpty() {
        $this->testSet($this->testSpec['isempty'], [Struct::class, 'isEmpty']);
    }

    public function testEscre() {
        $this->testSet($this->testSpec['escre'], [Struct::class, 'escre']);
    }

    public function testEscurl() {
        $this->testSet($this->testSpec['escurl'], [Struct::class, 'escurl']);
    }

    public function testStringify() {
        $this->testSet($this->testSpec['stringify'], function ($input) {
            return isset($input['max']) ? Struct::stringify($input['val'], $input['max']) : Struct::stringify($input['val']);
        });
    }

    public function testItems() {
        $this->testSet($this->testSpec['items'], [Struct::class, 'items']);
    }

    public function testGetProp() {
        $this->testSet($this->testSpec['getprop'], function ($input) {
            return isset($input['alt']) ? Struct::getProp($input['val'], $input['key'], $input['alt']) : Struct::getProp($input['val'], $input['key']);
        });
    }

    public static function setProp(&$parent, $key, $val) {
        if (!self::isKey($key)) return;
    
        if (!is_array($parent)) {
            throw new \TypeError("Parent must be an array.");
        }
        // Always set the key, even if $val is null
        $parent[$key] = $val;
    }
    
}
