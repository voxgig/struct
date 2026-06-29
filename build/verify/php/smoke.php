<?php
// Smoke client for the PUBLISHED PHP port, built against the source
// vendored from the git tag php/v<VERSION>. The vendored source path is
// passed as argv[1] (the extracted .../php directory).

declare(strict_types=1);

if ($argc < 2) {
    fwrite(STDERR, "FAIL php: missing vendored source dir argument\n");
    exit(2);
}

$src = rtrim($argv[1], '/') . '/src/Struct.php';
if (!is_file($src)) {
    fwrite(STDERR, "FAIL php: vendored Struct.php not found at $src\n");
    exit(2);
}
require $src;

use Voxgig\Struct\Struct;

$store = ['db' => ['host' => 'localhost']];
$got = Struct::getpath($store, 'db.host');

if ($got === 'localhost') {
    echo "OK php: getpath(db.host) = localhost\n";
    exit(0);
}

fwrite(STDERR, 'FAIL php: getpath(db.host) = ' . var_export($got, true) . " (want localhost)\n");
exit(1);
