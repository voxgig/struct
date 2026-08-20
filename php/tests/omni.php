<?php

/**
 * The shared test runner comes from voxgig/omni, consumed as a local
 * checkout - omni is deliberately not published to Packagist (yet). The
 * checkout is resolved the same way voxgig/sekreto's ports resolve it:
 * $OMNI_HOME first, then sibling paths, taking the first directory that
 * carries spec/fib.json. Set OMNI_HOME if yours lives elsewhere.
 *
 * Only the tests depend on omni. The library never does, and composer.json
 * gains no requirement - this file is a plain `require`, so `composer
 * install` and anything that ships from `src/` are untouched.
 *
 * This is the PHP counterpart of python/tests/omni.py, ruby/omni.rb and
 * javascript/test/omni.js. The runner API it exposes is omni's struct
 * compat shim, so the test files call `Runner::makeRunner` exactly as they
 * did when that class lived here.
 */

declare(strict_types=1);

namespace Voxgig\Struct;

function omnihome(): string
{
    $here = __DIR__;
    $candidates = [];

    $env = getenv('OMNI_HOME');
    if (false !== $env && '' !== $env) {
        $candidates[] = $env;
    }

    $candidates[] = $here . '/../../../omni';
    $candidates[] = $here . '/../../../../omni';
    $candidates[] = '/workspace/omni';
    $candidates[] = '/home/user/omni';

    foreach ($candidates as $candidate) {
        if (is_file($candidate . '/spec/fib.json')) {
            return realpath($candidate);
        }
    }

    throw new \RuntimeException(
        'struct: voxgig/omni checkout not found - set OMNI_HOME'
    );
}

/**
 * omni's shim, under the name struct's own test files already use. The
 * in-situ `tests/Runner.php` is gone; this class replaces it, and the call
 * sites (`Runner::makeRunner`, `Runner::nullModifier`) are unchanged.
 *
 * The shim is `final`, so this delegates rather than extends - which is the
 * better shape anyway: it names exactly the API struct's tests rely on, so
 * anything else the shim grows stays omni's business.
 */
final class Runner
{
    // Literals rather than aliases of the shim's constants: those would force
    // omni to be loaded when this file is merely included. The values are part
    // of the corpus format, not of omni's implementation, so they cannot drift
    // silently - a change would fail every port at once.
    public const NULLMARK = '__NULL__';
    public const UNDEFMARK = '__UNDEF__';
    public const EXISTSMARK = '__EXISTS__';

    /** Load omni's shim on first use, not at include time. */
    private static function shim(): string
    {
        if (!class_exists(\Voxgig\Omni\Compat\Struct::class, false)) {
            require_once omnihome() . '/php/compat/Struct.php';
        }
        return \Voxgig\Omni\Compat\Struct::class;
    }

    public static function makeRunner(string $testfile, $client): callable
    {
        $shim = self::shim();
        return $shim::makeRunner($testfile, $client);
    }

    public static function nullModifier(
        $val,
        $key,
        &$parent = null,
        $state = null,
        $store = null
    ): void {
        $shim = self::shim();
        $shim::nullModifier($val, $key, $parent, $state, $store);
    }
}
