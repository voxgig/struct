// The shared test runner comes from voxgig/omni, consumed as a local
// checkout - omni is deliberately not published to a module proxy (yet).
//
// Go resolves it through a workspace rather than a `require`: `make test`
// writes a gitignored go.work pointing at the sibling checkout ($OMNI_HOME
// first, then sibling paths), so go.mod stays free of paths that only work
// on one machine. Nothing the library ships imports omni - only this test
// package does, and `go build ./...` of voxgigstruct itself is unaffected.
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
