// Smoke test for the Go test-provider port. Loads the default corpus and
// prints summary numbers to verify parity with the canonical TS reference.
package main

import (
	"fmt"
	"strings"

	provider "voxgig/structproto"
)

func main() {
	p, err := provider.Load("")
	if err != nil {
		panic(err)
	}

	fns := p.Functions()
	fmt.Println("functions:", strings.Join(fns, ", "))

	total := 0
	expectKinds := map[string]int{}
	inputKinds := map[string]int{}
	for _, fn := range fns {
		for _, e := range p.Entries(fn) {
			total++
			expectKinds[e.Expect.Kind]++
			inputKinds[e.Input.Kind]++
		}
	}

	fmt.Println("total entries:", total)
	fmt.Printf("expect kinds: value=%d, absent=%d, match=%d, error=%d\n",
		expectKinds["value"], expectKinds["absent"], expectKinds["match"], expectKinds["error"])
	fmt.Printf("input kinds: in=%d, args=%d, ctx=%d\n",
		inputKinds["in"], inputKinds["args"], inputKinds["ctx"])

	gp := p.Entries("getpath", "basic")
	if len(gp) > 0 {
		e := gp[0]
		id := "<nil>"
		if e.ID != nil {
			id = *e.ID
		}
		fmt.Printf("getpath/basic[0]: id=%s, doc=%v, input.kind=%s, expect.kind=%s, expect.value=%v\n",
			id, e.Doc, e.Input.Kind, e.Expect.Kind, e.Expect.Value)
	}
}
