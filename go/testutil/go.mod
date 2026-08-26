// The test harness is its own module so that the library's own build stays
// independent of it. `go build ./...` in the parent module skips a nested
// module, so voxgigstruct compiles with no omni at all - and, more to the
// point, `go mod tidy` there cannot quietly add voxgig/omni to the published
// module's dependency graph.
//
// omni is taken from its release tag rather than a sibling checkout. Go
// requires the `go/` prefix for a module in a subdirectory, so the tag is
// `go/v0.1.0` and the version Go records is v0.1.0. That means no
// $OMNI_HOME, no go.work, and a go.sum entry the checksum database backs -
// what a checkout could never give. The parent module still names nothing.
module github.com/voxgig/struct/go/testutil

go 1.23

require (
	github.com/voxgig/omni/go v0.1.0
	github.com/voxgig/struct/go v0.0.0
)

// The library under test is the parent directory, not a published version.
replace github.com/voxgig/struct/go => ../
