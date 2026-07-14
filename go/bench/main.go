// Performance bench for the Go port. Emits one JSON line per
// build/bench/README.md; diagnostics go to stderr.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"time"

	vs "github.com/voxgig/struct/go"
)

func envi(k string, d int) int {
	if v, err := strconv.Atoi(os.Getenv(k)); err == nil {
		return v
	}
	return d
}

func build(w, d, leaf int) any {
	if d == 0 {
		return leaf
	}
	m := map[string]any{}
	for i := 0; i < w; i++ {
		m["k"+strconv.Itoa(i)] = build(w, d-1, leaf)
	}
	return m
}

func nodecount(w, d int) int {
	n, p := 0, 1
	for i := 0; i <= d; i++ {
		n += p
		p *= w
	}
	return n
}

var sink int

type opResult struct {
	Op        string  `json:"op"`
	Runs      int     `json:"runs"`
	UnitCount int     `json:"unit_count"`
	MinMs     float64 `json:"min_ms"`
	MedianMs  float64 `json:"median_ms"`
	MeanMs    float64 `json:"mean_ms"`
}

func measure(op string, uc, warm, runs int, fn func()) opResult {
	for i := 0; i < warm; i++ {
		fn()
	}
	t := make([]float64, 0, runs)
	for r := 0; r < runs; r++ {
		a := time.Now()
		fn()
		t = append(t, float64(time.Since(a).Nanoseconds())/1e6)
	}
	sort.Float64s(t)
	s := 0.0
	for _, x := range t {
		s += x
	}
	return opResult{op, runs, uc, t[0], t[len(t)/2], s / float64(len(t))}
}

func main() {
	W := envi("BENCH_WIDTH", 5)
	D := envi("BENCH_DEPTH", 6)
	WARM := envi("BENCH_WARMUP", 3)
	RUNS := envi("BENCH_RUNS", 21)
	GP := envi("BENCH_GETPATH_ITERS", 2000)

	tree := build(W, D, 0)
	nodes := nodecount(W, D)
	treeA := build(W, D, 1)
	treeB := build(W, D, 2)
	segs := make([]string, D)
	for i := range segs {
		segs[i] = "k0"
	}
	path := strings.Join(segs, ".")

	cb := func(key *string, val any, parent any, p []string) any {
		sink += len(p)
		return val
	}

	ops := []opResult{
		measure("clone", nodes, WARM, RUNS, func() {
			if vs.Clone(tree) != nil {
				sink++
			}
		}),
		measure("walk", nodes, WARM, RUNS, func() { vs.Walk(tree, cb) }),
		measure("merge", nodes, WARM, RUNS, func() {
			if vs.Merge([]any{treeA, treeB}) != nil {
				sink++
			}
		}),
		measure("stringify", nodes, WARM, RUNS, func() {
			sink += len(vs.Stringify(tree))
		}),
		measure("getpath", GP, WARM, RUNS, func() {
			s := 0
			for i := 0; i < GP; i++ {
				if vs.GetPath(tree, path) != nil {
					s++
				}
			}
			sink += s
		}),
	}

	fmt.Fprintf(os.Stderr, "go: sink=%d\n", sink)
	out := map[string]any{
		"lang":    "go",
		"runtime": "go " + strings.TrimPrefix(runtime.Version(), "go"),
		"nodes":   nodes,
		"params": map[string]int{"width": W, "depth": D, "warmup": WARM,
			"runs": RUNS, "getpath_iters": GP},
		"ops": ops,
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}
