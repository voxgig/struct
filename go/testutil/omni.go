// The shared test runner comes from voxgig/omni, taken from its release tag:
// go.mod beside this file requires github.com/voxgig/omni/go v0.1.0 and
// go.sum pins it with checksum-database-backed hashes. Go needs the directory
// prefix for a module in a subdirectory, so the tag is `go/v0.1.0`. No
// $OMNI_HOME, no sibling checkout, no path that works on one machine only.
//
// That alone would not keep the library clean, which is why this package is
// a nested module (see go.mod beside this file). A single module would put
// this import in `go build ./...`, breaking a fresh checkout that has no
// omni - and, worse, `go mod tidy` would resolve omni from the proxy (it is
// a public repo) and write it into voxgigstruct's published dependency
// graph. Nested, `./...` in the parent skips it, and neither can happen.
//
// This file is the Go counterpart of javascript/test/omni.js and
// python/tests/omni.py. The runner API below is omni's struct compat shim
// re-exported under struct's own names, so the test files change by nothing
// at all: they still call runner.MakeRunner and runner.TestSDK.

package runner

import (
	structcompat "github.com/voxgig/omni/go/compat/struct"
)

// The runner API, from omni.
type (
	Subject     = structcompat.Subject
	RunSet      = structcompat.RunSet
	RunSetFlags = structcompat.RunSetFlags
	RunPack     = structcompat.RunPack
)

// The sentinels, under struct's names.
var (
	NULLMARK   = structcompat.NULLMARK   // Value is JSON null
	UNDEFMARK  = structcompat.UNDEFMARK  // Value is not present (thus, undefined)
	EXISTSMARK = structcompat.EXISTSMARK // Value exists (not undefined)
)

// MakeRunner creates a runner function that can be used to run tests.
var MakeRunner = structcompat.MakeRunner
