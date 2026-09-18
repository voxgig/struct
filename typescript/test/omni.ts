
import * as Path from 'node:path'

import {
  makeRunner as omnimakerunner,
  nullModifier,
  structprovider,
} from '@voxgig/omni/compat/struct'

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
