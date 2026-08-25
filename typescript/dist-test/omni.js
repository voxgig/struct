"use strict";
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
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.EXISTSMARK = exports.UNDEFMARK = exports.NULLMARK = exports.structprovider = exports.nullModifier = exports.makeRunner = void 0;
const Path = __importStar(require("node:path"));
const struct_1 = require("@voxgig/omni/compat/struct");
Object.defineProperty(exports, "nullModifier", { enumerable: true, get: function () { return struct_1.nullModifier; } });
Object.defineProperty(exports, "structprovider", { enumerable: true, get: function () { return struct_1.structprovider; } });
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
function corpuspath(testfile) {
    return Path.isAbsolute(testfile) ? testfile : Path.join(__dirname, testfile);
}
const makeRunner = (testfile, client) => (0, struct_1.makeRunner)(corpuspath(testfile), client);
exports.makeRunner = makeRunner;
// Literals rather than re-exports of the shim's constants. These values are
// part of the CORPUS FORMAT, not of omni's implementation, so they cannot
// drift silently - a change would fail every port at once, which is the point.
const NULLMARK = '__NULL__';
exports.NULLMARK = NULLMARK;
const UNDEFMARK = '__UNDEF__';
exports.UNDEFMARK = UNDEFMARK;
const EXISTSMARK = '__EXISTS__';
exports.EXISTSMARK = EXISTSMARK;
//# sourceMappingURL=omni.js.map