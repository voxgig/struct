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

var MakeRunner = structcompat.MakeRunner
