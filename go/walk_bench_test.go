package voxgigstruct_test

import (
	"strconv"
	"testing"

	voxgigstruct "github.com/voxgig/struct/go"
)

// buildTree builds a balanced map tree of given width and depth.
// Each internal node has `width` map children keyed "k0".."k{width-1}".
// Leaves are integer values at the specified depth.
func buildTree(width, depth int) any {
	if depth <= 0 {
		return 1
	}
	m := make(map[string]any, width)
	for i := 0; i < width; i++ {
		m["k"+strconv.Itoa(i)] = buildTree(width, depth-1)
	}
	return m
}

func benchmarkWalk(b *testing.B, width, depth int) {
	tree := buildTree(width, depth)
	noop := func(_ *string, v any, _ any, _ []string) any { return v }
	b.ResetTimer()
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		voxgigstruct.Walk(tree, noop)
	}
}

// BenchmarkWalkWideDeep: wide+deep w=8 d=6 (~8^6 = 262144 leaves).
func BenchmarkWalkWideDeep(b *testing.B) { benchmarkWalk(b, 8, 6) }

// BenchmarkWalkVeryWide: very-wide w=1000 d=2 (~1e6 leaves, shallow).
func BenchmarkWalkVeryWide(b *testing.B) { benchmarkWalk(b, 1000, 2) }

// BenchmarkWalkVeryDeep: very-deep w=2 d=20 (~2^20 = 1048576 leaves).
func BenchmarkWalkVeryDeep(b *testing.B) { benchmarkWalk(b, 2, 20) }
