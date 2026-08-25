// REGISTER 4.13: nothing @voxgig/struct SHIPS may reach @voxgig/omni.
//
// omni is a test runner. Before this port took it from npm, package.json
// never contained the string "omni" at all and there was nothing to prove.
// Now it does, and that is exactly the condition that bit struct/go: its
// migration put omni/go/compat/struct in a normal package, `go mod tidy`
// resolved omni from the proxy, and `require github.com/voxgig/omni/go`
// landed in the PUBLISHED go.mod. Caught in review, not by CI.
//
// The isolation device here is the `devDependencies` block itself: npm
// never installs a devDependency transitively, so a consumer of
// @voxgig/struct cannot reach omni however hard they try. This asserts
// that device is intact, four ways, and reports every failure at once
// rather than stopping at the first.
//
// RUN IT AFTER `npm run build` - check (d) reads what npm pack would send,
// which comes off disk.

const { execSync } = require('node:child_process')
const { readFileSync } = require('node:fs')
const Path = require('node:path')

const ROOT = Path.join(__dirname, '..')
const OMNI = /^@voxgig\/omni(-js)?$/
const fails = []

// `execSync` with a literal command string, NOT execFile with an args array.
// On Windows `npm` is a .cmd shim that execFile will neither resolve nor
// execute - it fails with `spawnSync npm ENOENT`, which is how this was
// found. Running it through a shell is what works there, and execSync does
// that on both platforms; passing an ARRAY with `shell: true` would do it
// too but is deprecated (DEP0190, args concatenated unescaped). Every
// command here is a fixed literal with no interpolation, so the string form
// carries no injection surface.
const RUN = { cwd: ROOT, encoding: 'utf8' }

function read(file) {
  return JSON.parse(readFileSync(Path.join(ROOT, file), 'utf8'))
}

function npm(command) {
  // `npm ls --omit=dev` EXITS 1 when a named package is absent, so the exit
  // code cannot be the signal - parse the JSON and ignore the status.
  try {
    return JSON.parse(execSync(command, RUN))
  }
  catch (err) {
    const out = err.stdout
    if (null == out || '' === out) { throw err }
    return JSON.parse(out)
  }
}

// (a) THE LOAD-BEARING CHECK. omni in devDependencies and nowhere else.
const pkg = read('package.json')
for (const block of ['dependencies', 'peerDependencies', 'optionalDependencies']) {
  for (const name of Object.keys(pkg[block] || {})) {
    if (OMNI.test(name)) {
      fails.push('(a) ' + name + ' is in `' + block + '` - it must be devDependencies only')
    }
  }
}
if (!Object.keys(pkg.devDependencies || {}).some((n) => OMNI.test(n))) {
  fails.push('(a) no @voxgig/omni in devDependencies - has the harness moved?')
}

// (b) the production tree, walked, must not contain it.
function walk(node, path, seen) {
  for (const [name, entry] of Object.entries((node && node.dependencies) || {})) {
    if (OMNI.test(name)) {
      fails.push('(b) ' + name + ' is in the production tree via ' + path.concat(name).join(' > '))
    }
    if (!seen.has(entry)) {
      seen.add(entry)
      walk(entry, path.concat(name), seen)
    }
  }
}
walk(npm('npm ls --omit=dev --all --json'), [], new Set())

// (c) the lockfile, when there is one, must agree that the entry is
// dev-only. This repo gitignores package-lock.json (.gitignore:150) and
// commits none, so this is a LOCAL cross-check of npm's own bookkeeping
// rather than a check on committed intent - and a fresh clone that has not
// installed yet has no file at all, which is not a failure. What actually
// pins the version is the exact "0.1.0" in package.json; (a) is what
// carries the isolation.
let lock = null
try {
  lock = read('package-lock.json')
}
catch (err) {
  if ('ENOENT' !== err.code) { throw err }
}
if (null != lock) {
  for (const [route, entry] of Object.entries(lock.packages || {})) {
    const name = route.replace(/^.*node_modules\//, '')
    if (OMNI.test(name) && true !== entry.dev) {
      fails.push('(c) ' + route + ' is not marked dev:true in package-lock.json')
    }
  }
}

// (d) no SHIPPED file may name omni. package.json is exempt - (a) covers it,
// and devDependencies legitimately names it there.
const packed = JSON.parse(execSync('npm pack --dry-run --json', RUN))
const shipped = (packed[0] && packed[0].files) || []
for (const file of shipped) {
  if ('package.json' === file.path) { continue }
  if (!/\.(ts|js|mjs|cjs|json|map)$/.test(file.path)) { continue }
  const text = readFileSync(Path.join(ROOT, file.path), 'utf8')
  if (text.includes('voxgig/omni')) {
    fails.push('(d) shipped file ' + file.path + ' names voxgig/omni')
  }
}

if (0 < fails.length) {
  console.error('struct: omni is not isolated from the shipped library\n')
  for (const f of fails) { console.error('  ' + f) }
  process.exit(1)
}
console.log('struct: omni is devDependencies-only, absent from the production tree,')
console.log('        dev-locked, and named by no shipped file (' + shipped.length + ' files checked)')
