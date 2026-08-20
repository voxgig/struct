// The test harness is its own module so that the library's own build stays
// independent of it. `go build ./...` in the parent module skips a nested
// module, so voxgigstruct compiles with no sibling omni checkout and no
// workspace - and, more to the point, `go mod tidy` there cannot quietly
// add voxgig/omni to the published module's dependency graph.
//
// Neither require below is ever resolved from a proxy: the go.work written
// by the parent Makefile supplies both from local checkouts.
module github.com/voxgig/struct/go/testutil

go 1.23

require (
	github.com/voxgig/omni/go v0.0.0
	github.com/voxgig/struct/go v0.0.0
)
