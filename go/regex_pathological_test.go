// RUN: go test -run=TestRegexPathological -v
//
// Discovery test: pathological regex inputs run against the port's Re* API.
// Goal is to surface failures across ports, not to assert behaviour.
// Panel is the same in every port (see REGEX.md).

package voxgigstruct_test

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"

	voxgigstruct "github.com/voxgig/struct/go"
)

func record(label string, fn func() any) {
	t0 := time.Now()
	var outcome string
	func() {
		defer func() {
			if r := recover(); r != nil {
				outcome = fmt.Sprintf("ERR | panic: %v", r)
			}
		}()
		r := fn()
		b, err := json.Marshal(r)
		if err != nil {
			outcome = fmt.Sprintf("OK | <unjsonable %T>: %v", r, r)
			return
		}
		outcome = fmt.Sprintf("OK | %s", string(b))
	}()
	ms := float64(time.Since(t0).Microseconds()) / 1000.0
	fmt.Printf("[regex-discovery] %s | %.2fms | %s\n", label, ms, outcome)
}

func TestRegexPathological(t *testing.T) {
	a22 := strings.Repeat("a", 22)
	nest40 := strings.Repeat("(", 40) + "a" + strings.Repeat(")", 40)

	record("P1_redos_nested_plus", func() any { return voxgigstruct.ReTest("^(a+)+$", a22+"!") })
	record("P2_redos_alt_overlap", func() any { return voxgigstruct.ReTest("^(a|aa)+$", a22+"!") })
	record("P3_empty_repeat_replace", func() any { return voxgigstruct.ReReplace("a*", "abc", "X") })
	record("P4_unicode_replace_dot", func() any { return voxgigstruct.ReReplace(`\.`, "café.au.lait", "/") })
	record("P5_unicode_find_codepoint", func() any { return voxgigstruct.ReFind("é", "café au lait") })
	record("P6_deep_nesting_compile", func() any { return voxgigstruct.ReTest(nest40, "a") })
	record("P7_big_bounded_quantifier", func() any { return voxgigstruct.ReTest("^a{0,10000}b$", strings.Repeat("a", 10)+"b") })
	record("P8_invalid_pattern", func() any { return voxgigstruct.ReCompile("[abc") != nil })
	record("P9_backref_re2_forbidden", func() any { return voxgigstruct.ReTest(`^(a+)\1$`, "aaaa") })
	record("P10_find_all_zero_width", func() any { return voxgigstruct.ReFindAll("a*", "bbb") })
}
