// The shared test runner comes from voxgig/omni, consumed as a local
// checkout. (`@voxgig/omni-js` IS on npm now, and the typescript port has
// moved to it; this port has not yet.) The checkout is resolved the same way voxgig/sekreto's ports
// resolve it: $OMNI_HOME first, then sibling paths, taking the first
// directory that carries spec/fib.json. Set OMNI_HOME if yours lives
// elsewhere. Only the tests depend on omni; the library never does.

const { existsSync } = require('node:fs')
const Path = require('node:path')

function omnihome() {
  const candidates = []

  // Resolve OMNI_HOME against the process cwd: existsSync would do that
  // anyway, but require() resolves relative paths against THIS file, so a
  // relative OMNI_HOME could pass the probe and then fail the require.
  if (process.env.OMNI_HOME) {
    candidates.push(Path.resolve(process.env.OMNI_HOME))
  }

  candidates.push(
    Path.resolve(__dirname, '..', '..', '..', 'omni'),
    Path.resolve(__dirname, '..', '..', '..', '..', 'omni'),
    '/workspace/omni',
    '/home/user/omni',
  )

  for (const candidate of candidates) {
    if (existsSync(Path.join(candidate, 'spec', 'fib.json'))) {
      return candidate
    }
  }

  throw new Error('struct: voxgig/omni checkout not found - set OMNI_HOME')
}

module.exports = require(Path.join(omnihome(), 'javascript', 'compat', 'struct.js'))
