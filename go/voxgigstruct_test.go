
// RUN: go test
// RUN-SOME: go test -v -run=TestStruct/getpath


package voxgigstruct_test

import (
	"fmt"
	"math"
	"reflect"
	"strings"
	"testing"

	"github.com/voxgig/struct/go"
	"github.com/voxgig/struct/go/testutil"
)


// NOTE: tests are in order of increasing dependence.
func TestStruct(t *testing.T) {

	store := make(map[string]any)
	
	// Create an SDK client for the runner
	sdk, err := runner.TestSDK(nil)
	if err != nil {
		t.Fatalf("Failed to create SDK: %v", err)
	}

	runnerFunc := runner.MakeRunner("../build/test/test.json", sdk)
	runnerMap, err := runnerFunc("struct", store)
	if err != nil {
		t.Fatalf("Failed to create runner struct: %v", err)
	}

	var spec map[string]any = runnerMap.Spec
	var runset runner.RunSet = runnerMap.RunSet
	var runsetFlags runner.RunSetFlags = runnerMap.RunSetFlags

	var minorSpec     = spec["minor"].(map[string]any)
	var walkSpec      = spec["walk"].(map[string]any)
	var mergeSpec     = spec["merge"].(map[string]any)
	var getpathSpec   = spec["getpath"].(map[string]any)
	var injectSpec    = spec["inject"].(map[string]any)
	var transformSpec = spec["transform"].(map[string]any)
	var validateSpec  = spec["validate"].(map[string]any)
	var selectSpec    = spec["select"].(map[string]any)

  
	// minor tests
	// ===========

	t.Run("minor-exists", func(t *testing.T) {
		checks := map[string]any{
			"clone":   voxgigstruct.Clone,
			"delprop": voxgigstruct.DelProp,
			"escre":   voxgigstruct.EscRe,
			"escurl":  voxgigstruct.EscUrl,
			"getelem": voxgigstruct.GetElem,
			"getprop": voxgigstruct.GetProp,

			"getpath":  voxgigstruct.GetPath,
			"haskey":   voxgigstruct.HasKey,
			"inject":   voxgigstruct.Inject,
			"isempty":  voxgigstruct.IsEmpty,
			"isfunc":   voxgigstruct.IsFunc,

			"iskey":   voxgigstruct.IsKey,
			"islist":  voxgigstruct.IsList,
			"ismap":   voxgigstruct.IsMap,
			"isnode":  voxgigstruct.IsNode,
			"items":   voxgigstruct.Items,

			"joinurl":   voxgigstruct.JoinUrl,
			"jsonify":   voxgigstruct.Jsonify,
			"keysof":    voxgigstruct.KeysOf,
			"merge":     voxgigstruct.Merge,
			"pad":       voxgigstruct.Pad,
			"pathify":   voxgigstruct.Pathify,

			"select":    voxgigstruct.Select,
			"setpath":   voxgigstruct.SetPath,
			"size":      voxgigstruct.Size,
			"slice":     voxgigstruct.Slice,
			"setprop":   voxgigstruct.SetProp,

			"strkey":    voxgigstruct.StrKey,
			"stringify": voxgigstruct.Stringify,
			"transform": voxgigstruct.Transform,
			"typify":    voxgigstruct.Typify,
			"validate":  voxgigstruct.Validate,

			"walk": voxgigstruct.Walk,
		}
		for name, fn := range checks {
			if fnVal := reflect.ValueOf(fn); fnVal.Kind() != reflect.Func {
				t.Errorf("%s should be a function, but got %s", name, fnVal.Kind().String())
			}
		}
	})

  
	t.Run("minor-isnode", func(t *testing.T) {
		runset(t, minorSpec["isnode"], voxgigstruct.IsNode)
	})


  t.Run("minor-ismap", func(t *testing.T) {
		runset(t, minorSpec["ismap"], voxgigstruct.IsMap)
	})

  
	t.Run("minor-islist", func(t *testing.T) {
		runset(t, minorSpec["islist"], voxgigstruct.IsList)
	})

  
	t.Run("minor-iskey", func(t *testing.T) {
		runsetFlags(t, minorSpec["iskey"], map[string]bool{"null": false}, voxgigstruct.IsKey)
	})


	t.Run("minor-strkey", func(t *testing.T) {
		runsetFlags(t, minorSpec["strkey"], map[string]bool{"null": false}, voxgigstruct.StrKey)
	})

  
	t.Run("minor-isempty", func(t *testing.T) {
		runsetFlags(t, minorSpec["isempty"], map[string]bool{"null": false}, voxgigstruct.IsEmpty)
	})

  
	t.Run("minor-isfunc", func(t *testing.T) {
		runset(t, minorSpec["isfunc"], voxgigstruct.IsFunc)

		f0 := func() any {
			return nil
		}

		if !voxgigstruct.IsFunc(f0) {
			t.Errorf("IsFunc failed on function f0")
		}

		if !voxgigstruct.IsFunc(func() any { return nil }) {
			t.Errorf("IsFunc failed on anonymous function")
		}
	})

  
	t.Run("minor-clone", func(t *testing.T) {
		runsetFlags(
			t,
			minorSpec["clone"],
			map[string]bool{"null": false},
			voxgigstruct.Clone,
		)

    f0 := func() any { return nil }
		expected0 := map[string]any{"a":f0}
		result0 := voxgigstruct.Clone(map[string]any{"a":f0})
		if !reflect.DeepEqual(runner.Fdt(expected0), runner.Fdt(result0)) {
			t.Errorf("Expected: %v, Got: %v", expected0, result0)
		}
	})

  
	t.Run("minor-escre", func(t *testing.T) {
		runset(t, minorSpec["escre"], voxgigstruct.EscRe)
	})

  
	t.Run("minor-escurl", func(t *testing.T) {
		runset(t, minorSpec["escurl"], func(in string) string {
			return strings.ReplaceAll(voxgigstruct.EscUrl(fmt.Sprint(in)), "+", "%20")
		})
	})

  
	t.Run("minor-stringify", func(t *testing.T) {
		runset(t, minorSpec["stringify"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]

			if "__NULL__" == val {
				val = "null"
			}

			max, hasMax := m["max"]
			if !hasMax || nil == max {
				return voxgigstruct.Stringify(val)
			} else {
				return voxgigstruct.Stringify(val, int(max.(int)))
			}
		})
	})

  
	t.Run("minor-pathify", func(t *testing.T) {
		runsetFlags(
			t,
			minorSpec["pathify"],
			map[string]bool{"null": true},
			func(v any) any {
				m := v.(map[string]any)
				path := m["path"]
				from, hasFrom := m["from"]

				// NOTE: JSON null is not really nil, so special handling needed since
				// the JSON parser does give us nil for null!
				if "__NULL__" == path {
					path = nil
				}

				pathstr := ""

				if !hasFrom || nil == from {
					pathstr = voxgigstruct.Pathify(path)
				} else {
					pathstr = voxgigstruct.Pathify(path, int(from.(int)))
				}

				if "__NULL__" == m["path"] {
					pathstr = strings.ReplaceAll(pathstr, ">", ":null>")
				}

				pathstr = strings.ReplaceAll(pathstr, "__NULL__.", "")

				return pathstr
			},
		)
	})

  
	t.Run("minor-items", func(t *testing.T) {
		runset(t, minorSpec["items"], voxgigstruct.Items)
	})

  
	t.Run("minor-getprop", func(t *testing.T) {
		runsetFlags(
			t,
			minorSpec["getprop"],
			map[string]bool{"null": false},
			func(v any) any {
				m := v.(map[string]any)
				store := m["val"]
				key := m["key"]
				alt, hasAlt := m["alt"]
				if !hasAlt || alt == nil {
					return voxgigstruct.GetProp(store, key)
				}
				return voxgigstruct.GetProp(store, key, alt)
			},
		)
	})

  
	t.Run("minor-edge-getprop", func(t *testing.T) {
		strarr := []string{"a", "b", "c", "d", "e"}
		expectedA := "c"

		result0 := voxgigstruct.GetProp(strarr, 2)
		if !reflect.DeepEqual(expectedA, result0) {
			t.Errorf("Expected: %v, Got: %v", expectedA, result0)
		}

		result1 := voxgigstruct.GetProp(strarr, "2")
		if !reflect.DeepEqual(expectedA, result1) {
			t.Errorf("Expected: %v, Got: %v", expectedA, result1)
		}

		intarr := []int{2, 3, 5, 7, 11}
		expectedB := 5

		result2 := voxgigstruct.GetProp(intarr, 2)
		if !reflect.DeepEqual(expectedB, result2) {
			t.Errorf("Expected: %v, Got: %v", expectedB, result2)
		}

		result3 := voxgigstruct.GetProp(intarr, "2")
		if !reflect.DeepEqual(expectedB, result3) {
			t.Errorf("Expected: %v, Got: %v", expectedB, result2)
		}
	})

  
	t.Run("minor-setprop", func(t *testing.T) {
		runsetFlags(
			t,
			minorSpec["setprop"],
			map[string]bool{"null": true},
			func(v any) any {
				m := v.(map[string]any)
				parent := m["parent"]
				key := m["key"]
				val := m["val"]
				res := voxgigstruct.SetProp(parent, key, val)
				return res
			})
	})

  
	t.Run("minor-edge-setprop", func(t *testing.T) {
		strarr0 := []string{"a", "b", "c", "d", "e"}
		strarr1 := []string{"a", "b", "c", "d", "e"}

		expected0 := []string{"a", "b", "C", "d", "e"}
		gotstrarr := voxgigstruct.SetProp(strarr0, 2, "C").([]string)
		if !reflect.DeepEqual(gotstrarr, expected0) {
			t.Errorf("Expected: %v, Got: %v", expected0, gotstrarr)
		}

		expected1 := []string{"a", "b", "CC", "d", "e"}
		gotstrarr = voxgigstruct.SetProp(strarr1, "2", "CC").([]string)
		if !reflect.DeepEqual(gotstrarr, expected1) {
			t.Errorf("Expected: %v, Got: %v", expected0, gotstrarr)
		}

		intarr0 := []int{2, 3, 5, 7, 11}
		intarr1 := []int{2, 3, 5, 7, 11}

		expected2 := []int{2, 3, 55, 7, 11}
		gotintarr := voxgigstruct.SetProp(intarr0, 2, 55).([]int)
		if !reflect.DeepEqual(gotintarr, expected2) {
			t.Errorf("Expected: %v, Got: %v", expected2, gotintarr)
		}

		expected3 := []int{2, 3, 555, 7, 11}
		gotintarr = voxgigstruct.SetProp(intarr1, "2", 555).([]int)
		if !reflect.DeepEqual(gotintarr, expected3) {
			t.Errorf("Expected: %v, Got: %v", expected3, gotintarr)
		}
	})

  
	t.Run("minor-haskey", func(t *testing.T) {
		runsetFlags(t, minorSpec["haskey"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			src := m["src"]
			key := m["key"]
			return voxgigstruct.HasKey(src, key)
		})
	})

  
	t.Run("minor-keysof", func(t *testing.T) {
		runset(t, minorSpec["keysof"], voxgigstruct.KeysOf)
	})

  
	t.Run("minor-filter", func(t *testing.T) {
		checkmap := map[string]func([2]any) bool{
			"gt3": func(n [2]any) bool {
				if v, ok := n[1].(int); ok {
					return v > 3
				}
				return false
			},
			"lt3": func(n [2]any) bool {
				if v, ok := n[1].(int); ok {
					return v < 3
				}
				return false
			},
		}
		runset(t, minorSpec["filter"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			checkName := m["check"].(string)
			return voxgigstruct.Filter(val, checkmap[checkName])
		})
	})


	t.Run("minor-flatten", func(t *testing.T) {
		runset(t, minorSpec["flatten"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			depth := m["depth"]
			if depth == nil {
				return voxgigstruct.Flatten(val)
			}
			return voxgigstruct.Flatten(val, int(depth.(int)))
		})
	})


	t.Run("minor-join", func(t *testing.T) {
		runsetFlags(t, minorSpec["join"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			sep := m["sep"]
			urlMode := m["url"]
			arr, ok := val.([]any)
			if !ok {
				arr = []any{}
			}
			return voxgigstruct.Join(arr, sep, urlMode)
		})
	})


	t.Run("minor-typename", func(t *testing.T) {
		runset(t, minorSpec["typename"], voxgigstruct.Typename)
	})


	t.Run("minor-typify", func(t *testing.T) {
		runsetFlags(t, minorSpec["typify"], map[string]bool{"null": false}, voxgigstruct.Typify)
	})


	t.Run("minor-size", func(t *testing.T) {
		runsetFlags(t, minorSpec["size"], map[string]bool{"null": false}, voxgigstruct.Size)
	})


	t.Run("minor-slice", func(t *testing.T) {
		runsetFlags(t, minorSpec["slice"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			start := m["start"]
			end := m["end"]
			return voxgigstruct.Slice(val, start, end)
		})
	})


	t.Run("minor-pad", func(t *testing.T) {
		runsetFlags(t, minorSpec["pad"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			pad := m["pad"]
			char := m["char"]
			return voxgigstruct.Pad(val, pad, char)
		})
	})


	t.Run("minor-getelem", func(t *testing.T) {
		runsetFlags(t, minorSpec["getelem"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			key := m["key"]
			alt, hasAlt := m["alt"]
			if !hasAlt || alt == nil {
				return voxgigstruct.GetElem(val, key)
			}
			return voxgigstruct.GetElem(val, key, alt)
		})
	})


	t.Run("minor-edge-getelem", func(t *testing.T) {
		result := voxgigstruct.GetElem([]any{}, 1, func() int { return 2 })
		if result != 2 {
			t.Errorf("Expected: 2, Got: %v", result)
		}
	})


	t.Run("minor-delprop", func(t *testing.T) {
		runset(t, minorSpec["delprop"], func(v any) any {
			m := v.(map[string]any)
			parent := m["parent"]
			key := m["key"]
			return voxgigstruct.DelProp(parent, key)
		})
	})


	t.Run("minor-edge-delprop", func(t *testing.T) {
		strarr0 := []any{"a", "b", "c", "d", "e"}
		strarr1 := []any{"a", "b", "c", "d", "e"}
		expected0 := []any{"a", "b", "d", "e"}
		result0 := voxgigstruct.DelProp(strarr0, 2)
		if !reflect.DeepEqual(result0, expected0) {
			t.Errorf("Expected: %v, Got: %v", expected0, result0)
		}

		result1 := voxgigstruct.DelProp(strarr1, "2")
		if !reflect.DeepEqual(result1, expected0) {
			t.Errorf("Expected: %v, Got: %v", expected0, result1)
		}

		intarr0 := []any{2, 3, 5, 7, 11}
		intarr1 := []any{2, 3, 5, 7, 11}
		expected1 := []any{2, 3, 7, 11}
		result2 := voxgigstruct.DelProp(intarr0, 2)
		if !reflect.DeepEqual(result2, expected1) {
			t.Errorf("Expected: %v, Got: %v", expected1, result2)
		}

		result3 := voxgigstruct.DelProp(intarr1, "2")
		if !reflect.DeepEqual(result3, expected1) {
			t.Errorf("Expected: %v, Got: %v", expected1, result3)
		}
	})


	t.Run("minor-setpath", func(t *testing.T) {
		runsetFlags(t, minorSpec["setpath"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			store := m["store"]
			path := m["path"]
			val := m["val"]
			return voxgigstruct.SetPath(store, path, val)
		})
	})


	t.Run("minor-edge-setpath", func(t *testing.T) {
		x := map[string]any{"y": map[string]any{"z": 1, "q": 2}}
		result := voxgigstruct.SetPath(x, "y.q", voxgigstruct.DELETE)
		expected := map[string]any{"z": 1}
		if !reflect.DeepEqual(result, expected) {
			t.Errorf("Expected: %v, Got: %v", expected, result)
		}
		expectedX := map[string]any{"y": map[string]any{"z": 1}}
		if !reflect.DeepEqual(x, expectedX) {
			t.Errorf("Expected x: %v, Got: %v", expectedX, x)
		}
	})


	t.Run("minor-jsonify", func(t *testing.T) {
		runsetFlags(t, minorSpec["jsonify"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			if flags, ok := m["flags"].(map[string]any); ok {
				return voxgigstruct.Jsonify(val, flags)
			}
			return voxgigstruct.Jsonify(val)
		})
	})


	t.Run("minor-edge-jsonify", func(t *testing.T) {
		result := voxgigstruct.Jsonify(func() int { return 1 })
		if result != "null" {
			t.Errorf("Expected: null, Got: %v", result)
		}
	})


	t.Run("minor-edge-stringify", func(t *testing.T) {
		a := make(map[string]any)
		a["a"] = a
		result := voxgigstruct.Stringify(a)
		if result != "__STRINGIFY_FAILED__" {
			t.Errorf("Expected: __STRINGIFY_FAILED__, Got: %v", result)
		}
	})


	t.Run("minor-edge-clone", func(t *testing.T) {
		// Functions are preserved (same reference, not deep-cloned).
		f0 := func() int { return 22 }
		src := map[string]any{"a": 1, "f": f0}
		cloned := voxgigstruct.Clone(src).(map[string]any)

		// Plain values are deep cloned.
		if cloned["a"] != 1 {
			t.Errorf("Expected cloned a=1, Got: %v", cloned["a"])
		}

		// Function is same reference.
		clonedF, ok := cloned["f"].(func() int)
		if !ok {
			t.Errorf("Expected cloned f to be a function")
		} else if clonedF() != 22 {
			t.Errorf("Expected cloned f() = 22, Got: %v", clonedF())
		}

		// Modifying clone does not affect original.
		cloned["a"] = 2
		if src["a"] != 1 {
			t.Errorf("Expected original a=1 after clone modification, Got: %v", src["a"])
		}

		// Nested maps are deep cloned (different reference).
		nested := map[string]any{"b": map[string]any{"c": 3}}
		clonedNested := voxgigstruct.Clone(nested).(map[string]any)
		innerClone := clonedNested["b"].(map[string]any)
		innerClone["c"] = 99
		origInner := nested["b"].(map[string]any)
		if origInner["c"] != 3 {
			t.Errorf("Expected original nested c=3 after clone modification, Got: %v", origInner["c"])
		}
	})


	t.Run("minor-edge-typify", func(t *testing.T) {
		// nil → T_scalar | T_null
		tNil := voxgigstruct.Typify(nil)
		expected0 := voxgigstruct.T_scalar | voxgigstruct.T_null
		if tNil != expected0 {
			t.Errorf("Typify(nil): Expected: %v, Got: %v", expected0, tNil)
		}

		// math.NaN → T_noval
		tNaN := voxgigstruct.Typify(math.NaN())
		expected1 := voxgigstruct.T_noval
		if tNaN != expected1 {
			t.Errorf("Typify(NaN): Expected: %v, Got: %v", expected1, tNaN)
		}

		// function → T_scalar | T_function
		tFunc := voxgigstruct.Typify(func() {})
		expected2 := voxgigstruct.T_scalar | voxgigstruct.T_function
		if tFunc != expected2 {
			t.Errorf("Typify(func): Expected: %v, Got: %v", expected2, tFunc)
		}
	})


	// walk tests
	// ==========

	t.Run("walk-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Walk)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("walk should be a function, but got %s", fnVal.Kind().String())
		}
	})

  
	t.Run("walk-log", func(t *testing.T) {
		test := voxgigstruct.Clone(walkSpec["log"]).(map[string]any)

		walklog := func(k *string, v any, p any, t []string) any {
			var ks string
			if nil == k {
				ks = ""
			} else {
				ks = *k
			}
			entry := "k=" + voxgigstruct.Stringify(ks) +
				", v=" + voxgigstruct.Stringify(v) +
				", p=" + voxgigstruct.Stringify(p) +
				", t=" + voxgigstruct.Pathify(t)
			return entry
		}

		outMap := test["out"].(map[string]any)

		// Test after (post-order): Walk(val, nil, walklog)
		var logAfter []any
		walklogAfter := func(k *string, v any, p any, t []string) any {
			entry := walklog(k, v, p, t)
			logAfter = append(logAfter, entry)
			return v
		}
		voxgigstruct.Walk(test["in"], nil, walklogAfter)

		if !reflect.DeepEqual(logAfter, outMap["after"]) {
			t.Errorf("after log mismatch:\n got:  %v\n want: %v\n", logAfter, outMap["after"])
		}

		// Test before (pre-order): Walk(val, walklog)
		var logBefore []any
		walklogBefore := func(k *string, v any, p any, t []string) any {
			entry := walklog(k, v, p, t)
			logBefore = append(logBefore, entry)
			return v
		}
		voxgigstruct.Walk(test["in"], walklogBefore)

		if !reflect.DeepEqual(logBefore, outMap["before"]) {
			t.Errorf("before log mismatch:\n got:  %v\n want: %v\n", logBefore, outMap["before"])
		}

		// Test both: Walk(val, walklog, walklog)
		var logBoth []any
		walklogBoth := func(k *string, v any, p any, t []string) any {
			entry := walklog(k, v, p, t)
			logBoth = append(logBoth, entry)
			return v
		}
		voxgigstruct.Walk(test["in"], walklogBoth, walklogBoth)

		if !reflect.DeepEqual(logBoth, outMap["both"]) {
			t.Errorf("both log mismatch:\n got:  %v\n want: %v\n", logBoth, outMap["both"])
		}
	})


	t.Run("walk-basic", func(t *testing.T) {
		walkpath := func(k *string, val any, parent any, path []string) any {
			if str, ok := val.(string); ok {
				return str + "~" + strings.Join(path, ".")
			}
			return val
		}

		runset(t, walkSpec["basic"], func(v any) any {
			if "__NULL__" == v {
				v = nil
			}
			return voxgigstruct.Walk(v, walkpath)
		})
	})


	t.Run("walk-depth", func(t *testing.T) {
		runsetFlags(t, walkSpec["depth"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			src := m["src"]
			maxdepth := m["maxdepth"]

			var top any
			var cur any

			copy := func(key *string, val any, _parent any, _path []string) any {
				if voxgigstruct.IsNode(val) {
					var child any
					if voxgigstruct.IsList(val) {
						child = []any{}
					} else {
						child = map[string]any{}
					}
					if nil == key {
						top = child
						cur = child
					} else {
						voxgigstruct.SetProp(cur, *key, child)
						cur = child
					}
				} else if nil != key {
					voxgigstruct.SetProp(cur, *key, val)
				}
				return val
			}

			if maxdepth == nil {
				voxgigstruct.Walk(src, copy)
			} else {
				md := int(maxdepth.(int))
				voxgigstruct.Walk(src, copy, nil, md)
			}
			return top
		})
	})


	t.Run("walk-copy", func(t *testing.T) {
		runset(t, walkSpec["copy"], func(v any) any {
			var cur []any
			// Track parent keys to re-link after SetProp returns new slices
			var keys []string

			walkcopy := func(key *string, val any, _parent any, path []string) any {
				if nil == key {
					cur = make([]any, 33)
					keys = make([]string, 33)
					if voxgigstruct.IsMap(val) {
						cur[0] = map[string]any{}
					} else if voxgigstruct.IsList(val) {
						cur[0] = []any{}
					} else {
						cur[0] = val
					}
					return val
				}

				v := val
				i := voxgigstruct.Size(path)
				keys[i] = *key

				if voxgigstruct.IsNode(v) {
					if voxgigstruct.IsMap(v) {
						cur[i] = map[string]any{}
					} else {
						cur[i] = []any{}
					}
					v = cur[i]
				}

				cur[i-1] = voxgigstruct.SetProp(cur[i-1], *key, v)

				// Re-link parent chain up for slice reference stability
				for j := i - 1; j > 0; j-- {
					cur[j-1] = voxgigstruct.SetProp(cur[j-1], keys[j], cur[j])
				}

				return val
			}

			voxgigstruct.Walk(v, walkcopy)
			return cur[0]
		})
	})

  
	// merge tests
	// ===========

	t.Run("merge-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Merge)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("merge should be a function, but got %s", fnVal.Kind().String())
		}
	})

  
	t.Run("merge-basic", func(t *testing.T) {
		test := mergeSpec["basic"].(map[string]any)
		inVal := test["in"]
		outVal := test["out"]
		result := voxgigstruct.Merge(inVal)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

  
	t.Run("merge-cases", func(t *testing.T) {
		runset(t, mergeSpec["cases"], func(v any) any {
			return voxgigstruct.Merge(v)
		})
	})


	t.Run("merge-array", func(t *testing.T) {
		runset(t, mergeSpec["array"], func(v any) any {
			return voxgigstruct.Merge(v)
		})
	})

	t.Run("merge-integrity", func(t *testing.T) {
		runset(t, mergeSpec["integrity"], func(v any) any {
			return voxgigstruct.Merge(v)
		})
	})

  
	t.Run("merge-special", func(t *testing.T) {
		f0 := func() int { return 11 }
		
		result0 := voxgigstruct.Merge([]any{f0})
    var fr0 = result0.(func() int)

    if f0() != fr0() {
			t.Errorf("Expected same function reference (A)")
		}
		
		result1 := voxgigstruct.Merge([]any{nil, f0})
    var fr1 = result1.(func() int)
		if f0() != fr1() {
			t.Errorf("Expected same function reference (B)")
		}
		
		result2 := voxgigstruct.Merge([]any{map[string]any{"a": f0}}).(map[string]any)
    var fr2 = result2["a"].(func() int)
		if f0() != fr2() {
			t.Errorf("Expected object with function reference")
		}

		result3 := voxgigstruct.Merge([]any{[]any{f0}}).([]any)
    var fr3 = result3[0].(func() int)
		if f0() != fr3() {
			t.Errorf("Expected array with function reference")
		}
    
		result4 := voxgigstruct.Merge([]any{map[string]any{"a": map[string]any{"b": f0}}})
    var b = result4.(map[string]any)["a"].(map[string]any)
    var fr4 = b["b"].(func() int)

		if f0() != fr4() {
			t.Errorf("Expected deep object with function reference")
		}
	})


	t.Run("merge-depth", func(t *testing.T) {
		runset(t, mergeSpec["depth"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			depth := m["depth"]
			if depth == nil {
				return voxgigstruct.Merge(val)
			}
			return voxgigstruct.Merge(val, int(depth.(int)))
		})
	})


	// getpath tests
	// =============

	t.Run("getpath-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.GetPath)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("getpath should be a function, but got %s", fnVal.Kind().String())
		}
	})

  
	t.Run("getpath-basic", func(t *testing.T) {
		runset(t, getpathSpec["basic"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			store := m["store"]

			return voxgigstruct.GetPath(store, path)
		})
	})


	t.Run("getpath-relative", func(t *testing.T) {
		runset(t, getpathSpec["relative"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			store := m["store"]
			dparent := m["dparent"]

			dpathStr, _ := m["dpath"].(string)
			var dpath []string
			if dpathStr != "" {
				dpath = strings.Split(dpathStr, ".")
			}

			inj := &voxgigstruct.Injection{
				Dparent: dparent,
				Dpath:   dpath,
			}

			return voxgigstruct.GetPath(store, path, inj)
		})
	})


	t.Run("getpath-special", func(t *testing.T) {
		runset(t, getpathSpec["special"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			store := m["store"]
			inj := m["inj"]

			if inj != nil {
				injMap, _ := inj.(map[string]any)
				inj := &voxgigstruct.Injection{}
				if key, ok := injMap["key"]; ok {
					inj.Key = fmt.Sprint(key)
				}
				if meta, ok := injMap["meta"]; ok {
					if metaMap, ok := meta.(map[string]any); ok {
						inj.Meta = metaMap
					}
				}
				return voxgigstruct.GetPath(store, path, inj)
			}

			return voxgigstruct.GetPath(store, path)
		})
	})

  
	// inject tests
	// ============

	t.Run("inject-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Inject)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("inject should be a function, but got %s", fnVal.Kind().String())
		}
	})

  
	t.Run("inject-basic", func(t *testing.T) {
		subtest := injectSpec["basic"].(map[string]any)
		inVal := subtest["in"].(map[string]any)
		val, store := inVal["val"], inVal["store"]
		outVal := subtest["out"]
		result := voxgigstruct.Inject(val, store)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})


	t.Run("inject-string", func(t *testing.T) {
		runset(t, injectSpec["string"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			store := m["store"]

			return voxgigstruct.Inject(val, store, &voxgigstruct.Injection{Modify: runner.NullModifier})
		})
	})

  
	t.Run("inject-deep", func(t *testing.T) {
		runset(t, injectSpec["deep"], func(v any) any {
			m := v.(map[string]any)
			val := m["val"]
			store := m["store"]
			return voxgigstruct.Inject(val, store)
		})
	})

  
	// transform tests
	// ===============

	t.Run("transform-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Transform)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("transform should be a function, but got %s", fnVal.Kind().String())
		}
	})

  
	t.Run("transform-basic", func(t *testing.T) {
		subtest := transformSpec["basic"].(map[string]any)
		inVal := subtest["in"].(map[string]any)
		data := inVal["data"]
		spec := inVal["spec"]
		outVal := subtest["out"]
		result := voxgigstruct.Transform(data, spec)
		if !reflect.DeepEqual(result, outVal) {
			t.Errorf("Expected: %v, Got: %v", outVal, result)
		}
	})

  
	t.Run("transform-paths", func(t *testing.T) {
		runset(t, transformSpec["paths"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

  
	t.Run("transform-cmds", func(t *testing.T) {
		runset(t, transformSpec["cmds"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

  
	t.Run("transform-each", func(t *testing.T) {
		runset(t, transformSpec["each"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

  
	t.Run("transform-pack", func(t *testing.T) {
		runset(t, transformSpec["pack"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})

  
	// NOTE: transform-ref has some edge case failures in $REF handling
	// (cyclic refs, nested self-refs). Kept as opt-in for now.
	t.Run("transform-ref", func(t *testing.T) {
		runset(t, transformSpec["ref"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})


	t.Run("transform-format", func(t *testing.T) {
		runsetFlags(t, transformSpec["format"], map[string]bool{"null": false}, func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Transform(data, spec)
		})
	})


	t.Run("transform-apply", func(t *testing.T) {
		runset(t, transformSpec["apply"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			result, errs := voxgigstruct.TransformCollect(data, spec)
			if len(errs) > 0 {
				return result, fmt.Errorf("%s", errs[0])
			}
			return result, nil
		})
	})

	t.Run("transform-edge-apply", func(t *testing.T) {
		result := voxgigstruct.Transform(
			map[string]any{},
			[]any{"`$APPLY`", func(v any) any { return 1 + v.(int) }, 1},
		)
		if result != 2 {
			t.Errorf("Expected: 2, Got: %v", result)
		}
	})


	t.Run("transform-modify", func(t *testing.T) {
		runset(t, transformSpec["modify"], func(v any) any {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.TransformModify(data, spec, nil, func(
				val any,
				key any,
				parent any,
				inj *voxgigstruct.Injection,
				store any,
			) {
				if key != nil && parent != nil {
					if strval, ok := val.(string); ok {
						newVal := "@" + strval
						if pm, isMap := parent.(map[string]any); isMap {
							pm[fmt.Sprint(key)] = newVal
						}
					}
				}
			})
		})
	})

  
	t.Run("transform-extra", func(t *testing.T) {
		data := map[string]any{"a": 1}
		spec := map[string]any{
			"x": "`a`",
			"b": "`$COPY`",
			"c": "`$UPPER`",
		}

		upper := voxgigstruct.Injector(func(
			s *voxgigstruct.Injection,
			val any,
			ref *string,
			store any,
		) any {
			p := s.Path
			if len(p.List) == 0 {
				return ""
			}
			last := p.List[len(p.List)-1]
			// uppercase the last letter
			if len(last) > 0 {
				return string(last[0]-32) + last[1:]
			}

			return last
		})

		extra := map[string]any{
			"b":      2,
			"$UPPER": upper,
		}

		output := map[string]any{
			"x": 1,
			"b": 2,
			"c": "C",
		}

		result := voxgigstruct.TransformModify(data, spec, extra, nil)
		if !reflect.DeepEqual(result, output) {
			t.Errorf("Expected: %s, \nGot: %s \nExpected JSON: %s \nGot JSON: %s",
				runner.Fdt(output),
        runner.Fdt(result),
        runner.ToJSONString(output),
        runner.ToJSONString(result),
      )
		}
	})


	t.Run("transform-funcval", func(t *testing.T) {
    f0 := func() int { return 22 }
		
		result1 := voxgigstruct.Transform(map[string]any{}, map[string]any{"x": 1})
		expected1 := map[string]any{"x": 1}
		if !reflect.DeepEqual(expected1, result1) {
			t.Errorf("Expected simple value transform result")
		}
		
		result2 := voxgigstruct.Transform(map[string]any{}, map[string]any{"x": f0})
    var fr0 = result2.(map[string]any)["x"].(func() int) 
    if f0() != fr0() {
      t.Errorf("Expected x to be f0")
		}
		
    result3 := voxgigstruct.Transform(map[string]any{"a": 1}, map[string]any{"x": "`a`"})
    expected3 := map[string]any{"x": 1}
    if !reflect.DeepEqual(expected3, result3) {
	 		t.Errorf("Expected value lookup transform to work")
    }
		
    result4 := voxgigstruct.Transform(map[string]any{"f0": f0}, map[string]any{"x": "`f0`"})
    var fr4 = result4.(map[string]any)["x"].(func() int)
    if 22 != fr4() {
	 		t.Errorf("Expected function to be preserved")
    }
	})

  
	// validate tests
	// ===============

	t.Run("validate-exists", func(t *testing.T) {
		fnVal := reflect.ValueOf(voxgigstruct.Validate)
		if fnVal.Kind() != reflect.Func {
			t.Errorf("validate should be a function, but got %s", fnVal.Kind().String())
		}
	})

  
	t.Run("validate-basic", func(t *testing.T) {
		runsetFlags(t, validateSpec["basic"], map[string]bool{"null": false}, func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Validate(data, spec)
		})
	})

  
	t.Run("validate-child", func(t *testing.T) {
		runset(t, validateSpec["child"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			out, err := voxgigstruct.Validate(data, spec)

			// Return both the output and error so the test framework can handle error checking
			return out, err
		})
	})


	t.Run("validate-one", func(t *testing.T) {
		runset(t, validateSpec["one"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Validate(data, spec)
		})
	})


	t.Run("validate-exact", func(t *testing.T) {
		runset(t, validateSpec["exact"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]
			return voxgigstruct.Validate(data, spec)
		})
	})


	t.Run("validate-invalid", func(t *testing.T) {
		runsetFlags(t, validateSpec["invalid"], map[string]bool{"null": false}, func(v any) (any, error) {
			m := v.(map[string]any)
			return voxgigstruct.Validate(m["data"], m["spec"])
		})
	})

  
	t.Run("validate-special", func(t *testing.T) {
		runset(t, validateSpec["special"], func(v any) (any, error) {
			m := v.(map[string]any)
			data := m["data"]
			spec := m["spec"]

			if inj, ok := m["inj"]; ok && inj != nil {
				injMap := inj.(map[string]any)
				extra := make(map[string]any)

				if meta, ok := injMap["meta"]; ok {
					extra["meta"] = meta
				}

				// Pass nil for collecterrs so errors are returned, not collected.
				return voxgigstruct.Validate(data, spec, &voxgigstruct.Injection{Extra: extra})
			}

			return voxgigstruct.Validate(data, spec)
		})
	})


	t.Run("validate-custom", func(t *testing.T) {
		errs := voxgigstruct.ListRefCreate[any]() // make([]any,0)

		integerCheck := voxgigstruct.Injector(func(
			inj *voxgigstruct.Injection,
			val any,
			ref *string,
			store any,
		) any {
			out := voxgigstruct.GetProp(inj.Dparent, inj.Key)
      
      switch x := out.(type) {
			case int:
				return x
			default:
				msg := fmt.Sprintf("Not an integer at %s: %v",
					voxgigstruct.Pathify(inj.Path.List, 1), out)
				inj.Errs.Append(msg)
				return nil
			}
		})

		extra := map[string]any{
			"$INTEGER": integerCheck,
		}

		shape := map[string]any{
			"a": "`$INTEGER`",
		}

		out, err := voxgigstruct.Validate(
			map[string]any{"a": 1},
			shape,
			&voxgigstruct.Injection{Extra: extra, Errs: errs},
		)
		if nil != err {
			t.Error(err)
		}

		expected0 := map[string]any{"a": 1}
		if !reflect.DeepEqual(out, expected0) {
			t.Errorf("Expected: %v, Got: %v", expected0, out)
		}
		errs0 := []any{}
		if !reflect.DeepEqual(errs.List, errs0) {
			t.Errorf("Expected Error: %v, Got: %v", errs0, errs.List)
		}

		out, err = voxgigstruct.Validate(
			map[string]any{"a": "A"},
			shape,
			&voxgigstruct.Injection{Extra: extra, Errs: errs},
		)
		if nil != err {
			t.Error(err)
		}
    
		expected1 := map[string]any{"a": "A"}
		if !reflect.DeepEqual(out, expected1) {
			t.Errorf("Expected: %v, Got: %v", expected1, out)
		}

		errs1 := []any{"Not an integer at a: A"}
		if !reflect.DeepEqual(errs.List, errs1) {
			t.Errorf("Expected Error: %v, Got: %v", errs1, errs.List)
		}

	})


	t.Run("validate-edge", func(t *testing.T) {
		// $INSTANCE validator should fail for integer, map, and list values.
		spec := map[string]any{"x": "`$INSTANCE`"}

		// Integer should fail $INSTANCE.
		out0, err0 := voxgigstruct.Validate(map[string]any{"x": 1}, spec)
		if err0 == nil {
			t.Errorf("Expected error for $INSTANCE with integer, Got: %v", out0)
		}
		if err0 != nil && !strings.Contains(err0.Error(), "instance") {
			t.Errorf("Expected instance error message, Got: %v", err0.Error())
		}

		// Map should fail $INSTANCE.
		out1, err1 := voxgigstruct.Validate(map[string]any{"x": map[string]any{"a": 1}}, spec)
		if err1 == nil {
			t.Errorf("Expected error for $INSTANCE with map, Got: %v", out1)
		}
		if err1 != nil && !strings.Contains(err1.Error(), "instance") {
			t.Errorf("Expected instance error message, Got: %v", err1.Error())
		}

		// List should fail $INSTANCE.
		out2, err2 := voxgigstruct.Validate(map[string]any{"x": []any{1, 2}}, spec)
		if err2 == nil {
			t.Errorf("Expected error for $INSTANCE with list, Got: %v", out2)
		}
		if err2 != nil && !strings.Contains(err2.Error(), "instance") {
			t.Errorf("Expected instance error message, Got: %v", err2.Error())
		}
	})


	// select tests
	// ============

	t.Run("select-basic", func(t *testing.T) {
		runset(t, selectSpec["basic"], func(v any) any {
			m := v.(map[string]any)
			obj := m["obj"]
			query := m["query"]
			return voxgigstruct.Select(obj, query)
		})
	})


	t.Run("select-operators", func(t *testing.T) {
		runset(t, selectSpec["operators"], func(v any) any {
			m := v.(map[string]any)
			obj := m["obj"]
			query := m["query"]
			return voxgigstruct.Select(obj, query)
		})
	})


	t.Run("select-edge", func(t *testing.T) {
		runset(t, selectSpec["edge"], func(v any) any {
			m := v.(map[string]any)
			obj := m["obj"]
			query := m["query"]
			return voxgigstruct.Select(obj, query)
		})
	})


	t.Run("select-alts", func(t *testing.T) {
		runset(t, selectSpec["alts"], func(v any) any {
			m := v.(map[string]any)
			obj := m["obj"]
			query := m["query"]
			return voxgigstruct.Select(obj, query)
		})
	})


	// JSON Builder
	// ============

	t.Run("json-builder", func(t *testing.T) {
		expected0 := "{\n  \"a\": 1\n}"
		result0 := voxgigstruct.Jsonify(voxgigstruct.Jo("a", 1))
		if result0 != expected0 {
			t.Errorf("Expected: %v, Got: %v", expected0, result0)
		}

		expected1 := "[\n  \"b\",\n  2\n]"
		result1 := voxgigstruct.Jsonify(voxgigstruct.Ja("b", 2))
		if result1 != expected1 {
			t.Errorf("Expected: %v, Got: %v", expected1, result1)
		}

		expected2 := "{\n  \"c\": \"C\",\n  \"d\": {\n    \"x\": true\n  },\n  \"e\": [\n    null,\n    false\n  ]\n}"
		result2 := voxgigstruct.Jsonify(voxgigstruct.Jo(
			"c", "C",
			"d", voxgigstruct.Jo("x", true),
			"e", voxgigstruct.Ja(nil, false),
		))
		if result2 != expected2 {
			t.Errorf("Expected:\n%v\nGot:\n%v", expected2, result2)
		}
	})


	// getpath-handler test
	// ====================

	t.Run("getpath-handler", func(t *testing.T) {
		runset(t, getpathSpec["handler"], func(v any) any {
			m := v.(map[string]any)
			path := m["path"]
			innerStore := m["store"]

			store := map[string]any{
				"$TOP": innerStore,
				"$FOO": func() string { return "foo" },
			}

			inj := &voxgigstruct.Injection{
				Handler: func(
					s *voxgigstruct.Injection,
					val any,
					ref *string,
					st any,
				) any {
					if fn, ok := val.(func() string); ok {
						return fn()
					}
					return val
				},
			}

			return voxgigstruct.GetPath(store, path, inj)
		})
	})
}


func IsSameFunc(target any, candidate any) bool {
	if reflect.TypeOf(target).Kind() != reflect.Func || reflect.TypeOf(candidate).Kind() != reflect.Func {
		return false
	}

	return reflect.ValueOf(target).Pointer() == reflect.ValueOf(candidate).Pointer()
}
