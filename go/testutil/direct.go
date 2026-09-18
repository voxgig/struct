package runner

import (
	"fmt"

	voxgigstruct "github.com/voxgig/struct/go"
)

// Direct is a direct testing helper for validation functions
// Similar to the direct.ts TypeScript file, it provides a way to test validation directly
func DirectTest() {
	var out any

	// Direct testing code ported from direct.ts

	// This is the only uncommented test from direct.ts
	errs := voxgigstruct.ListRefCreate[any]()
	out, _ = voxgigstruct.Validate(
		map[string]any{
			// kind: undefined
		},
		map[string]any{
			"resform": []any{"`$ONE`", "`$OBJECT`"},
		},
		&voxgigstruct.Injection{Errs: errs})
	fmt.Println("OUT", out, errs.List)
}

// Run runs the direct tests
func Run() {
	DirectTest()
}
