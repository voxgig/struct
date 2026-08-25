// The shared test runner comes from voxgig/omni, taken from npm as a
// devDependency the way jest or vitest would be. `@voxgig/omni/compat/struct`
// is a declared subpath of that package: it exposes omni behind THIS port's
// historical runner API, so the test files below import from here and never
// learn where the runner came from.
//
// This file used to be a ~99-line resolver. It located an omni CHECKOUT -
// $OMNI_HOME, then sibling paths, taking the first directory carrying
// spec/fib.json - checked that the checkout had been built, and `require`d
// its dist by absolute path. None of that is needed once the package is on a
// registry, and CI no longer checks omni out at all.
//
// Only the TESTS depend on omni. `@voxgig/omni` is a devDependency, which npm
// never installs transitively, so nothing a consumer of @voxgig/struct
// installs can reach it - see `tools/omni-isolation.js`, which proves that
// rather than asserting it.

import * as Path from 'node:path'

import {
  makeRunner as omnimakerunner,
  nullModifier,
  structprovider,
} from '@voxgig/omni/compat/struct'

// PASS THE CORPUS PATH ABSOLUTELY. omni's shim resolves a relative path
// against the first stack frame outside omni, and this port's test FILES sit
// one directory below the module that loads the runner: `test/omni.ts`
// compiles to `dist-test/omni.js` but `test/utility/StructUtility.ts` to
// `dist-test/utility/`. The same relative string therefore means two
// different places, and the deeper one resolved into
// `typescript/build/test/test.json`. Resolving here against THIS module's
// directory reproduces what the port's own runner did, and drops the stack
// walk entirely. Publishing omni did not change this - it is a fact about
// struct's outDir layout, not about how omni is delivered.
function corpuspath(testfile: string): string {
  return Path.isAbsolute(testfile) ? testfile : Path.join(__dirname, testfile)
}

const makeRunner = (testfile: string, client: any) => omnimakerunner(corpuspath(testfile), client)

// Literals rather than re-exports of the shim's constants. These values are
// part of the CORPUS FORMAT, not of omni's implementation, so they cannot
// drift silently - a change would fail every port at once, which is the point.
const NULLMARK = '__NULL__'
const UNDEFMARK = '__UNDEF__'
const EXISTSMARK = '__EXISTS__'

export { makeRunner, nullModifier, structprovider, NULLMARK, UNDEFMARK, EXISTSMARK }
