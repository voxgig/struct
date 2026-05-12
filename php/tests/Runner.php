<?php

namespace Voxgig\Struct;

use Exception;

require_once __DIR__ . '/../src/Struct.php';

class Runner
{
    private const NULLMARK  = "__NULL__";
    private const UNDEFMARK = "__UNDEF__";

    public static function makeRunner(string $testfile, $client): callable
    {
        return function (string $name, $store = null) use ($testfile, $client) {
            $store = $store ?? [];
            $utility = $client->utility();
            $structUtils = $utility->struct;
            $spec = self::resolveSpec($name, $testfile);
            $clients = self::resolveClients($client, $spec, $store, $structUtils);
            $subject = self::resolveSubject($name, $utility);

            $runsetflags = function ($testspec, array $flags = [], $testsubject = null) use ($name, $client, $structUtils, &$subject, $clients) {
                $subject = $testsubject ?? $subject;
                $flags = self::resolveFlags($flags);
                $testspecmap = self::fixJSON($testspec, $flags);
                if (!isset($testspecmap['set']) || !is_array($testspecmap['set'])) {
                    throw new Exception("Test specification 'set' is missing or not an array");
                }
                $testset = $testspecmap['set'];
                foreach ($testset as &$entry) {
                    try {
                        $entry = self::resolveEntry($entry, $flags);
                        $testpack = self::resolveTestPack($name, $entry, $subject, $client, $clients);
                        $args = self::resolveArgs($entry, $testpack, $structUtils);
                        $res = call_user_func_array($testpack['subject'], $args);
                        $res = self::fixJSON($res, $flags);
                        $entry['res'] = $res;
                        self::checkResult($entry, $res, $structUtils);
                    } catch (Exception $err) {
                        self::handleError($entry, $err, $structUtils);
                    }
                }
            };

            $runset = function ($testspec, $testsubject = null) use ($runsetflags) {
                $runsetflags($testspec, [], $testsubject);
            };

            return [
                'spec'        => $spec,
                'runset'      => $runset,
                'runsetflags' => $runsetflags,
                'subject'     => $subject,
                'client'      => $client,
            ];
        };
    }

    private static function resolveSpec(string $name, string $testfile): array
    {
        // If $testfile is an absolute path, use it as-is; otherwise, build a path relative to __DIR__
        if (preg_match('/^(\/|[A-Za-z]:[\/\\\\])/', $testfile)) {
            $path = $testfile;
        } else {
            $path = rtrim(__DIR__, DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . $testfile;
        }
        $json = file_get_contents($path);
        if ($json === false) {
            throw new Exception("Unable to read test file at $path");
        }
        $alltests = json_decode($json, true);
        if (isset($alltests['primary'][$name])) {
            return $alltests['primary'][$name];
        } elseif (isset($alltests[$name])) {
            return $alltests[$name];
        } else {
            return $alltests;
        }
    }

    private static function resolveClients($client, array $spec, $store, $structUtils): array
    {
        $clients = [];
        if (isset($spec['DEF']) && isset($spec['DEF']['client'])) {
            foreach ($spec['DEF']['client'] as $cn => $cdef) {
                $copts = $cdef['test']['options'] ?? [];
                if (is_array($store) && method_exists($structUtils, 'inject')) {
                    $structUtils->inject($copts, $store);
                }
                $clients[$cn] = $client->test($copts);
            }
        }
        return $clients;
    }

    private static function resolveSubject(string $name, $container, $subject = null)
    {
        return $subject ?? ($container->$name ?? null);
    }

    private static function resolveFlags($flags = null): array
    {
        if ($flags === null) {
            $flags = [];
        }
        $flags['null'] = $flags['null'] ?? true;
        $flags['null'] = (bool)$flags['null'];
        return $flags;
    }

    private static function resolveEntry($entry, array $flags)
    {
        if (!isset($entry['out']) && $flags['null']) {
            $entry['out'] = self::NULLMARK;
        }
        return $entry;
    }

    private static function checkResult(array $entry, $res, $structUtils)
    {
        $matched = false;
        if (isset($entry['match'])) {
            $result = [
                'in'  => $entry['in'] ?? null,
                'out' => $entry['res'] ?? null,
                'ctx' => $entry['ctx'] ?? null,
            ];
            self::match($entry['match'], $result, $structUtils);
            $matched = true;
        }
        if (isset($entry['out']) && $entry['out'] === $res) {
            return;
        }
        if ($matched && ($entry['out'] === self::NULLMARK || $entry['out'] === null)) {
            return;
        }
        if (json_encode($res) !== json_encode($entry['out'])) {
            throw new \AssertionError('Deep equality failed: expected ' .
                $structUtils->stringify($entry['out']) . ' but got ' .
                $structUtils->stringify($res));
        }
    }

    private static function handleError(&$entry, \Exception $err, $structUtils)
    {
        $entry['thrown'] = $err->getMessage();
        if (isset($entry['err'])) {
            if ($entry['err'] === true || self::matchval($entry['err'], $err->getMessage(), $structUtils)) {
                if (isset($entry['match'])) {
                    self::match(
                        $entry['match'],
                        [
                            'in'  => $entry['in'] ?? null,
                            'out' => $entry['res'] ?? null,
                            'ctx' => $entry['ctx'] ?? null,
                            'err' => $err->getMessage(),
                        ],
                        $structUtils
                    );
                }
                return;
            }
            throw new \AssertionError('ERROR MATCH: [' . $structUtils->stringify($entry['err']) .
                '] <=> [' . $err->getMessage() . ']');
        } elseif ($err instanceof \AssertionError) {
            throw new \AssertionError($err->getMessage() .
                "\n\nENTRY: " . json_encode($entry, JSON_PRETTY_PRINT));
        } else {
            throw new Exception($err->getTraceAsString() .
                "\n\nENTRY: " . json_encode($entry, JSON_PRETTY_PRINT));
        }
    }

    private static function resolveArgs($entry, array $testpack, $structUtils): array
    {
        $args = [];
        if (isset($entry['in'])) {
            $args[] = $structUtils->clone($entry['in']);
        }
        if (isset($entry['ctx'])) {
            $args = [$entry['ctx']];
        } elseif (isset($entry['args'])) {
            $args = $entry['args'];
        }
        if ((isset($entry['ctx']) || isset($entry['args'])) && isset($args[0]) && is_array($args[0])) {
            $first = $structUtils->clone($args[0]);
            $first['client'] = $testpack['client'];
            $first['utility'] = $testpack['utility'];
            $args[0] = $first;
            $entry['ctx'] = $first;
        }
        return $args;
    }

    private static function resolveTestPack(string $name, $entry, $subject, $client, array $clients): array
    {
        $testpack = [
            'client'  => $client,
            'subject' => $subject,
            'utility' => $client->utility(),
        ];
        if (isset($entry['client'])) {
            $testpack['client'] = $clients[$entry['client']] ?? $client;
            $testpack['utility'] = $testpack['client']->utility();
            $testpack['subject'] = self::resolveSubject($name, $testpack['utility']);
        }
        return $testpack;
    }

    private static function match($check, $base, $structUtils): void
    {
        $structUtils->walk($check, function ($key, $val, $parent, $path) use ($base, $structUtils) {
            if (!is_array($val) && !is_object($val)) {
                $baseval = $structUtils->getpath($base, $path);
                if ($baseval === $val) {
                    return;
                }
                if ($val === self::UNDEFMARK && $baseval === null) {
                    return;
                }
                if (!self::matchval($val, $baseval, $structUtils)) {
                    throw new \AssertionError(
                        'MATCH: ' . implode('.', $path) .
                        ': [' . $structUtils->stringify($val) .
                        '] <=> [' . $structUtils->stringify($baseval) . ']'
                    );
                }
            }
        });
    }

    private static function matchval($check, $base, $structUtils): bool
    {
        $pass = ($check === $base);
        if (!$pass) {
            if (is_string($check)) {
                $basestr = $structUtils->stringify($base);
                if (preg_match('/^\/(.+)\/$/', $check, $matches)) {
                    $pass = preg_match('/' . $matches[1] . '/', $basestr) === 1;
                } else {
                    $pass = stripos($basestr, $structUtils->stringify($check)) !== false;
                }
            } elseif (is_callable($check)) {
                $pass = true;
            }
        }
        return $pass;
    }

    private static function fixJSON($val, array $flags)
    {
        if ($val === null) {
            return $flags['null'] ? self::NULLMARK : $val;
        }
        $replacer = function ($v) use ($flags, &$replacer) {
            if ($v === null && $flags['null']) {
                return self::NULLMARK;
            }
            if ($v instanceof \Exception) {
                return array_merge(get_object_vars($v), [
                    'name'    => get_class($v),
                    'message' => $v->getMessage(),
                ]);
            }
            if (is_array($v)) {
                return array_map($replacer, $v);
            }
            if (is_object($v)) {
                $arr = get_object_vars($v);
                return array_map($replacer, $arr);
            }
            return $v;
        };
        $fixed = $replacer($val);
        return json_decode(json_encode($fixed), true);
    }

    public static function nullModifier($val, $key, array &$parent)
    {
        if ($val === self::NULLMARK) {
            $parent[$key] = null;
        } elseif (is_string($val)) {
            $parent[$key] = str_replace('__NULL__', 'null', $val);
        }
    }
}
