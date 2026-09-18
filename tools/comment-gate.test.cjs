'use strict'
const { test } = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const os = require('node:os')
const cp = require('node:child_process')
const gate = require('./comment-gate.cjs')
const rules = (text, file = 'probe.ts') => gate.checkText(file, text).findings.map(f => f.rule)

test('repository satisfies the policy', () => {
  const findings = gate.checkAll().flatMap(r => r.findings)
  assert.deepEqual(findings, [], JSON.stringify(findings.slice(0, 20)))
})

test('short explanation passes and each prohibited form fails', () => {
  assert.deepEqual(rules('// The sentinel distinguishes absence from null.\nconst sentinel = null'), [])
  for (const [rule, text] of [
    ['long-block', Array(6).fill('// explanation').join('\n')],
    ['narrative', '// We fixed the old implementation.'],
    ['requirements', '// The business requirement is here.'],
    ['commented-code', '// const removed = fn();'],
    ['count-claim', '// There are three passes.'],
    ['dated-claim', '// Updated 2026-09-18.'],
    ['issue-ref', '// See #123.'],
    ['version-claim', '// Available in v1.2.3.'],
    ['stale-path', '// See missing-comment-gate-probe/no-file.ts.'],
    ['stale-symbol', '// Uses `CommentGateNonexistentSymbolXyz`.'],
    ['stale-adr', '// See ADR-999.'],
  ]) assert.ok(rules(text).includes(rule), rule)
})

test('density boundary and small-file floor', () => {
  const comments = Array.from({length: 9}, (_, i) => '// explanation\n\n').join('')
  const code = n => Array.from({length: n}, (_, i) => `const x${i} = ${i}`).join('\n')
  assert.ok(rules(comments + code(74)).includes('dense-file'))
  assert.ok(!rules(comments + code(75)).includes('dense-file'))
  assert.ok(!rules('// explanation\n'.repeat(8) + code(1)).includes('dense-file'))
})

test('licenses and tool directives survive', () => {
  for (const text of ['/* Copyright 2026 Example, MIT License */',
    '// SPDX-License-Identifier: MIT', '//go:build linux', '//go:embed data.json',
    '//covergate:allow unreachable state', '// @ts-expect-error intentional invalid input',
    '/* node:coverage ignore next */', '// eslint-disable-next-line rule', '//nolint:errcheck', '// EJECT-START', '// EJECT-END', '// <[SLOT]>', '// #SecretsImport', '/*#__PURE__*/']) {
    assert.deepEqual(rules(text), [], text)
  }
})

test('strings, regular expressions, Rust lifetimes and raw strings are code', () => {
  const fixtures = [
    ['ts', 'const url = "http://host/path"; const r = /[/]/; // explanation'],
    ['ts', 'function f() { return /https?:\\/\\// } // explanation'],
    ['ts', 'const nested = `outer ${`inner ${value}`} text`; // explanation'],
    ['ts', 'const template = `// not prose\n/* not prose */`; // explanation'],
    ['go', 'var text = `// not prose\n/* not prose */` // explanation'],
    ['rs', 'fn f<\'a>(x: &\'a str) {} // explanation'],
    ['rs', 'let text = r##"// not prose " /* not prose */"##; // explanation'],
    ['rs', 'let text = br#"// not prose"#; let c = \'x\'; // explanation'],
    ['rs', '/* outer /* nested */ outer */ // explanation'],
  ]
  for (const [lang, text] of fixtures) {
    const comments = gate.lex(text, lang).comments
    assert.equal(comments.at(-1).text, '// explanation', text)
    assert.equal(comments.length, text.startsWith('/* outer') ? 2 : 1, text)
  }
})

test('scope includes authored implementation files and excludes output', () => {
  for (const file of ['src/probe.ts', 'go/probe.go', 'rust/src/probe.rs', '.sdk/src/probe.ts'])
    assert.equal(gate.gated(file), true, file)
  for (const file of ['tools/probe.cjs', 'dist/probe.ts', 'rust/target/probe.rs', 'node_modules/probe.ts', 'vendor/probe.go'])
    assert.equal(gate.gated(file), false, file)
})

test('CLI and pre-push reject violations, discover new files, and emit complete JSON', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'comment-gate-test-'))
  try {
    fs.mkdirSync(path.join(dir, 'tools'))
    fs.copyFileSync(path.join(__dirname, 'comment-gate.cjs'), path.join(dir, 'tools/comment-gate.cjs'))
    fs.writeFileSync(path.join(dir, 'tools/comment-scope.json'), '{"exclude":{}}')
    cp.execFileSync('git', ['init', '-q'], {cwd: dir})
    fs.writeFileSync(path.join(dir, '.gitignore'), 'ignored/\n')
    fs.mkdirSync(path.join(dir, 'ignored'))
    fs.writeFileSync(path.join(dir, 'ignored/probe.ts'), '// TODO: ignored\n')
    const invoke = args => cp.spawnSync(process.execPath, ['tools/comment-gate.cjs', ...args], {cwd: dir, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024})
    assert.equal(invoke([]).status, 0)
    fs.writeFileSync(path.join(dir, 'probe.ts'), '// TODO: fix this\n\n'.repeat(1000))
    const failed = invoke(['--json'])
    assert.equal(failed.status, 1)
    assert.ok(JSON.parse(failed.stdout).totals.findings > 0)
    const hook = path.join(__dirname, '..', '.githooks/pre-push')
    if (process.platform !== 'win32') {
      assert.equal(cp.spawnSync('sh', [hook], {cwd: dir}).status, 1)
    }
    fs.writeFileSync(path.join(dir, 'probe.ts'), 'const ready = true\n')
    assert.equal(invoke([]).status, 0)
  } finally { fs.rmSync(dir, {recursive: true, force: true}) }
})

test('both Aontu extensions enforce hash comments and preserve model literals', () => {
  for (const ext of ['aon', 'aontu']) {
    const file = `model/target/probe.${ext}`
    assert.equal(gate.gated(file), true)
    assert.equal(gate.language(file), 'aon')
    assert.deepEqual(rules('# The sentinel distinguishes absence from null.\nvalue: null', file), [])
    for (const [rule, text] of [
      ['narrative', '# TODO: restore this'],
      ['long-block', '# explanation\n'.repeat(6)],
      ['requirements', '# The business requirement is here.'],
      ['commented-code', '# value: true'],
      ['commented-code', '# nested: value: { enabled: false }'],
      ['stale-path', '# See missing-comment-gate-probe/schema.aontu.'],
    ]) assert.ok(rules(text, file).includes(rule), `${ext}: ${rule}`)
    const literal = 'single: \'# TODO: literal\'\ndouble: "# TODO: literal"\nmulti: `# TODO: literal\n${value} // literal\n\\`# still literal`\nurl: https://example.test/path\n# explanation'
    const comments = gate.lex(literal, gate.language(file)).comments
    assert.deepEqual(comments.map(c => c.text), ['# explanation'])
    assert.deepEqual(rules(literal, file), [])
    assert.deepEqual(rules('# Copyright 2026 Example, MIT License', file), [])
    const dense = '# explanation\n\n'.repeat(9) + 'value: true\n'
    assert.ok(rules(dense, file).includes('dense-file'))
  }
})

test('CLI and hook reject new models in target directories under either extension', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'comment-model-test-'))
  try {
    fs.mkdirSync(path.join(dir, 'tools'))
    fs.mkdirSync(path.join(dir, 'model/target'), {recursive: true})
    fs.copyFileSync(path.join(__dirname, 'comment-gate.cjs'), path.join(dir, 'tools/comment-gate.cjs'))
    fs.writeFileSync(path.join(dir, 'tools/comment-scope.json'), JSON.stringify({exclude: {}, excludeModels: {'golden': 'Byte-exact generated model output.'}}))
    cp.execFileSync('git', ['init', '-q'], {cwd: dir})
    fs.mkdirSync(path.join(dir, 'golden'))
    fs.writeFileSync(path.join(dir, 'golden/output.aontu'), '# TODO: golden\n')
    const invoke = () => cp.spawnSync(process.execPath, ['tools/comment-gate.cjs', '--json'], {cwd: dir, encoding: 'utf8'})
    assert.equal(invoke().status, 0)
    fs.writeFileSync(path.join(dir, 'golden/implementation.ts'), '// TODO: still checked\n')
    assert.equal(invoke().status, 1)
    fs.unlinkSync(path.join(dir, 'golden/implementation.ts'))
    for (const ext of ['aon', 'aontu']) {
      const file = path.join(dir, `model/target/probe.${ext}`)
      fs.writeFileSync(file, '# TODO: remove this\nvalue: true\n')
      const bad = invoke()
      assert.equal(bad.status, 1)
      assert.ok(JSON.parse(bad.stdout).totals.findings > 0)
      if (process.platform !== 'win32')
        assert.equal(cp.spawnSync('sh', [path.join(__dirname, '..', '.githooks/pre-push')], {cwd: dir}).status, 1)
      fs.writeFileSync(file, 'value: "# TODO: literal"\n')
      assert.equal(invoke().status, 0)
    }
  } finally { fs.rmSync(dir, {recursive: true, force: true}) }
})
