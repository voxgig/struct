/* Copyright (c) 2025 Voxgig Ltd. MIT LICENSE. */

/* Voxgig Struct
 * =============
 *
 * Utility functions to manipulate in-memory JSON-like data
 * structures. These structures assumed to be composed of nested
 * "nodes", where a node is a list or map, and has named or indexed
 * fields.  The general design principle is "by-example". Transform
 * specifications mirror the desired output.  This implementation is
 * designed for porting to multiple language, and to be tolerant of
 * undefined values.
 *
 * Main utilities
 * - getpath: get the value at a key path deep inside an object.
 * - merge: merge multiple nodes, overriding values in earlier nodes.
 * - walk: walk a node tree, applying a function at each node and leaf.
 * - inject: inject values from a data store into a new data structure.
 * - transform: transform a data structure to an example structure.
 * - validate: valiate a data structure against a shape specification.
 *
 * Minor utilities
 * - isnode, islist, ismap, iskey, isfunc: identify value kinds.
 * - isempty: undefined values, or empty nodes.
 * - keysof: sorted list of node keys (ascending).
 * - haskey: true if key value is defined.
 * - clone: create a copy of a JSON-like data structure.
 * - items: list entries of a map or list as [key, value] pairs.
 * - getprop: safely get a property value by key.
 * - setprop: safely set a property value by key.
 * - stringify: human-friendly string version of a value.
 * - escre: escape a regular expresion string.
 * - escurl: escape a url.
 * - joinurl: join parts of a url, merging forward slashes.
 *
 * This set of functions and supporting utilities is designed to work
 * uniformly across many languages, meaning that some code that may be
 * functionally redundant in specific languages is still retained to
 * keep the code human comparable.
 *
 * NOTE: In this code JSON nulls are in general *not* considered the
 * same as the undefined value in the given language. However most
 * JSON parsers do use the undefined value to represent JSON
 * null. This is ambiguous as JSON null is a separate value, not an
 * undefined value. You should convert such values to a special value
 * to represent JSON null, if this ambiguity creates issues
 * (thankfully in most APIs, JSON nulls are not used). For example,
 * the unit tests use the string "__NULL__" where necessary.
 *
 */

package voxgigstruct

import (
	"encoding/json"
	"fmt"
	"math"
	"math/bits"
	"net/url"
	"reflect"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

const Version = "0.1.0"

// String constants are explicitly defined.

const (
	// Mode value for inject step (bitfield).
	M_KEYPRE  = 1
	M_KEYPOST = 2
	M_VAL     = 4

	// Special keys.
	S_DKEY  = "$KEY"
	S_DMETA = "`$META`"
	S_DTOP  = "$TOP"
	S_DERRS = "$ERRS"

	// General strings.
	S_any      = "any"
	S_noval    = "noval"
	S_array    = "array"
	S_list     = "list"
	S_map      = "map"
	S_boolean  = "boolean"
	S_decimal  = "decimal"
	S_integer  = "integer"
	S_function = "function"
	S_symbol   = "symbol"
	S_instance = "instance"
	S_number   = "number"
	S_object   = "object"
	S_string   = "string"
	S_scalar   = "scalar"
	S_node     = "node"
	S_null     = "null"
	S_key      = "key"
	S_parent   = "parent"
	S_MT       = ""
	S_SP       = " "
	S_BT       = "`"
	S_DS       = "$"
	S_DT       = "."
	S_CN       = ":"
	S_KEY      = "KEY"
	S_base     = "base"
	S_BEXACT   = "`$EXACT`"
	S_BOPEN    = "`$OPEN`"
	S_BKEY     = "`$KEY`"
	S_BANNO    = "`$ANNO`"
	S_BVAL     = "`$VAL`"
	S_DSPEC    = "$SPEC"
	S_VIZ      = ": "
)

// Type bits - using bit positions from 31 downward, matching the TS implementation.
const (
	T_any      = (1 << 31) - 1 // All bits set.
	T_noval    = 1 << 30       // Absent value (no value at all). NOT a scalar.
	T_boolean  = 1 << 29
	T_decimal  = 1 << 28
	T_integer  = 1 << 27
	T_number   = 1 << 26
	T_string   = 1 << 25
	T_function = 1 << 24
	T_symbol   = 1 << 23
	T_null     = 1 << 22
	// 7 bits reserved
	T_list     = 1 << 14
	T_map      = 1 << 13
	T_instance = 1 << 12
	// 4 bits reserved
	T_scalar   = 1 << 7
	T_node     = 1 << 6
)

// TYPENAME maps bit position (via leading zeros count) to type name string.
var TYPENAME = [...]string{
	S_any,
	S_noval,
	S_boolean,
	S_decimal,
	S_integer,
	S_number,
	S_string,
	S_function,
	S_symbol,
	S_null,
	"", "", "",
	"", "", "", "",
	S_list,
	S_map,
	S_instance,
	"", "", "", "",
	S_scalar,
	S_node,
}

// Sentinel values for control flow in inject/transform.
type _sentinel struct{ name string }

var SKIP = &_sentinel{"SKIP"}
var DELETE = &_sentinel{"DELETE"}

// Regex matching integer keys (including negative).
var reIntegerKey = regexp.MustCompile(`^[-0-9]+$`)

// Meta path syntax regex: matches patterns like "q0$=x1" or "q0$~x1"
var reMetaPath = regexp.MustCompile(`^([^$]+)\$([=~])(.+)$`)

// The standard undefined value for this language.
// NOTE: `nil` must be used directly.

// Keys are strings for maps, or integers for lists.
type PropKey any

// Handle value injections using backtick escape sequences:
// - `a.b.c`: insert value at {a:{b:{c:1}}}
// - `$FOO`: apply transform FOO
type Injector func(
	inj *Injection, // Injection inj.
	val any, // Injection value specification.
	ref *string, // Original injection reference string.
	store any, // Current source root value.
) any

// Injection inj used for recursive injection into JSON-like data structures.
type Injection struct {
	Mode    int              // Injection mode: M_KEYPRE, M_VAL, M_KEYPOST (bitfield).
	Full    bool             // Transform escape was full key name.
	KeyI    int              // Index of parent key in list of parent keys.
	Keys    *ListRef[string] // List of parent keys.
	Key     string           // Current parent key.
	Val     any              // Current child value.
	Parent  any              // Current parent (in transform specification).
	Path    *ListRef[string] // Path to current node.
	Nodes   *ListRef[any]    // Stack of ancestor nodes.
	Handler Injector         // Custom handler for injections.
	Errs    *ListRef[any]    // Error collector.
	Meta    map[string]any   // Custom meta data.
	Dparent any              // Current data parent node (contains current data value).
	Dpath   []string         // Current data value path.
	Base    string           // Base key for data in store, if any.
	Modify  Modify           // Modify injection output.
	Prior   *Injection       // Parent (aka prior) injection.
	Extra   any              // Extra data.
}

// Apply a custom modification to injections.
type Modify func(
	val any, // Value.
	key any, // Value key, if any,
	parent any, // Parent node, if any.
	inj *Injection, // Injection inj, if any.
	store any, // Store, if any
)

// Create a child injection inj sharing errs/meta/modify/handler with parent.
func (inj *Injection) child(keyI int, keys []string) *Injection {
	key := StrKey(keys[keyI])
	val := inj.Val

	childPath := make([]string, len(inj.Path.List))
	copy(childPath, inj.Path.List)
	childPath = append(childPath, key)

	childNodes := make([]any, len(inj.Nodes.List))
	copy(childNodes, inj.Nodes.List)
	childNodes = append(childNodes, val)

	childDpath := make([]string, len(inj.Dpath))
	copy(childDpath, inj.Dpath)

	cinj := &Injection{
		Mode:    inj.Mode,
		Full:    false,
		KeyI:    keyI,
		Keys:    &ListRef[string]{List: keys},
		Key:     key,
		Val:     GetProp(val, key),
		Parent:  val,
		Path:    &ListRef[string]{List: childPath},
		Nodes:   &ListRef[any]{List: childNodes},
		Handler: inj.Handler,
		Modify:  inj.Modify,
		Base:    inj.Base,
		Meta:    inj.Meta,
		Errs:    inj.Errs,
		Prior:   inj,
		Dpath:   childDpath,
		Dparent: inj.Dparent,
	}

	return cinj
}

// Set value in parent or ancestor node.
func (inj *Injection) setval(val any, ancestor ...int) any {
	anc := 0
	if len(ancestor) > 0 {
		anc = ancestor[0]
	}

	if anc < 2 {
		if val == nil {
			inj.Parent = DelProp(inj.Parent, inj.Key)
		} else {
			SetProp(inj.Parent, inj.Key, val)
		}
		return inj.Parent
	} else {
		aval := GetElem(inj.Nodes.List, 0-anc)
		akey := GetElem(inj.Path.List, 0-anc)
		if val == nil {
			DelProp(aval, akey)
		} else {
			SetProp(aval, akey, val)
		}
		return aval
	}
}

// Resolve current node in store for local paths.
func (inj *Injection) descend() any {
	if inj.Meta == nil {
		inj.Meta = map[string]any{}
	}

	// Increment depth counter
	d, _ := inj.Meta["__d"].(int)
	inj.Meta["__d"] = d + 1

	parentkey := ""
	if len(inj.Path.List) >= 2 {
		parentkey = inj.Path.List[len(inj.Path.List)-2]
	}

	if inj.Dparent == nil {
		// Even if there's no data, dpath should continue to match path
		if len(inj.Dpath) > 1 {
			inj.Dpath = append(inj.Dpath, parentkey)
		}
	} else {
		if parentkey != "" {
			inj.Dparent = GetProp(inj.Dparent, parentkey)

			lastpart := ""
			if len(inj.Dpath) > 0 {
				lastpart = inj.Dpath[len(inj.Dpath)-1]
			}
			if lastpart == "$:"+parentkey {
				inj.Dpath = inj.Dpath[:len(inj.Dpath)-1]
			} else {
				inj.Dpath = append(inj.Dpath, parentkey)
			}
		}
	}

	return inj.Dparent
}

// String returns a human-readable representation of the Injection inj.
func (inj *Injection) String(prefix ...string) string {
	pfx := ""
	if len(prefix) > 0 && prefix[0] != "" {
		pfx = "/" + prefix[0]
	}
	fullStr := ""
	if inj.Full {
		fullStr = "/full"
	}

	pathStr := ""
	if inj.Path != nil {
		pathStr = Pathify(inj.Path.List, 1)
	}

	keysStr := ""
	if inj.Keys != nil {
		keysStr = fmt.Sprintf("%v", inj.Keys.List)
	}

	rootVal := ""
	if inj.Nodes != nil && len(inj.Nodes.List) > 0 {
		top := inj.Nodes.List[0]
		if topMap, ok := top.(map[string]any); ok {
			rootVal = Stringify(topMap[S_DTOP], -1, 1)
		}
	}

	return "INJ" + pfx + ":" +
		Pad(pathStr) +
		MODENAME[inj.Mode] + fullStr + ":" +
		"key=" + fmt.Sprintf("%d", inj.KeyI) + "/" + inj.Key + "/" + keysStr +
		"  p=" + Stringify(inj.Parent, -1, 1) +
		"  m=" + Stringify(inj.Meta, -1, 1) +
		"  d/" + Pathify(inj.Dpath, 1) + "=" + Stringify(inj.Dparent, -1, 1) +
		"  r=" + rootVal
}

// Function applied to each node and leaf when walking a node structure depth first.
// The `path` argument is a single mutable slice per depth, shared across all
// callback invocations for the lifetime of a top-level Walk call. Callbacks
// that need to retain the path MUST clone it (e.g. `append([]string(nil), path...)`);
// otherwise its contents will be overwritten by subsequent visits.
type WalkApply func(
	// Map keys are strings, list keys are numbers, top key is nil
	key *string,
	val any,
	parent any,
	path []string,
) any

// Value is a node - defined, and a map (hash) or list (array).
func IsNode(val any) bool {
	if val == nil {
		return false
	}

	return IsMap(val) || IsList(val)
}

// Value is a defined map (hash) with string keys.
func IsMap(val any) bool {
	if val == nil {
		return false
	}
	_, ok := val.(map[string]any)
	return ok
}

// Value is a defined list (array) with integer keys (indexes).
func IsList(val any) bool {
	if val == nil {
		return false
	}
	if _, ok := val.(*ListRef[any]); ok {
		return true
	}
	rv := reflect.ValueOf(val)
	kind := rv.Kind()
	return kind == reflect.Slice || kind == reflect.Array
}

// Value is a defined string (non-empty) or integer key.
func IsKey(val any) bool {
	switch k := val.(type) {
	case string:
		return k != S_MT
	case int, float64, int8, int16, int32, int64:
		return true
	case uint8, uint16, uint32, uint64, uint, float32:
		return true
	default:
		return false
	}
}

// Check for an "empty" value - nil, empty string, array, object.
func IsEmpty(val any) bool {
	if val == nil {
		return true
	}
	switch vv := val.(type) {
	case string:
		return vv == S_MT
	case *ListRef[any]:
		return len(vv.List) == 0
	case []any:
		return len(vv) == 0
	case map[string]any:
		return len(vv) == 0
	}
	return false
}

// Value is a function.
func IsFunc(val any) bool {
	return reflect.ValueOf(val).Kind() == reflect.Func
}

// Get a defined value. Returns alt if val is nil.
func GetDef(val any, alt any) any {
	if nil == val {
		return alt
	}
	return val
}

// Determine the type of a value as a bitset.
// Use bitwise AND to test: 0 < (T_string & Typify(val))
// Use Typename to get the string name.
func Typify(value any) int {
	if value == nil {
		return T_scalar | T_null
	}

	if _, ok := value.(*ListRef[any]); ok {
		return T_node | T_list
	}

	val := reflect.ValueOf(value)
	if !val.IsValid() {
		return T_scalar | T_null
	}

	switch val.Type().Kind() {
	case reflect.Bool:
		return T_scalar | T_boolean

	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		return T_scalar | T_number | T_integer

	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64:
		return T_scalar | T_number | T_integer

	case reflect.Float32, reflect.Float64:
		f, err := _toFloat64(value)
		if err == nil && f == math.Trunc(f) && !math.IsNaN(f) && !math.IsInf(f, 0) {
			return T_scalar | T_number | T_integer
		}
		if err == nil && math.IsNaN(f) {
			return T_noval
		}
		return T_scalar | T_number | T_decimal

	case reflect.String:
		return T_scalar | T_string

	case reflect.Func:
		return T_scalar | T_function

	case reflect.Slice, reflect.Array:
		return T_node | T_list

	case reflect.Map:
		return T_node | T_map

	default:
		return T_node | T_map
	}
}

// Convert a type bitset to its string name using leading zeros count.
func Typename(t int) string {
	if t <= 0 {
		return S_any
	}
	idx := bits.LeadingZeros32(uint32(t))
	if idx < len(TYPENAME) && TYPENAME[idx] != "" {
		return TYPENAME[idx]
	}
	return S_any
}

// The integer size of the value. For lists and maps, the number of entries.
// For strings, the length. For numbers, the integer part.
// For booleans, true is 1 and false is 0. For all other values, 0.
func Size(val any) int {
	if IsList(val) {
		list, ok := _asList(val)
		if ok {
			return len(list)
		}
		return len(_listify(val))
	} else if IsMap(val) {
		return len(val.(map[string]any))
	}

	switch v := val.(type) {
	case string:
		return len(v)
	case bool:
		if v {
			return 1
		}
		return 0
	default:
		f, err := _toFloat64(val)
		if err == nil {
			return int(math.Floor(f))
		}
		return 0
	}
}

// Extract part of a list or string into a new value, from the start
// point to the end point. If no end is specified, extract to the
// full length. Negative arguments count from the end. For numbers,
// perform min and max bounding (start inclusive, end exclusive).
func Slice(val any, args ...any) any {
	var startP, endP *int
	var mutate bool

	if len(args) > 0 && args[0] != nil {
		if f, err := _toFloat64(args[0]); err == nil {
			i := int(f)
			startP = &i
		}
	}
	if len(args) > 1 && args[1] != nil {
		if f, err := _toFloat64(args[1]); err == nil {
			i := int(f)
			endP = &i
		}
	}
	if len(args) > 2 {
		if b, ok := args[2].(bool); ok {
			mutate = b
		}
	}

	// Number case: clamp between start (inclusive) and end-1 (exclusive->inclusive).
	if _, ok := val.(string); !ok && !IsNode(val) {
		if f, err := _toFloat64(val); err == nil {
			start := math.MinInt64
			if startP != nil {
				start = *startP
			}
			end := math.MaxInt64
			if endP != nil {
				end = *endP - 1
			}
			result := int(math.Min(math.Max(f, float64(start)), float64(end)))
			return result
		}
	}

	vlen := Size(val)

	if endP != nil && startP == nil {
		zero := 0
		startP = &zero
	}

	if startP == nil {
		return val
	}

	start := *startP
	end := vlen

	if start < 0 {
		end = vlen + start
		if end < 0 {
			end = 0
		}
		start = 0
	} else if endP != nil {
		end = *endP
		if end < 0 {
			end = vlen + end
			if end < 0 {
				end = 0
			}
		} else if vlen < end {
			end = vlen
		}
	}

	if vlen < start {
		start = vlen
	}

	if start >= 0 && start <= end && end <= vlen {
		if IsList(val) {
			list, _ := _asList(val)
			if list == nil {
				list = _listify(val)
			}
			if mutate {
				for i, j := 0, start; j < end; i, j = i+1, j+1 {
					list[i] = list[j]
				}
				list = list[:end-start]
				if lr, ok := val.(*ListRef[any]); ok {
					lr.List = list
					return lr
				}
				return list
			}
			return append([]any{}, list[start:end]...)
		} else if s, ok := val.(string); ok {
			return s[start:end]
		}
	} else {
		if IsList(val) {
			return []any{}
		} else if _, ok := val.(string); ok {
			return S_MT
		}
	}

	return val
}

// String padding. Positive padding right-pads, negative left-pads.
// Default padding is 44, default pad character is space.
func Pad(str any, args ...any) string {
	var s string
	if ss, ok := str.(string); ok {
		s = ss
	} else {
		s = Stringify(str)
	}

	padding := 44
	if len(args) > 0 && args[0] != nil {
		if f, err := _toFloat64(args[0]); err == nil {
			padding = int(f)
		}
	}

	padchar := S_SP
	if len(args) > 1 && args[1] != nil {
		if pc, ok := args[1].(string); ok && len(pc) > 0 {
			padchar = string(pc[0])
		}
	}

	if padding >= 0 {
		for len(s) < padding {
			s += padchar
		}
	} else {
		target := -padding
		for len(s) < target {
			s = padchar + s
		}
	}

	return s
}

// Get a list element. The key should be an integer, or a string
// that parses to an integer. Negative integers count from the end.
func GetElem(val any, key any, alts ...any) any {
	var alt any
	if len(alts) > 0 {
		alt = alts[0]
	}

	if nil == val || nil == key {
		return alt
	}

	var out any

	if IsList(val) {
		ks := StrKey(key)
		if reIntegerKey.MatchString(ks) {
			nkey, err := strconv.Atoi(ks)
			if err == nil {
				list, ok := _asList(val)
				if !ok {
					list = _listify(val)
				}
				if nkey < 0 {
					nkey = len(list) + nkey
				}
				if nkey >= 0 && nkey < len(list) {
					out = list[nkey]
				}
			}
		}
	}

	if nil == out {
		if 0 < (T_function & Typify(alt)) {
			fn := reflect.ValueOf(alt)
			results := fn.Call(nil)
			if len(results) > 0 {
				return results[0].Interface()
			}
			return nil
		}
		return alt
	}

	return out
}

// Safely get a property of a node. Nil arguments return nil.
// If the key is not found, return the alternative value, if any.
func GetProp(val any, key any, alts ...any) any {
	var out any
	var alt any

	if len(alts) > 0 {
		alt = alts[0]
	}

	if nil == val || nil == key {
		return alt
	}

	if IsMap(val) {
		ks, ok := key.(string)
		if !ok {
			ks = StrKey(key)
		}

		v := val.(map[string]any)
		res, has := v[ks]
		if has {
			out = res
		}

	} else if IsList(val) {
		ki, ok := key.(int)
		if !ok {
			switch kf := key.(type) {
			case float64:
				ki = int(kf)

			case string:
				ki = -1
				ski, err := strconv.Atoi(key.(string))
				if nil == err {
					ki = ski
				}
			}
		}

		if lr, isLR := val.(*ListRef[any]); isLR {
			if 0 <= ki && ki < len(lr.List) {
				out = lr.List[ki]
			}
		} else {
			v, ok := val.([]any)

			if !ok {
				rv := reflect.ValueOf(val)
				if rv.Kind() == reflect.Slice && 0 <= ki && ki < rv.Len() {
					out = rv.Index(ki).Interface()
				}

			} else {
				if 0 <= ki && ki < len(v) {
					out = v[ki]
				}
			}
		}

	} else {
		valRef := reflect.ValueOf(val)
		if valRef.Kind() == reflect.Ptr {
			valRef = valRef.Elem()
		}

		if valRef.Kind() == reflect.Struct {
			ks, ok := key.(string)
			if !ok {
				ks = StrKey(key)
			}

			field := valRef.FieldByName(ks)
			if field.IsValid() {
				out = field.Interface()
			}
		}
	}

	if nil == out {
		return alt
	}

	return out
}

// Sorted keys of a map, or indexes of a list.
func KeysOf(val any) []string {
	if IsMap(val) {
		m := val.(map[string]any)

		keys := make([]string, 0, len(m))
		for k := range m {
			keys = append(keys, k)
		}

		sort.Strings(keys)

		return keys

	} else if IsList(val) {
		list, _ := _asList(val)
		if list == nil {
			list = _listify(val)
		}
		keys := make([]string, len(list))
		for i := range list {
			keys[i] = StrKey(i)
		}
		return keys
	}

	return make([]string, 0)
}


// Value of property with name key in node val is defined.
func HasKey(val any, key any) bool {
	return nil != GetProp(val, key)
}


// List the sorted keys of a map or list as an array of tuples of the form [key, value].
func Items(val any) [][2]any {
	if IsMap(val) {
		m := val.(map[string]any)
		out := make([][2]any, 0, len(m))

    keys := KeysOf(val)
		// keys := make([]string, 0, len(m))
		// for k := range m {
		// 	keys = append(keys, k)
		// }
		// sort.Strings(keys)

		for _, k := range keys {
			out = append(out, [2]any{k, m[k]})
		}
		return out

	} else if IsList(val) {
		list, _ := _asList(val)
		if list == nil {
			list = _listify(val)
		}
		out := make([][2]any, 0, len(list))
		for i, v := range list {
			out = append(out, [2]any{strconv.Itoa(i), v})
		}
		return out
	}

	return make([][2]any, 0, 0)
}

// List items with an optional apply callback that maps over each [key, value] tuple.
func ItemsApply(val any, apply func([2]any) any) []any {
	items := Items(val)
	out := make([]any, len(items))
	for i, item := range items {
		out[i] = apply(item)
	}
	return out
}

// Flatten a nested list to a given depth (default 1).
// Non-list inputs are returned as-is.
func Flatten(list any, depths ...int) any {
	if !IsList(list) {
		return list
	}

	depth := 1
	if len(depths) > 0 {
		depth = depths[0]
	}

	arr, ok := _asList(list)
	if !ok {
		arr = _listify(list)
	}

	return _flattenDepth(arr, depth)
}

func _flattenDepth(arr []any, depth int) []any {
	result := make([]any, 0)
	for _, item := range arr {
		if depth > 0 {
			if sub, ok := _asList(item); ok {
				result = append(result, _flattenDepth(sub, depth-1)...)
				continue
			}
		}
		result = append(result, item)
	}
	return result
}

// Filter item values using check function.
// Returns values where the check function returns true.
func Filter(val any, check func([2]any) bool) []any {
	all := Items(val)
	out := make([]any, 0)
	for _, item := range all {
		if check(item) {
			out = append(out, item[1])
		}
	}
	return out
}


// Escape regular expression.
func EscRe(s string) string {
	if s == "" {
		return ""
	}
	re := regexp.MustCompile(`[.*+?^${}()|\[\]\\]`)
	return re.ReplaceAllString(s, `\${0}`)
}

// Escape URLs.
func EscUrl(s string) string {
	return url.QueryEscape(s)
}

var (
	reNonSlashSlash = regexp.MustCompile(`([^/])/+`)
	reTrailingSlash = regexp.MustCompile(`/+$`)
	reLeadingSlash  = regexp.MustCompile(`^/+`)
)

// Concatenate url part strings, merging forward slashes as needed.
func JoinUrl(parts []any) string {
	var filtered []string
	for _, p := range parts {
		if "" != p && nil != p {
			ps, ok := p.(string)
			if !ok {
				ps = Stringify(p)
			}
			filtered = append(filtered, ps)
		}
	}

	for i, s := range filtered {
		if i == 0 {
			// For the first part, only remove trailing slashes
			s = reTrailingSlash.ReplaceAllString(s, "")
		} else {
			// For remaining parts, handle both leading and trailing slashes
			s = reNonSlashSlash.ReplaceAllString(s, `$1/`)
			s = reLeadingSlash.ReplaceAllString(s, "")
			s = reTrailingSlash.ReplaceAllString(s, "")
		}
		filtered[i] = s
	}

	finalParts := filtered[:0]
	for _, s := range filtered {
		if s != "" {
			finalParts = append(finalParts, s)
		}
	}

	return strings.Join(finalParts, "/")
}


// Concatenate string array elements, merging separator chars as needed.
// Optional args: sep (string, default ","), url (bool, default false).
func Join(arr []any, args ...any) string {
	sarr := Size(arr)

	sep := ","
	urlMode := false

	if len(args) > 0 && args[0] != nil {
		if s, ok := args[0].(string); ok {
			sep = s
		}
	}
	if len(args) > 1 && args[1] != nil {
		if b, ok := args[1].(bool); ok {
			urlMode = b
		}
	}

	var sepre string
	if 1 == len(sep) {
		sepre = EscRe(sep)
	}

	// Filter to only non-empty strings
	filtered := Filter(arr, func(n [2]any) bool {
		t := Typify(n[1])
		return (0 < (T_string & t)) && S_MT != n[1]
	})

	// Process each element for separator handling
	processed := Items(filtered)

	var parts []string
	for _, kv := range processed {
		idx := 0
		if kstr, ok := kv[0].(string); ok {
			n, err := strconv.Atoi(kstr)
			if err == nil {
				idx = n
			}
		}
		s, ok := kv[1].(string)
		if !ok {
			continue
		}

		if sepre != "" && sepre != S_MT {
			reTrailing := regexp.MustCompile(sepre + `+$`)
			reLeading := regexp.MustCompile(`^` + sepre + `+`)
			reInternal := regexp.MustCompile(`([^` + sepre + `])` + sepre + `+([^` + sepre + `])`)

			if urlMode && 0 == idx {
				s = reTrailing.ReplaceAllString(s, S_MT)
			} else {
				if 0 < idx {
					s = reLeading.ReplaceAllString(s, S_MT)
				}

				if idx < sarr-1 || !urlMode {
					s = reTrailing.ReplaceAllString(s, S_MT)
				}

				s = reInternal.ReplaceAllString(s, "${1}"+sep+"${2}")
			}
		}

		if s != S_MT {
			parts = append(parts, s)
		}
	}

	return strings.Join(parts, sep)
}


// Output JSON in a "standard" format, with 2 space indents, each property on a new line,
// and spaces after {[: and before ]}. Any "weird" values (NaN, etc) are output as null.
// In general, the behavior of JavaScript's JSON.stringify(val,null,2) is followed.
func Jsonify(val any, flags ...map[string]any) string {
	str := S_null

	indent := 2
	offset := 0

	if len(flags) > 0 && flags[0] != nil {
		if v, ok := flags[0]["indent"]; ok {
			if n, ok := v.(int); ok {
				indent = n
			}
		}
		if v, ok := flags[0]["offset"]; ok {
			if n, ok := v.(int); ok {
				offset = n
			}
		}
	}

	if nil != val {
		indentStr := strings.Repeat(" ", indent)
		offsetStr := strings.Repeat(" ", offset)
		b, err := json.MarshalIndent(val, offsetStr, indentStr)
		if err != nil {
			str = S_null
		} else {
			str = string(b)
		}
	}

	return str
}

// Safely stringify a value for humans (NOT JSON!).
func Stringify(val any, maxlen ...int) string {
	if nil == val {
		return S_MT
	}

	if lr, ok := val.(*ListRef[any]); ok {
		return Stringify(lr.List, maxlen...)
	}

	// Strings are returned directly without JSON serialization.
	if s, ok := val.(string); ok {
		jsonStr := s
		if len(maxlen) > 0 && maxlen[0] > 0 {
			ml := maxlen[0]
			if len(jsonStr) > ml {
				if ml >= 3 {
					jsonStr = jsonStr[:ml-3] + "..."
				} else {
					jsonStr = jsonStr[:ml]
				}
			}
		}
		return jsonStr
	}

	// Unwrap any nested ListRefs before marshaling to JSON.
	val = _unwrapListRefs(val)

	b, err := json.Marshal(val)
	if err != nil {
		return "__STRINGIFY_FAILED__"
	}
	jsonStr := string(b)

	jsonStr = strings.ReplaceAll(jsonStr, `"`, "")

	if len(maxlen) > 0 && maxlen[0] > 0 {
		ml := maxlen[0]
		if len(jsonStr) > ml {
			if ml >= 3 {
				jsonStr = jsonStr[:ml-3] + "..."
			} else {
				jsonStr = jsonStr[:ml]
			}
		}
	}

	return jsonStr
}

// Build a human friendly path string.
func Pathify(val any, from ...int) string {
	var pathstr *string

	var path []any = nil

	if IsList(val) {
		path = _listify(val)
	} else {
		str, ok := val.(string)
		if ok {
			path = append(path, str)
		} else {
			num, err := _toFloat64(val)
			if nil == err {
				path = append(path, strconv.FormatInt(int64(math.Floor(num)), 10))
			}
		}
	}

	var start int
	if 0 == len(from) {
		start = 0

	} else {
		start = from[0]
		if start < 0 {
			start = 0
		}
	}

	end := 0
	if len(from) > 1 {
		end = from[1]
		if end < 0 {
			end = 0
		}
	}

	if nil != path && 0 <= start {
		if len(path) < start {
			start = len(path)
		}

		endIdx := len(path) - end
		if endIdx < start {
			endIdx = start
		}

		sliced := path[start:endIdx]
		if len(sliced) == 0 {
			root := "<root>"
			pathstr = &root

		} else {
			var filtered []any
			for _, p := range sliced {
				switch x := p.(type) {
				case string:
					filtered = append(filtered, x)
				case int, int8, int16, int32, int64,
					float32, float64, uint, uint8, uint16, uint32, uint64:
					filtered = append(filtered, x)
				}
			}

			var mapped []string
			for _, p := range filtered {
				switch x := p.(type) {
				case string:
					replaced := strings.ReplaceAll(x, S_DT, S_MT)
					mapped = append(mapped, replaced)
				default:
					numVal, err := _toFloat64(x)
					if err == nil {
						mapped = append(mapped, S_MT+strconv.FormatInt(int64(math.Floor(numVal)), 10))
					}
				}
			}

			joined := strings.Join(mapped, S_DT)
			pathstr = &joined
		}
	}

	if nil == pathstr {
		var sb strings.Builder
		sb.WriteString("<unknown-path")
		if val == nil {
			sb.WriteString(S_MT)
		} else {
			sb.WriteString(S_CN)
			sb.WriteString(Stringify(val, 33))
		}
		sb.WriteString(">")
		updesc := sb.String()
		pathstr = &updesc
	}

	return *pathstr
}

// Clone a JSON-like data structure.
// NOTE: function value references are copied, *not* cloned.
func Clone(val any) any {
	return CloneFlags(val, nil)
}

func CloneFlags(val any, flags map[string]bool) any {
	if val == nil {
		return nil
	}

	if nil == flags {
		flags = map[string]bool{}
	}

	if _, ok := flags["func"]; !ok {
		flags["func"] = true
	}

	typ := reflect.TypeOf(val)
	if typ.Kind() == reflect.Func {
		if flags["func"] {
			return val
		}
		return nil
	}

	switch v := val.(type) {
	case map[string]any:
		newMap := make(map[string]any, len(v))
		for key, value := range v {
			newMap[key] = CloneFlags(value, flags)
		}
		return newMap
	case *ListRef[any]:
		newSlice := make([]any, len(v.List))
		for i, value := range v.List {
			newSlice[i] = CloneFlags(value, flags)
		}
		if flags["unwrap"] {
			return newSlice
		}
		return &ListRef[any]{List: newSlice}
	case []any:
		newSlice := make([]any, len(v))
		for i, value := range v {
			newSlice[i] = CloneFlags(value, flags)
		}
		if flags["wrap"] {
			return &ListRef[any]{List: newSlice}
		}
		return newSlice
	default:
		return v
	}
}

// Define a JSON Object from alternating key-value arguments.
// jo("a", 1, "b", 2) => {"a": 1, "b": 2}
func Jo(kv ...any) map[string]any {
	o := make(map[string]any)
	kvsize := len(kv)
	for i := 0; i < kvsize; i += 2 {
		k := GetProp(kv, i, S_DS+S_KEY+strconv.Itoa(i))
		ks, ok := k.(string)
		if !ok {
			ks = Stringify(k)
		}
		o[ks] = GetProp(kv, i+1)
	}
	return o
}

// Define a JSON Array from arguments.
// ja(1, "x", true) => [1, "x", true]
func Ja(v ...any) []any {
	a := make([]any, len(v))
	for i := 0; i < len(v); i++ {
		a[i] = GetProp(v, i)
	}
	return a
}

// Safely delete a property from a map or list element.
// For maps, the property is deleted. For lists, the element at the
// index is removed and remaining elements are shifted down.
// Returns the (possibly modified) parent.
func DelProp(parent any, key any) any {
	if !IsKey(key) {
		return parent
	}

	if IsMap(parent) {
		ks := StrKey(key)
		delete(parent.(map[string]any), ks)
	} else if IsList(parent) {
		ks := StrKey(key)
		ki, err := _parseInt(ks)
		if err != nil {
			return parent
		}
		ki = int(math.Floor(float64(ki)))

		if lr, isLR := parent.(*ListRef[any]); isLR {
			psize := len(lr.List)
			if 0 <= ki && ki < psize {
				copy(lr.List[ki:], lr.List[ki+1:])
				lr.List = lr.List[:psize-1]
			}
			return parent
		}

		arr, genarr := parent.([]any)
		if !genarr {
			rv := reflect.ValueOf(parent)
			arr = make([]any, rv.Len())
			for i := 0; i < rv.Len(); i++ {
				arr[i] = rv.Index(i).Interface()
			}
		}

		psize := len(arr)
		if 0 <= ki && ki < psize {
			copy(arr[ki:], arr[ki+1:])
			arr = arr[:psize-1]
		}

		if !genarr {
			return _makeArrayType(arr, parent)
		}
		return arr
	}

	return parent
}

// Safely set a property. Undefined arguments and invalid keys are ignored.
// Returns the (possibly modified) parent.
// If the value is undefined the key will be deleted from the parent.
// If the parent is a list, and the key is negative, prepend the value.
// NOTE: If the key is above the list size, append the value; below, prepend.
// If the value is undefined, remove the list element at index key, and shift the
// remaining elements down.  These rules avoid "holes" in the list.
func SetProp(parent any, key any, newval any) any {
	if !IsKey(key) {
		return parent
	}

	if IsMap(parent) {
		m := parent.(map[string]any)

		// Convert key to string
		ks := ""
		ks = StrKey(key)

		// Preserve nil values (like JS null). Use DelProp for explicit key removal.
		m[ks] = newval

	} else if IsList(parent) {

		// Convert key to integer
		var ki int
		switch k := key.(type) {
		case int:
			ki = k
		case float64:
			ki = int(k)
		case string:
			kiParsed, e := _parseInt(k)
			if e == nil {
				ki = kiParsed
			} else {
				// no-op, can't set
				return parent
			}
		default:
			return parent
		}

		// ListRef: modify .List in place, return same pointer for reference stability.
		if lr, isLR := parent.(*ListRef[any]); isLR {
			if newval == nil {
				if ki >= 0 && ki < len(lr.List) {
					copy(lr.List[ki:], lr.List[ki+1:])
					lr.List = lr.List[:len(lr.List)-1]
				}
				return parent
			}
			if ki >= 0 {
				if ki >= len(lr.List) {
					lr.List = append(lr.List, newval)
				} else {
					lr.List[ki] = newval
				}
				return parent
			}
			if ki < 0 {
				lr.List = append([]any{newval}, lr.List...)
				return parent
			}
			return parent
		}

		arr, genarr := parent.([]any)

		// If newval == nil, remove element [shift down].

		if !genarr {
			rv := reflect.ValueOf(parent)
			arr = make([]any, rv.Len())
			for i := 0; i < rv.Len(); i++ {
				arr[i] = rv.Index(i).Interface()
			}
		}

		if newval == nil {
			if ki >= 0 && ki < len(arr) {
				copy(arr[ki:], arr[ki+1:])
				arr = arr[:len(arr)-1]
			}

			if !genarr {
				return _makeArrayType(arr, parent)
			} else {

				return arr
			}
		}

		// If ki >= 0, set or append
		if ki >= 0 {
			if ki >= len(arr) {
				arr = append(arr, newval)
			} else {
				arr[ki] = newval
			}

			if !genarr {
				return _makeArrayType(arr, parent)
			} else {
				return arr
			}
		}

		// If ki < 0, prepend
		if ki < 0 {
			// prepend
			newarr := make([]any, 0, len(arr)+1)
			newarr = append(newarr, newval)
			newarr = append(newarr, arr...)
			if !genarr {
				return _makeArrayType(newarr, parent)
			} else {
				return newarr
			}
		}
	}

	return parent
}

// Walk a data structure depth first, applying functions to each value.
// Walk(val, before) - before callback only (pre-order).
// Walk(val, before, after) - both before and after callbacks.
// Walk(val, before, after, maxdepth) - with maximum recursion depth.
// Pass nil for before or after to skip that callback.
// For backward compatibility, Walk(val, apply) applies the callback after children (post-order).
//
// The `path` passed to callbacks is a single mutable slice per depth, reused
// across recursive calls. Callbacks must clone it (see WalkApply) if they want
// to retain it beyond the invocation.
func Walk(
	val any,
	apply WalkApply,
	opts ...any,
) any {
	var after WalkApply
	var maxdepth int = 32

	if len(opts) > 0 {
		if opts[0] != nil {
			if fn, ok := opts[0].(WalkApply); ok {
				after = fn
			} else if fn, ok := opts[0].(func(*string, any, any, []string) any); ok {
				after = fn
			}
		}
	}
	if len(opts) > 1 {
		if opts[1] != nil {
			switch md := opts[1].(type) {
			case int:
				maxdepth = md
			case float64:
				maxdepth = int(md)
			}
		}
	}

	// Allocate the path-pool once per top-level Walk. pool[n] is a backing
	// array of length n that holds the current path for depth n; it is
	// grown on demand and mutated in place by _walkDescend.
	pool := [][]string{nil}

	if after != nil {
		// Two-callback mode: apply is before, after is after.
		return _walkDescend(val, apply, after, maxdepth, nil, nil, nil, pool)
	}

	// Single-callback mode: apply is called before children (pre-order),
	// matching the TS implementation where walk(val, before) is pre-order.
	return _walkDescend(val, apply, nil, maxdepth, nil, nil, nil, pool)
}


// WalkDescend performs a post-order walk from an arbitrary start point
// (with explicit key, parent, and path). Unlike Walk it does not share a
// pool across recursive calls: it allocates per-call path arrays. Intended
// for ad-hoc recursive descents from a non-root position.
func WalkDescend(
	val any,
	apply WalkApply,
	key *string,
	parent any,
	path []string,
) any {
	return _walkDescendAlloc(val, nil, apply, 32, key, parent, path)
}


// _walkDescend is the pool-threaded core used by Walk. The `path` slice it
// hands to callbacks is reused across sibling visits: each recursive call
// reuses pool[depth+1] (growing the pool on demand), writes its own key in
// the last slot, and passes the slice down. Callbacks must clone it if they
// want to retain it.
func _walkDescend(
	val any,
	before WalkApply,
	after WalkApply,
	maxdepth int,
	key *string,
	parent any,
	path []string,
	pool [][]string,
) any {

	if path == nil {
		path = pool[0]
	}
	depth := len(path)

	out := val

	// Apply before callback.
	if nil != before {
		out = before(key, out, parent, path)
	}

	// Check depth limit.
	if 0 == maxdepth || (0 < maxdepth && maxdepth <= depth) {
		return out
	}

	if IsNode(out) {
		childDepth := depth + 1
		// Grow pool on demand.
		for len(pool) <= childDepth {
			pool = append(pool, nil)
		}
		childPath := pool[childDepth]
		if childPath == nil {
			childPath = make([]string, childDepth)
			pool[childDepth] = childPath
		}
		// Sync prefix [0..depth-1] from the current path. Only needed
		// once per parent: siblings share the same prefix and will each
		// overwrite slot [depth] below.
		for i := 0; i < depth; i++ {
			childPath[i] = path[i]
		}

		for _, kv := range Items(out) {
			ckey := kv[0]
			child := kv[1]
			ckeyStr := StrKey(ckey)
			childPath[depth] = ckeyStr
			newChild := _walkDescend(child, before, after, maxdepth, &ckeyStr, out, childPath, pool)
			out = SetProp(out, ckey, newChild)
		}

		if nil != parent && nil != key {
			SetProp(parent, *key, out)
		}
	}

	// Apply after callback.
	if nil != after {
		out = after(key, out, parent, path)
	}

	return out
}


// _walkDescendAlloc is the legacy per-call-allocating descent used by
// WalkDescend, preserved for callers that enter the recursion at an
// arbitrary point without a shared pool.
func _walkDescendAlloc(
	val any,
	before WalkApply,
	after WalkApply,
	maxdepth int,
	key *string,
	parent any,
	path []string,
) any {

	out := val

	if nil != before {
		out = before(key, out, parent, path)
	}

	if 0 == maxdepth || (nil != path && 0 < maxdepth && maxdepth <= len(path)) {
		return out
	}

	if IsNode(out) {
		for _, kv := range Items(out) {
			ckey := kv[0]
			child := kv[1]
			ckeyStr := StrKey(ckey)
			newPath := make([]string, len(path)+1)
			copy(newPath, path)
			newPath[len(path)] = ckeyStr
			newChild := _walkDescendAlloc(child, before, after, maxdepth, &ckeyStr, out, newPath)
			out = SetProp(out, ckey, newChild)
		}

		if nil != parent && nil != key {
			SetProp(parent, *key, out)
		}
	}

	if nil != after {
		out = after(key, out, parent, path)
	}

	return out
}

// Merge a list of values into each other. Later values have
// precedence.  Nodes override scalars. Node kinds (list or map)
// override each other, and do *not* merge.  The first element is
// modified.
// Optional maxdepth parameter limits recursion depth.
func Merge(val any, maxdepths ...int) any {
	md := 32
	if len(maxdepths) > 0 {
		if maxdepths[0] < 0 {
			md = 0
		} else {
			md = maxdepths[0]
		}
	}

	var out any = nil

	if !IsList(val) {
		return val
	}

	list := _listify(val)
	lenlist := len(list)

	if 0 == lenlist {
		return nil
	}

	if 1 == lenlist {
		return list[0]
	}

	// Merge a list of values.
	out = GetProp(list, 0, make(map[string]any))

	for i := 1; i < lenlist; i++ {
		obj := list[i]

		if !IsNode(obj) {
			// Nodes win.
			out = obj
		} else {
			// Current value at path end in overriding node.
			cur := make([]any, 33)
			cur[0] = out

			// Current value at path end in destination node.
			dst := make([]any, 33)
			dst[0] = out

			before := func(
				key *string,
				val any,
				_parent any,
				path []string,
			) any {
				pI := len(path)

				if md <= pI {
					if key != nil {
						SetProp(cur[pI-1], *key, val)
					}
				} else if !IsNode(val) {
					// Scalars just override directly.
					cur[pI] = val
				} else {
					// Descend into override node.
					if 0 < pI && key != nil {
						dst[pI] = GetProp(dst[pI-1], *key)
					}
					tval := dst[pI]

					// Destination empty, create node (unless override is class instance).
					if nil == tval && 0 == (T_instance&Typify(val)) {
						if IsList(val) {
							cur[pI] = make([]any, 0)
						} else {
							cur[pI] = make(map[string]any)
						}
					} else if Typify(val) == Typify(tval) {
						// Matching override and destination, continue with their values.
						cur[pI] = tval
					} else {
						// Override wins.
						cur[pI] = val
						// No need to descend (destination is discarded).
						val = nil
					}
				}

				return val
			}

			after := func(
				key *string,
				_val any,
				_parent any,
				path []string,
			) any {
				cI := len(path)

				// Root node: nothing to set on parent.
				if nil == key || cI <= 0 {
					return cur[0]
				}

				value := cur[cI]

				cur[cI-1] = SetProp(cur[cI-1], *key, value)
				return value
			}

			// Walk overriding node, creating paths in output as needed.
			Walk(obj, before, after, md)

			out = cur[0]
		}
	}

	if 0 == md {
		out = GetElem(list, -1)
		if IsList(out) {
			out = make([]any, 0)
		} else if IsMap(out) {
			out = make(map[string]any)
		}
	}

	return out
}

// Get a value deep inside a node using a key path.  For example the
// path `a.b` gets the value 1 from {a:{b:1}}.  The path can specified
// as a dotted string, or a string array.  If the path starts with a
// dot (or the first element is "), the path is considered local, and
// resolved against the `current` argument, if defined.  Integer path
// parts are used as array indexes.  The inj argument allows for
// custom handling when called from `inject` or `transform`.
func GetPath(path any, store any, injdefs ...*Injection) any {
	var inj *Injection
	if len(injdefs) > 0 {
		inj = injdefs[0]
	}

	var parts []string

	// Operate on a string array.
	switch pp := path.(type) {
	case []string:
		parts = make([]string, len(pp))
		copy(parts, pp)

	case string:
		if pp == "" {
			parts = []string{S_MT}
		} else {
			parts = strings.Split(pp, S_DT)
		}
	default:
		if IsList(path) {
			parts = _resolveStrings(_listify(path))
		} else {
			return nil
		}
	}

	val := store
	var base any = nil
	if nil != inj {
		base = inj.Base
	}

	src := GetProp(store, base, store)
	var dparent any
	if inj != nil {
		dparent = inj.Dparent
	}

	numparts := len(parts)

	// An empty path (incl empty string) just finds the store.
	if nil == path || nil == store || (1 == numparts && S_MT == parts[0]) {
		val = src

	} else if 0 < numparts {

		// Check for $ACTIONs
		if 1 == numparts {
			val = GetProp(store, parts[0])
		}

		if !IsFunc(val) {
			val = src

			// Meta path syntax: "q0$=x1" or "q0$~x1"
			m := reMetaPath.FindStringSubmatch(parts[0])
			if m != nil && inj != nil && inj.Meta != nil {
				val = GetProp(inj.Meta, m[1])
				parts[0] = m[3]
			}

			var dpath []string
			if inj != nil {
				dpath = inj.Dpath
			}

			for pI := 0; val != nil && pI < numparts; pI++ {
				part := parts[pI]

				if inj != nil && part == "$KEY" {
					part = inj.Key
				} else if inj != nil && strings.HasPrefix(part, "$GET:") {
					// $GET:path$ -> get store value, use as path part
					subpath := part[5 : len(part)-1]
					result := GetPath(subpath, src)
					part = Stringify(result)
				} else if inj != nil && strings.HasPrefix(part, "$REF:") {
					// $REF:refpath$ -> get spec value, use as path part
					subpath := part[5 : len(part)-1]
					specVal := GetProp(store, S_DSPEC)
					if specVal != nil {
						result := GetPath(subpath, specVal)
						part = Stringify(result)
					}
				} else if inj != nil && strings.HasPrefix(part, "$META:") {
					// $META:metapath$ -> get meta value, use as path part
					subpath := part[6 : len(part)-1]
					result := GetPath(subpath, inj.Meta)
					part = Stringify(result)
				}

				// $$ escapes $
				part = strings.ReplaceAll(part, "$$", "$")

				if S_MT == part {
					ascends := 0
					for 1+pI < numparts && S_MT == parts[1+pI] {
						ascends++
						pI++
					}

					if inj != nil && 0 < ascends {
						if pI == numparts-1 {
							ascends--
						}

						if 0 == ascends {
							val = dparent
						} else {
							// Build fullpath from dpath + remaining parts
							cutLen := len(dpath) - ascends
							if cutLen < 0 {
								cutLen = 0
							}
							fullpath := make([]string, 0)
							fullpath = append(fullpath, dpath[:cutLen]...)
							if pI+1 < numparts {
								fullpath = append(fullpath, parts[pI+1:]...)
							}

							if ascends <= len(dpath) {
								val = GetPath(fullpath, store)
							} else {
								val = nil
							}
							break
						}
					} else {
						val = dparent
					}
				} else {
					val = GetProp(val, part)
				}
			}
		}
	}

	if nil != inj && inj.Handler != nil {
		ref := Pathify(path)
		val = inj.Handler(inj, val, &ref, store)
	}

	return val
}

// Set a value at a path inside a store. Missing intermediate path
// parts are created (maps for string keys, lists for numeric keys).
// String paths are split on ".". If val is the DELETE sentinel,
// the final key is deleted instead of set.
func SetPath(store any, path any, val any, injdefs ...map[string]any) any {
	pathType := Typify(path)

	var parts []any
	if 0 < (T_list & pathType) {
		parts = _listify(path)
	} else if 0 < (T_string & pathType) {
		splitParts := strings.Split(path.(string), S_DT)
		parts = make([]any, len(splitParts))
		for i, s := range splitParts {
			parts[i] = s
		}
	} else if 0 < (T_number & pathType) {
		parts = []any{path}
	} else {
		return nil
	}

	var base any
	if len(injdefs) > 0 && injdefs[0] != nil {
		base = GetProp(injdefs[0], S_base)
	}

	numparts := len(parts)
	parent := GetProp(store, base, store)

	var grandparent any
	var grandKey any

	for pI := 0; pI < numparts-1; pI++ {
		partKey := GetElem(parts, pI)
		nextParent := GetProp(parent, partKey)
		if !IsNode(nextParent) {
			nextPartKey := GetElem(parts, pI+1)
			if 0 < (T_number & Typify(nextPartKey)) {
				nextParent = []any{}
			} else {
				nextParent = map[string]any{}
			}
			SetProp(parent, partKey, nextParent)
		}
		grandparent = parent
		grandKey = partKey
		parent = nextParent
	}

	lastKey := GetElem(parts, -1)
	if val == DELETE {
		newParent := DelProp(parent, lastKey)
		if grandparent != nil && IsList(parent) {
			SetProp(grandparent, grandKey, newParent)
		}
		return newParent
	} else {
		newParent := SetProp(parent, lastKey, val)
		if grandparent != nil && IsList(parent) {
			SetProp(grandparent, grandKey, newParent)
		}
		return newParent
	}
}

// Inject store values into a string. Not a public utility - used by
// `inject`.  Inject are marked with `path` where path is resolved
// with getpath against the store or current (if defined)
// arguments. See `getpath`.  Custom injection handling can be
// provided by inj.handler (this is used for transform functions).
// The path can also have the special syntax $NAME999 where NAME is
// upper case letters only, and 999 is any digits, which are
// discarded. This syntax specifies the name of a transform, and
// optionally allows transforms to be ordered by alphanumeric sorting.
func _injectStr(
	val string,
	store any,
	inj *Injection,
) any {
	if val == S_MT {
		return S_MT
	}

	// Pattern examples: "`a.b.c`", "`$NAME`", "`$NAME1`"
	// fullRe := regexp.MustCompile("^`([^`]+)[0-9]*`$")
	fullRe := regexp.MustCompile("^`(\\$[A-Z]+|[^`]*)[0-9]*`$")
	matches := fullRe.FindStringSubmatch(val)

	// Full string of the val is an injection.
	if matches != nil {
		if nil != inj {
			inj.Full = true
		}
		pathref := matches[1]

		// Special escapes inside injection.
		if len(pathref) > 3 {
			pathref = strings.ReplaceAll(pathref, "$BT", S_BT)
			pathref = strings.ReplaceAll(pathref, "$DS", S_DS)
		}

		// Get the extracted path reference.
		out := GetPath(pathref, store, inj)

		return out
	}

	// Check for injections within the string.
	partialRe := regexp.MustCompile("`([^`]+)`")
	out := partialRe.ReplaceAllStringFunc(val, func(m string) string {
		ref := strings.Trim(m, "`")

		// Special escapes inside injection.
		if 3 < len(ref) {
			ref = strings.ReplaceAll(ref, "$BT", S_BT)
			ref = strings.ReplaceAll(ref, "$DS", S_DS)
		}
		if nil != inj {
			inj.Full = false
		}
		found := GetPath(ref, store, inj)

		if nil == found {
			return S_MT
		}
		switch fv := found.(type) {
		case map[string]any, []any:
			b, _ := json.Marshal(fv)
			return string(b)
		case *ListRef[any]:
			b, _ := json.Marshal(fv.List)
			return string(b)
		default:
			return _stringifyValue(found)
		}
	})

	// Also call the inj handler on the entire string, providing the
	// option for custom injection.
	if nil != inj && IsFunc(inj.Handler) {
		inj.Full = true
		result := inj.Handler(inj, out, &val, store)
		if s, ok := result.(string); ok {
			out = s
		} else {
			out = fmt.Sprint(result)
		}
	}

	return out
}

// Inject values from a data store into a node recursively, resolving
// paths against the store, or current if they are local. The modify
// argument allows custom modification of the result. The inj
// (Injection) argument is used to maintain recursive inj.
func Inject(
	val any,
	store any,
	injdefs ...*Injection,
) any {
	var inj *Injection
	if len(injdefs) > 0 {
		inj = injdefs[0]
	}
	valType := Typify(val)

	// Create inj if at root of injection. The input value is placed
	// inside a virtual parent holder to simplify edge cases.
	if inj == nil || inj.Mode == 0 {
		parent := map[string]any{
			S_DTOP: val,
		}

		newInj := &Injection{
			Mode:    M_VAL,
			Full:    false,
			KeyI:    0,
			Keys:    &ListRef[string]{List: []string{S_DTOP}},
			Key:     S_DTOP,
			Val:     val,
			Parent:  parent,
			Path:    &ListRef[string]{List: []string{S_DTOP}},
			Nodes:   &ListRef[any]{List: []any{parent}},
			Handler: injectHandler,
			Base:    S_DTOP,
			Modify:  nil,
			Errs:    GetProp(store, S_DERRS, ListRefCreate[any]()).(*ListRef[any]),
			Meta:    make(map[string]any),
			Dparent: store,
			Dpath:   []string{S_DTOP},
		}
		newInj.Meta["__d"] = 0

		if inj != nil {
			// Partial init provided (like TS injdef)
			if inj.Modify != nil {
				newInj.Modify = inj.Modify
			}
			if inj.Extra != nil {
				newInj.Extra = inj.Extra
			}
			if inj.Meta != nil {
				newInj.Meta = inj.Meta
			}
			if inj.Handler != nil {
				newInj.Handler = inj.Handler
			}
			if inj.Errs != nil {
				newInj.Errs = inj.Errs
			}
			if inj.Dparent != nil {
				newInj.Dparent = inj.Dparent
			}
			if inj.Dpath != nil {
				newInj.Dpath = inj.Dpath
			}
		}

		inj = newInj
	}

	inj.descend()

	// Descend into node
	if IsNode(val) {
		childkeys := KeysOf(val)

		// Keys are sorted alphanumerically to ensure determinism.
		// Injection transforms ($FOO) are processed *after* other keys.
		var normalKeys []string
		var transformKeys []string
		for _, k := range childkeys {
			if strings.Contains(k, S_DS) {
				transformKeys = append(transformKeys, k)
			} else {
				normalKeys = append(normalKeys, k)
			}
		}

		sort.Strings(normalKeys)
		sort.Strings(transformKeys)
		nodekeys := append(normalKeys, transformKeys...)

		nkI := 0
		for nkI < len(nodekeys) {
			nodekey := nodekeys[nkI]

			childinj := inj.child(nkI, nodekeys)
			childinj.Mode = M_KEYPRE

			// Perform the key:pre mode injection on the child key.
			preKey := _injectStr(nodekey, store, childinj)

			// The injection may modify child processing.
			nkI = childinj.KeyI
			nodekeys = childinj.Keys.List
			val = childinj.Parent

			if preKey != nil {
				childval := GetProp(val, preKey)
				childinj.Val = childval
				childinj.Mode = M_VAL

				// Perform the val mode injection on the child value.
				Inject(childval, store, childinj)

				// The injection may modify child processing.
				nkI = childinj.KeyI
				nodekeys = childinj.Keys.List
				val = childinj.Parent

				// Perform the key:post mode injection on the child key.
				childinj.Mode = M_KEYPOST
				_injectStr(nodekey, store, childinj)

				// The injection may modify child processing.
				nkI = childinj.KeyI
				nodekeys = childinj.Keys.List
				val = childinj.Parent
			}

			nkI = nkI + 1
		}

	} else if 0 < (T_string & valType) {

		// Inject paths into string scalars.
		inj.Mode = M_VAL
		strVal, ok := val.(string)
		if ok {
			val = _injectStr(strVal, store, inj)
			if val != SKIP {
				inj.setval(val)
			}
		}
	}

	// Custom modification
	if nil != inj.Modify && val != SKIP {
		mkey := inj.Key
		mparent := inj.Parent
		mval := GetProp(mparent, mkey)
		inj.Modify(
			mval,
			mkey,
			mparent,
			inj,
			store,
		)
	}

	inj.Val = val

	// Original val reference may no longer be correct.
	// This return value is only used as the top level result.
	rval := GetProp(inj.Parent, S_DTOP)

	return rval
}

// Default inject handler for transforms. If the path resolves to a function,
// call the function passing the injection inj. This is how transforms operate.
var injectHandler Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	out := val
	iscmd := IsFunc(val) && (nil == ref || strings.HasPrefix(*ref, S_DS))

	if iscmd {
		fnih, ok := val.(Injector)

		if ok {
			out = fnih(inj, val, ref, store)
		} else {
			// In Go, as a convenience, allow injection functions that have no arguments.
			fn0, ok := val.(func() any)
			if ok {
				out = fn0()
			}
		}
	} else if M_VAL == inj.Mode && inj.Full {
		// Update parent with value. Ensures references remain in node tree.
		inj.setval(val)
	}

	return out
}

// The transform_* functions are special command inject handlers (see Injector).

// Delete a key from a map or list.
var Transform_DELETE Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	inj.setval(nil)
	return nil
}

// Copy value from source data.
var Transform_COPY Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if !CheckPlacement(M_VAL, "COPY", T_any, inj) {
		return nil
	}

	out := GetProp(inj.Dparent, inj.Key)
	inj.setval(out)

	return out
}

// As a value, inject the key of the parent node.
// As a key, defined the name of the key property in the source object.
var Transform_KEY Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if inj.Mode != M_VAL {
		return nil
	}

	// Key is defined by $KEY meta property.
	keyspec := GetProp(inj.Parent, S_BKEY)
	if keyspec != nil {
		DelProp(inj.Parent, S_BKEY)
		return GetProp(inj.Dparent, keyspec)
	}

	// Key is defined within general purpose $ANNO object.
	anno := GetProp(inj.Parent, S_BANNO)
	pkey := GetProp(anno, S_KEY)
	if pkey != nil {
		return pkey
	}

	// fallback to the second-last path element
	if len(inj.Path.List) >= 2 {
		return inj.Path.List[len(inj.Path.List)-2]
	}

	return nil
}

// Store meta data about a node.  Does nothing itself, just used by
// other injectors, and is removed when called.
var Transform_META Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	DelProp(inj.Parent, S_DMETA)
	return nil
}

// Annotate node. Does nothing itself, just used by other injectors, and is removed when called.
var Transform_ANNO Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	DelProp(inj.Parent, S_BANNO)
	return nil
}

// Merge a list of objects into the current object.
// Must be a key in an object. The value is merged over the current object.
// If the value is an array, the elements are first merged using `merge`.
// If the value is the empty string, merge the top level store.
// Format: { '`$MERGE`': '`source-path`' | ['`source-paths`', ...] }
var Transform_MERGE Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if M_KEYPRE == inj.Mode {
		return inj.Key
	}

	if M_KEYPOST == inj.Mode {
		args := GetProp(inj.Parent, inj.Key)
		if S_MT == args {
			args = []any{GetProp(store, S_DTOP)}
		} else if IsList(args) {
			// do nothing
		} else {
			// wrap in array
			args = []any{args}
		}

		// Remove the $MERGE command from a parent map.
    DelProp(inj.Parent, inj.Key)

		list, ok := _asList(args)
		if !ok {
			return inj.Key
		}

		// Literals in the parent have precedence, but we still merge onto
		// the parent object, so that node tree references are not changed.
		mergeList := []any{inj.Parent}
		mergeList = append(mergeList, list...)
		mergeList = append(mergeList, Clone(inj.Parent))

		Merge(mergeList)

		return inj.Key
	}

	// Ensures $MERGE is removed from parent list.
	return nil
}


// Convert a node to a list.
// Format: ['`$EACH`', '`source-path-of-node`', child-template]
var Transform_EACH Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	ijname := "EACH"

	if !CheckPlacement(M_VAL, ijname, T_list, inj) {
		return nil
	}

	// Remove remaining keys to avoid spurious processing.
	if inj.Keys != nil && len(inj.Keys.List) > 0 {
		inj.Keys.List = inj.Keys.List[:1]
	}

	// Get arguments: ['`$EACH`', 'source-path', child-template]
	parentList := _listify(inj.Parent)
	var sliced []any
	if len(parentList) > 1 {
		sliced = parentList[1:]
	}
	args := InjectorArgs([]int{T_string, T_any}, sliced)
	if args[0] != nil {
		inj.Errs.Append("$" + ijname + ": " + args[0].(string))
		return nil
	}

	srcpath := args[1].(string)
	child := args[2]

	// Source data.
	srcstore := GetProp(store, inj.Base, store)
	src := GetPath(srcpath, srcstore, inj)
	srctype := Typify(src)

	// Create parallel data structures
	var tcur any
	var tval any

	tkey := ""
	if len(inj.Path.List) >= 2 {
		tkey = inj.Path.List[len(inj.Path.List)-2]
	}
	var target any
	if len(inj.Nodes.List) >= 2 {
		target = inj.Nodes.List[len(inj.Nodes.List)-2]
	}
	if target == nil && len(inj.Nodes.List) > 0 {
		target = inj.Nodes.List[len(inj.Nodes.List)-1]
	}

	// Create clones of the child template for each value of the current source.
	if 0 < (T_list & srctype) {
		srcList := _listify(src)
		newlist := make([]any, len(srcList))
		for i := range srcList {
			newlist[i] = Clone(child)
		}
		tval = newlist
	} else if 0 < (T_map & srctype) {
		srcItems := Items(src)
		newlist := make([]any, len(srcItems))
		for i, item := range srcItems {
			cclone := Clone(child)
			cclone = Merge([]any{
				cclone,
				map[string]any{S_BANNO: map[string]any{S_KEY: item[0]}},
			})
			newlist[i] = cclone
		}
		tval = newlist
	}

	rval := []any{}

	if tval != nil && len(_listify(tval)) > 0 {
		if src != nil {
			srcVals := make([]any, 0)
			if IsMap(src) {
				for _, item := range Items(src) {
					srcVals = append(srcVals, item[1])
				}
			} else {
				srcVals = _listify(src)
			}
			tcur = srcVals
		}

		ckey := ""
		if len(inj.Path.List) >= 2 {
			ckey = inj.Path.List[len(inj.Path.List)-2]
		}

		tpath := make([]string, len(inj.Path.List)-1)
		copy(tpath, inj.Path.List[:len(inj.Path.List)-1])

		dpath := []string{S_DTOP}
		for _, p := range strings.Split(srcpath, S_DT) {
			dpath = append(dpath, p)
		}
		dpath = append(dpath, "$:"+ckey)

		// Parent structure.
		tcur = map[string]any{ckey: tcur}

		if len(tpath) > 1 {
			pkey := S_DTOP
			if len(inj.Path.List) >= 3 {
				pkey = inj.Path.List[len(inj.Path.List)-3]
			}
			tcur = map[string]any{pkey: tcur}
			dpath = append(dpath, "$:"+pkey)
		}

		tinj := inj.child(0, []string{ckey})
		tinj.Path = &ListRef[string]{List: tpath}

		tnodeslist := make([]any, 1)
		copy(tnodeslist, inj.Nodes.List[len(inj.Nodes.List)-1:])
		tinj.Nodes = &ListRef[any]{List: tnodeslist}

		tinj.Parent = tinj.Nodes.List[len(tinj.Nodes.List)-1]
		SetProp(tinj.Parent, ckey, tval)

		tinj.Val = tval
		tinj.Dpath = dpath
		tinj.Dparent = tcur

		Inject(tval, store, tinj)
		rval = _listify(tinj.Val)
	}

	SetProp(target, tkey, rval)

	// Prevent callee from damaging first list entry (since we are in val mode).
	if len(rval) > 0 {
		return rval[0]
	}
	return nil
}


// transform_PACK => `$PACK`
var Transform_PACK Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	ijname := "EACH" // TS uses EACH for checkPlacement name

	if !CheckPlacement(M_KEYPRE, ijname, T_map, inj) {
		return nil
	}

	// Get arguments.
	args := GetProp(inj.Parent, inj.Key)
	argsList := _listify(args)
	injArgs := InjectorArgs([]int{T_string, T_any}, argsList)
	if injArgs[0] != nil {
		inj.Errs.Append("$" + ijname + ": " + injArgs[0].(string))
		return nil
	}

	srcpath := injArgs[1].(string)
	origchildspec := injArgs[2]

	// Find key and target node.
	tkey := ""
	if len(inj.Path.List) >= 2 {
		tkey = inj.Path.List[len(inj.Path.List)-2]
	}
	pathsize := len(inj.Path.List)
	var target any
	if pathsize >= 2 {
		target = inj.Nodes.List[pathsize-2]
	}
	if target == nil {
		target = inj.Nodes.List[pathsize-1]
	}

	// Source data
	srcstore := GetProp(store, inj.Base, store)
	src := GetPath(srcpath, srcstore, inj)

	// Prepare source as a list.
	if !IsList(src) {
		if IsMap(src) {
			srcItems := Items(src)
			srcList := make([]any, len(srcItems))
			for i, item := range srcItems {
				node := item[1]
				if IsMap(node) {
					SetProp(node, S_BANNO, map[string]any{S_KEY: item[0]})
				}
				srcList[i] = node
			}
			src = srcList
		} else {
			return nil
		}
	}

	if src == nil {
		return nil
	}

	// Get keypath.
	keypath := GetProp(origchildspec, S_BKEY)
	childspec := DelProp(origchildspec, S_BKEY)

	child := GetProp(childspec, S_BVAL, childspec)

	// Build parallel target object.
	tval := map[string]any{}
	srclist := _listify(src)

	// Helper to resolve key for a src item at given index
	resolveKey := func(srcItem any, idx int) string {
		if keypath == nil {
			return strconv.Itoa(idx)
		}
		keypathStr, isStr := keypath.(string)
		if !isStr {
			return ""
		}
		if strings.HasPrefix(keypathStr, "`") {
			keyStore := Merge([]any{map[string]any{}, store, map[string]any{S_DTOP: srcItem}})
			keyResult := Inject(keypathStr, keyStore)
			if ks, ok := keyResult.(string); ok {
				return ks
			}
		} else {
			kval := GetPath(keypathStr, srcItem, inj)
			if ks, ok := kval.(string); ok {
				return ks
			}
		}
		return ""
	}

	for i, srcItem := range srclist {
		srcnode := srcItem
		key := resolveKey(srcnode, i)

		if key == "" {
			continue
		}

		tchild := Clone(child)
		tval[key] = tchild

		anno := GetProp(srcnode, S_BANNO)
		if anno == nil {
			if tchildMap, ok := tchild.(map[string]any); ok {
				delete(tchildMap, S_BANNO)
			}
		} else {
			if IsMap(tchild) {
				SetProp(tchild, S_BANNO, anno)
			}
		}
	}

	rval := map[string]any{}

	if !IsEmpty(tval) {
		// Build parallel source object
		tsrc := map[string]any{}
		for i, srcItem := range srclist {
			kn := resolveKey(srcItem, i)
			if kn != "" {
				tsrc[kn] = srcItem
			}
		}

		tpath := make([]string, len(inj.Path.List)-1)
		copy(tpath, inj.Path.List[:len(inj.Path.List)-1])

		ckey := ""
		if len(inj.Path.List) >= 2 {
			ckey = inj.Path.List[len(inj.Path.List)-2]
		}

		dpath := []string{S_DTOP}
		for _, p := range strings.Split(srcpath, S_DT) {
			dpath = append(dpath, p)
		}
		dpath = append(dpath, "$:"+ckey)

		tcur := map[string]any{ckey: tsrc}

		if len(tpath) > 1 {
			pkey := S_DTOP
			if len(inj.Path.List) >= 3 {
				pkey = inj.Path.List[len(inj.Path.List)-3]
			}
			tcur = map[string]any{pkey: tcur}
			dpath = append(dpath, "$:"+pkey)
		}

		tinj := inj.child(0, []string{ckey})
		tinj.Path = &ListRef[string]{List: tpath}

		tnodeslist := make([]any, 1)
		copy(tnodeslist, inj.Nodes.List[len(inj.Nodes.List)-1:])
		tinj.Nodes = &ListRef[any]{List: tnodeslist}

		tinj.Parent = tinj.Nodes.List[len(tinj.Nodes.List)-1]
		tinj.Val = tval

		tinj.Dpath = dpath
		tinj.Dparent = tcur

		Inject(tval, store, tinj)
		if r, ok := tinj.Val.(map[string]any); ok {
			rval = r
		}
	}

	SetProp(target, tkey, rval)

	// Drop transform key.
	return nil
}

// transform_APPLY => `$APPLY`
// Reference original spec (enables recursive transformations).
// Format: ['`$REF`', '`spec-path`']
var Transform_REF Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if inj.Mode != M_VAL {
		return nil
	}

	// Get arguments: ['`$REF`', 'ref-path'].
	refpath := GetProp(inj.Parent, 1)
	inj.KeyI = len(inj.Keys.List)

	// Spec reference.
	specFn := GetProp(store, S_DSPEC)
	if specFn == nil {
		return nil
	}
	var spec any
	if fn, ok := specFn.(func() any); ok {
		spec = fn()
	} else {
		return nil
	}

	dpath := make([]string, 0)
	if len(inj.Path.List) > 1 {
		dpath = append(dpath, inj.Path.List[1:]...)
	}
	refResult := GetPath(refpath, spec, &Injection{
		Dpath:   dpath,
		Dparent: GetPath(dpath, spec),
	})

	hasSubRef := false
	if IsNode(refResult) {
		Walk(refResult, func(k *string, v any, parent any, path []string) any {
			if s, ok := v.(string); ok && s == "`$REF`" {
				hasSubRef = true
			}
			return v
		})
	}

	tref := Clone(refResult)

	cpath := make([]string, 0)
	if len(inj.Path.List) > 3 {
		cpath = append(cpath, inj.Path.List[:len(inj.Path.List)-3]...)
	}
	tpath := make([]string, 0)
	if len(inj.Path.List) >= 1 {
		tpath = append(tpath, inj.Path.List[:len(inj.Path.List)]...)
	}
	tpath = tpath[:len(tpath)-1]

	tcur := GetPath(cpath, store)
	tval := GetPath(tpath, store)

	var rval any

	if !hasSubRef || tval != nil {
		lastPath := S_DTOP
		if len(tpath) > 0 {
			lastPath = tpath[len(tpath)-1]
		}
		tinj := inj.child(0, []string{lastPath})
		tinj.Path = &ListRef[string]{List: tpath}

		// TS: tinj.nodes = slice(inj.nodes, -1) → nodes[0:len-1] (all except last)
		nodesLen := len(inj.Nodes.List)
		if nodesLen > 1 {
			tnodeslist := make([]any, nodesLen-1)
			copy(tnodeslist, inj.Nodes.List[:nodesLen-1])
			tinj.Nodes = &ListRef[any]{List: tnodeslist}
		} else {
			tinj.Nodes = &ListRef[any]{List: []any{}}
		}

		// TS: tinj.parent = getelem(nodes, -2)
		if nodesLen >= 2 {
			tinj.Parent = inj.Nodes.List[nodesLen-2]
		}
		tinj.Val = tref

		tinj.Dpath = cpath
		tinj.Dparent = tcur

		Inject(tref, store, tinj)
		rval = tinj.Val
	}

	grandparent := inj.setval(rval, 2)

	if IsList(grandparent) && inj.Prior != nil {
		inj.Prior.KeyI--
	}

	return val
}

var Transform_APPLY Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	ijname := "APPLY"

	// Skip remaining keys
	if inj.Keys != nil && len(inj.Keys.List) > 0 {
		inj.Keys.List = inj.Keys.List[:1]
	}

	if !CheckPlacement(M_VAL, ijname, T_list, inj) {
		return nil
	}

	parentList := _listify(inj.Parent)
	var sliced []any
	if len(parentList) > 1 {
		sliced = parentList[1:]
	}
	args := InjectorArgs([]int{T_function, T_any}, sliced)

	tkey := ""
	if len(inj.Path.List) >= 2 {
		tkey = inj.Path.List[len(inj.Path.List)-2]
	}
	var target any
	if len(inj.Nodes.List) >= 2 {
		target = inj.Nodes.List[len(inj.Nodes.List)-2]
	}

	if args[0] != nil {
		inj.Errs.Append("$" + ijname + ": " + args[0].(string))
		if target != nil {
			DelProp(target, tkey)
		}
		return nil
	}

	applyFn := args[1]
	child := args[2]

	// Resolve child via injection
	cinj := InjectChild(child, store, inj)
	resolved := cinj.Val

	// Call the apply function
	fn := reflect.ValueOf(applyFn)
	fnType := fn.Type()

	var out any
	switch fnType.NumIn() {
	case 1:
		results := fn.Call([]reflect.Value{reflect.ValueOf(resolved)})
		if len(results) > 0 {
			out = results[0].Interface()
		}
	case 3:
		results := fn.Call([]reflect.Value{
			reflect.ValueOf(resolved),
			reflect.ValueOf(store),
			reflect.ValueOf(cinj),
		})
		if len(results) > 0 {
			out = results[0].Interface()
		}
	default:
		results := fn.Call([]reflect.Value{reflect.ValueOf(resolved)})
		if len(results) > 0 {
			out = results[0].Interface()
		}
	}

	// Set on parent output
	if target != nil {
		SetProp(target, tkey, out)
	}

	return out
}


// transform_FORMAT => `$FORMAT`
// injectChild resolves a child value via injection, going up the injection chain
// to get the correct data context.
func InjectChild(child any, store any, inj *Injection) *Injection {
	cinj := inj

	if inj.Prior != nil {
		if inj.Prior.Prior != nil {
			cinj = inj.Prior.Prior.child(inj.Prior.KeyI, inj.Prior.Keys.List)
			cinj.Val = child
			SetProp(cinj.Parent, inj.Prior.Key, child)
		} else {
			cinj = inj.Prior.child(inj.KeyI, inj.Keys.List)
			cinj.Val = child
			SetProp(cinj.Parent, inj.Key, child)
		}
	}

	Inject(child, store, cinj)

	return cinj
}

var Transform_FORMAT Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	// Remove remaining keys to avoid spurious processing.
	if inj.Keys != nil && len(inj.Keys.List) > 0 {
		inj.Keys.List = inj.Keys.List[:1]
	}

	if inj.Mode != M_VAL {
		return nil
	}

	// Get arguments: ['`$FORMAT`', 'name', child].
	name := GetProp(inj.Parent, 1)
	child := GetProp(inj.Parent, 2)

	// Resolve child via injection using injectChild
	cinj := InjectChild(child, store, inj)
	resolved := cinj.Val

	tkey := ""
	if len(inj.Path.List) >= 2 {
		tkey = inj.Path.List[len(inj.Path.List)-2]
	}
	var target any
	if len(inj.Nodes.List) >= 2 {
		target = inj.Nodes.List[len(inj.Nodes.List)-2]
	}
	if target == nil && len(inj.Nodes.List) > 0 {
		target = inj.Nodes.List[len(inj.Nodes.List)-1]
	}

	// Convert nil to "null" string for formatting purposes
	_fmtStr := func(v any) string {
		if v == nil {
			return "null"
		}
		return fmt.Sprint(v)
	}

	// Get formatter
	var formatter func(key *string, val any, parent any, path []string) any

	if IsFunc(name) {
		fn := reflect.ValueOf(name)
		formatter = func(key *string, val any, parent any, path []string) any {
			results := fn.Call([]reflect.Value{
				reflect.ValueOf(key),
				reflect.ValueOf(val),
				reflect.ValueOf(parent),
				reflect.ValueOf(path),
			})
			if len(results) > 0 {
				return results[0].Interface()
			}
			return val
		}
	} else if nameStr, ok := name.(string); ok {
		switch nameStr {
		case "upper":
			formatter = func(_ *string, val any, _ any, _ []string) any {
				if IsNode(val) {
					return val
				}
				return strings.ToUpper(_fmtStr(val))
			}
		case "lower":
			formatter = func(_ *string, val any, _ any, _ []string) any {
				if IsNode(val) {
					return val
				}
				return strings.ToLower(_fmtStr(val))
			}
		case "string":
			formatter = func(_ *string, val any, _ any, _ []string) any {
				if IsNode(val) {
					return val
				}
				return _fmtStr(val)
			}
		case "number":
			formatter = func(_ *string, val any, _ any, _ []string) any {
				if IsNode(val) {
					return val
				}
				switch v := val.(type) {
				case int:
					return v
				case float64:
					return v
				case string:
					n, err := strconv.ParseFloat(v, 64)
					if err != nil {
						return 0
					}
					if n == float64(int(n)) {
						return int(n)
					}
					return n
				default:
					return 0
				}
			}
		case "integer":
			formatter = func(_ *string, val any, _ any, _ []string) any {
				if IsNode(val) {
					return val
				}
				switch v := val.(type) {
				case int:
					return v
				case float64:
					return int(v)
				case string:
					n, err := strconv.ParseFloat(v, 64)
					if err != nil {
						return 0
					}
					return int(n)
				default:
					return 0
				}
			}
		case "concat":
			formatter = func(key *string, val any, _ any, _ []string) any {
				if key == nil && IsList(val) {
					parts := []string{}
					list := _listify(val)
					for _, v := range list {
						if IsNode(v) {
							parts = append(parts, "")
						} else {
							parts = append(parts, _fmtStr(v))
						}
					}
					return strings.Join(parts, "")
				}
				return val
			}
		case "identity":
			formatter = func(_ *string, val any, _ any, _ []string) any {
				return val
			}
		default:
			inj.Errs.Append("$FORMAT: unknown format: " + nameStr + ".")
			if target != nil {
				DelProp(target, tkey)
			}
			return nil
		}
	} else {
		inj.Errs.Append("$FORMAT: unknown format: " + Stringify(name) + ".")
		if target != nil {
			DelProp(target, tkey)
		}
		return nil
	}

	var out any
	out = Walk(resolved, formatter)

	// Set on parent output
	if target != nil {
		SetProp(target, tkey, out)
	}

	return out
}


// ---------------------------------------------------------------------
// Transform function: top-level

func Transform(
	data any, // source data
	spec any, // transform specification
	injdefs ...*Injection,
) any {
	if len(injdefs) > 0 && injdefs[0] != nil {
		injdef := injdefs[0]
		return TransformModifyHandler(
			data,
			spec,
			injdef.Extra,
			injdef.Modify,
			injdef.Handler,
			injdef.Errs,
			injdef.Meta,
		)
	}
	return TransformModify(data, spec, nil, nil)
}

// TransformModifyHandler is like TransformModify but allows a custom handler and injection inj.
func TransformModifyHandler(
	data any,
	spec any,
	extra any,
	modify Modify,
	handler Injector,
	errs *ListRef[any],
	meta map[string]any,
) any {
	// Clone and wrap
	wrapFlags := map[string]bool{"wrap": true}
	origspec := spec
	spec = CloneFlags(spec, wrapFlags)

	// Split extra transforms from extra data
	extraTransforms := map[string]any{}
	extraData := map[string]any{}

	if extra != nil {
		pairs := Items(extra)
		for _, kv := range pairs {
			k, _ := kv[0].(string)
			v := kv[1]
			if strings.HasPrefix(k, S_DS) {
				extraTransforms[k] = v
			} else {
				extraData[k] = v
			}
		}
	}

	if extraData == nil {
		extraData = map[string]any{}
	}

	var dataClone any
	if data == nil {
		dataClone = nil
	} else {
		dataClone = Merge([]any{
			CloneFlags(extraData, wrapFlags),
			CloneFlags(data, wrapFlags),
		})
	}

	// Save original spec for $REF
	_ = origspec

	store := map[string]any{
		S_DTOP: dataClone,
		S_DSPEC: func() any { return origspec },
		"$BT": func() any { return S_BT },
		"$DS": func() any { return S_DS },
		"$WHEN": func() any {
			return time.Now().UTC().Format(time.RFC3339)
		},
		"$DELETE": Transform_DELETE,
		"$COPY":   Transform_COPY,
		"$KEY":    Transform_KEY,
		"$META":   Transform_META,
		"$ANNO":   Transform_ANNO,
		"$MERGE":  Transform_MERGE,
		"$EACH":   Transform_EACH,
		"$PACK":   Transform_PACK,
		"$REF":    Transform_REF,
		"$APPLY":  Transform_APPLY,
		"$FORMAT": Transform_FORMAT,
	}

	for k, v := range extraTransforms {
		store[k] = v
	}

	if errs == nil {
		errs = ListRefCreate[any]()
	}
	store[S_DERRS] = errs

	// Create injection inj with handler
	injState := &Injection{
		Modify:  modify,
		Handler: handler,
		Errs:    errs,
		Meta:    meta,
	}

	out := Inject(spec, store, injState)
	out = CloneFlags(out, map[string]bool{"unwrap": true})
	return out
}

// transformModifyCore is the internal implementation that collects errors.
func transformModifyCore(
	data any,
	spec any,
	extra any,
	modify Modify,
) (any, *ListRef[any]) {

	// Clone and wrap: clone the structures and convert bare lists to ListRefs
	// for reference stability, in a single pass.
	wrapFlags := map[string]bool{"wrap": true}

	// Save original spec for $REF as a separate wrapped clone (not modified by injection)
	origspec := CloneFlags(spec, wrapFlags)
	spec = CloneFlags(spec, wrapFlags)

	// Split extra transforms from extra data
	extraTransforms := map[string]any{}
	extraData := map[string]any{}

	if extra != nil {
		pairs := Items(extra)
		for _, kv := range pairs {
			k, _ := kv[0].(string)
			v := kv[1]
			if strings.HasPrefix(k, S_DS) {
				extraTransforms[k] = v
			} else {
				extraData[k] = v
			}
		}
	}

	// Create empty maps if nil
	if extraData == nil {
		extraData = map[string]any{}
	}
	if data == nil {
		data = map[string]any{}
	}

	// Merge extraData + data, clone+wrap in one pass
	dataClone := Merge([]any{
		CloneFlags(extraData, wrapFlags),
		CloneFlags(data, wrapFlags),
	})

	// Collect errors from transform operations
	errs := ListRefCreate[any]()

	// The injection store with transform functions
	store := map[string]any{
		// Merged data is at $TOP
		S_DTOP: dataClone,

		// Reference to original spec for $REF
		S_DSPEC: func() any { return origspec },

		// Handy escapes
		"$BT": func() any { return S_BT },
		"$DS": func() any { return S_DS },

		// Insert current date/time
		"$WHEN": func() any {
			return time.Now().UTC().Format(time.RFC3339)
		},

		// Built-in transform functions
		"$DELETE": Transform_DELETE,
		"$COPY":   Transform_COPY,
		"$KEY":    Transform_KEY,
		"$META":   Transform_META,
		"$ANNO":   Transform_ANNO,
		"$MERGE":  Transform_MERGE,
		"$EACH":   Transform_EACH,
		"$PACK":   Transform_PACK,
		"$REF":    Transform_REF,
		"$APPLY":  Transform_APPLY,
		"$FORMAT": Transform_FORMAT,
	}

	// Add any extra transforms
	for k, v := range extraTransforms {
		store[k] = v
	}

	// Pass errs via injection inj to avoid Merge converting ListRef to []any
	injState := &Injection{
		Modify: modify,
		Errs:   errs,
	}

	out := Inject(spec, store, injState)

	// Clone output, unwrapping ListRefs back to bare lists.
	out = CloneFlags(out, map[string]bool{"unwrap": true})

	return out, errs
}

func TransformModify(
	data any, // source data
	spec any, // transform specification
	extra any, // extra store
	modify Modify, // optional modify
) any {
	out, _ := transformModifyCore(data, spec, extra, modify)
	return out
}

// TransformCollect is like Transform but also returns collected error strings.
func TransformCollect(
	data any,
	spec any,
) (any, []string) {
	out, errs := transformModifyCore(data, spec, nil, nil)
	errStrs := make([]string, 0, len(errs.List))
	for _, e := range errs.List {
		if s, ok := e.(string); ok {
			errStrs = append(errStrs, s)
		}
	}
	return out, errStrs
}

var validate_STRING Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	out := GetProp(inj.Dparent, inj.Key)

	t := Typify(out)
	if 0 == (T_string & t) {
		msg := _invalidTypeMsg(inj.Path.List, S_string, Typename(t), out)
		inj.Errs.Append(msg)
		return nil
	}

	if S_MT == out.(string) {
		msg := "Empty string at " + Pathify(inj.Path.List, 1)
		inj.Errs.Append(msg)
		return nil
	}

	return out
}

var validate_NUMBER Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	out := GetProp(inj.Dparent, inj.Key)

	t := Typify(out)
	if 0 == (T_number & t) {
		msg := _invalidTypeMsg(inj.Path.List, S_number, Typename(t), out)
		inj.Errs.Append(msg)
		return nil
	}

	return out
}

var validate_BOOLEAN Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	out := GetProp(inj.Dparent, inj.Key)

	t := Typify(out)
	if 0 == (T_boolean & t) {
		msg := _invalidTypeMsg(inj.Path.List, S_boolean, Typename(t), out)
		inj.Errs.Append(msg)
		return nil
	}

	return out
}

var validate_OBJECT Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	out := GetProp(inj.Dparent, inj.Key)

	t := Typify(out)

	if 0 == (T_map & t) {
		msg := _invalidTypeMsg(inj.Path.List, S_object, Typename(t), out)
		inj.Errs.Append(msg)

    return nil
	}

	return out
}

var validate_ARRAY Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	out := GetProp(inj.Dparent, inj.Key)

	t := Typify(out)
	if 0 == (T_list & t) {
		msg := _invalidTypeMsg(inj.Path.List, S_array, Typename(t), out)
		inj.Errs.Append(msg)
		return nil
	}

	return out
}

var validate_FUNCTION Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	out := GetProp(inj.Dparent, inj.Key)

	t := Typify(out)
	if 0 == (T_function & t) {
		msg := _invalidTypeMsg(inj.Path.List, S_function, Typename(t), out)
		inj.Errs.Append(msg)
		return nil
	}

	return out
}

var validate_ANY Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	return GetProp(inj.Dparent, inj.Key)
}

// Generic type validator: handles $INTEGER, $DECIMAL, $NULL, $NIL, $MAP, $LIST, $INSTANCE
var validate_TYPE Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	if ref == nil {
		return nil
	}

	tname := strings.ToLower((*ref)[1:]) // e.g. "$DECIMAL" → "decimal"

	// Find the type bit from the TYPENAME array
	var typev int
	for i, name := range TYPENAME {
		if name == tname {
			typev = 1 << (31 - i)
			break
		}
	}

	out := GetProp(inj.Dparent, inj.Key)
	t := Typify(out)

	// In Go, nil represents both null and noval (undefined).
	// $NIL should match nil values, and $NULL should also match nil.
	if tname == "nil" && out == nil {
		return out
	}
	if tname == "null" && out == nil {
		return out
	}

	if 0 == (t & typev) {
		msg := _invalidTypeMsg(inj.Path.List, tname, Typename(t), out)
		inj.Errs.Append(msg)
		return nil
	}

	return out
}

var validate_CHILD Injector = func(
	inj *Injection,
	_val any,
	ref *string,
	store any,
) any {
	// Map syntax
	if inj.Mode == M_KEYPRE {
		child := GetProp(inj.Parent, inj.Key)

		pkey := inj.Path.List[len(inj.Path.List)-2]
		tval := GetProp(inj.Dparent, pkey)

		if nil == tval {
			tval = map[string]any{}

		} else if !IsMap(tval) {
			inj.Errs.Append(
				_invalidTypeMsg(
					inj.Path.List[:len(inj.Path.List)-1],
					S_object,
					Typename(Typify(tval)),
					tval,
				))
			return nil
		}

		// For each key in tval, clone the child into parent
		ckeys := KeysOf(tval)
		for _, ckey := range ckeys {
			SetProp(inj.Parent, ckey, Clone(child))
			inj.Keys.Append(ckey)
		}

		DelProp(inj.Parent, inj.Key)

		return nil
	}

	// List syntax
	if inj.Mode == M_VAL {

		// We expect 'parent' to be a slice of any, like ["`$CHILD`", childTemplate].
		if !IsList(inj.Parent) {
			inj.Errs.Append("Invalid $CHILD as value")
			return nil
		}

		child := GetProp(inj.Parent, 1)
		dparent := inj.Dparent

		// If dparent is nil => empty list default
		if nil == dparent {
			if lr, ok := inj.Parent.(*ListRef[any]); ok {
				lr.List = []any{}
			} else {
				inj.Parent = []any{}
			}
			return nil
		}

		// If dparent is not a list => error
		if !IsList(dparent) {
			inj.Errs.Append(
				_invalidTypeMsg(
					inj.Path.List[:len(inj.Path.List)-1],
					S_array,
					Typename(Typify(dparent)),
					dparent,
				))
			parentList := _listify(inj.Parent)
			inj.KeyI = len(parentList)
			return dparent
		}

		// Otherwise, dparent is a list => clone child for each element
		currentList := _listify(dparent)
		length := len(currentList)

		// Make a new slice to hold the child clones, sized to length
		newParent := make([]any, length)
		for i := 0; i < length; i++ {
			newParent[i] = Clone(child)
		}

		// Replace parent with the new slice
		if lr, ok := inj.Parent.(*ListRef[any]); ok {
			lr.List = newParent
		} else {
			inj.Parent = newParent
		}

		inj.KeyI = 0

		out := GetProp(dparent, 0)
		return out
	}

	return nil
}

// Forward declaration for validate_ONE
var validate_ONE Injector

// Forward declaration for validate_EXACT
var validate_EXACT Injector

// Implementation will be set after Validate is defined
func init_validate_ONE() {
	validate_ONE = func(
		inj *Injection,
		_val any,
		ref *string,
		store any,
	) any {
		// Only operate in "val mode" (list mode).
		if inj.Mode == M_VAL {
			// Validate that parent is a list and we're at the first element
			if !IsList(inj.Parent) || inj.KeyI != 0 {
				inj.Errs.Append("The $ONE validator at field " +
					Pathify(inj.Path.List, 1, 1) +
					" must be the first element of an array.")
				return nil
			}

			// Once we handle `$ONE`, we skip further iteration by setting KeyI to keys.length
			inj.KeyI = len(inj.Keys.List)

			// The parent is assumed to be a slice: ["`$ONE`", alt0, alt1, ...].
			parentSlice, ok := _asList(inj.Parent)
			if !ok {
				return nil
			}

			// Get grandparent and grandkey to replace the structure
			grandparent := inj.Nodes.List[len(inj.Nodes.List)-2]
			grandkey := inj.Path.List[len(inj.Path.List)-2]

			// Clean up structure by replacing [$ONE, ...] with current value
			SetProp(grandparent, grandkey, inj.Dparent)
      inj.Parent = inj.Dparent

			// Adjust the path
			inj.Path.List = inj.Path.List[:len(inj.Path.List)-1]
			inj.Key = inj.Path.List[len(inj.Path.List)-1]

			// The shape alternatives are everything after the first element.
			tvals := parentSlice[1:] // alt0, alt1, ...

			// Ensure we have at least one alternative
			if len(tvals) == 0 {
				inj.Errs.Append("The $ONE validator at field " +
					Pathify(inj.Path.List, 1, 1) +
					" must have at least one argument.")
				return nil
			}

			// Try each alternative shape
			for _, tval := range tvals {
				// Collect errors in a temporary slice
				var terrs = ListRefCreate[any]()

				// Create a new store for validation
				vstore := Clone(store).(map[string]any)
				vstore["$TOP"] = inj.Dparent

				// Attempt validation of data with shape `tval`
				vcurrent, err := Validate(inj.Dparent, tval, &Injection{Extra: vstore, Errs: terrs})

				// Update the value in the grandparent
				SetProp(grandparent, grandkey, vcurrent)

				// If no errors, we found a match
				if err == nil && len(terrs.List) == 0 {
					return nil
				}
			}

			// If we get here, there was no match
			mapped := make([]string, len(tvals))
			for i, v := range tvals {
				mapped[i] = Stringify(v)
			}

			joined := strings.Join(mapped, ", ")

			re := regexp.MustCompile("`\\$([A-Z]+)`")
			valdesc := re.ReplaceAllStringFunc(joined, func(match string) string {
				submatches := re.FindStringSubmatch(match)
				if len(submatches) == 2 {
					return strings.ToLower(submatches[1])
				}
				return match
			})

			prefix := ""
			if len(tvals) > 1 {
				prefix = "one of "
			}

			msg := _invalidTypeMsg(
				inj.Path.List,
				prefix+valdesc,
				Typename(Typify(inj.Dparent)),
				inj.Dparent,
				"V0210",
			)
			inj.Errs.Append(msg)
		}

		return nil
	}
}

func init_validate_EXACT() {
	validate_EXACT = func(
		inj *Injection,
		_val any,
		ref *string,
		_store any,
	) any {
		// Only operate in "val mode" (list mode).
		if inj.Mode == M_VAL {
			// Validate that parent is a list and we're at the first element
			if !IsList(inj.Parent) || inj.KeyI != 0 {
				inj.Errs.Append("The $EXACT validator at field " +
					Pathify(inj.Path.List, 1, 1) +
					" must be the first element of an array.")
				return nil
			}

			// Once we handle `$EXACT`, we skip further iteration by setting KeyI to keys.length
			inj.KeyI = len(inj.Keys.List)

			// The parent is assumed to be a slice: ["`$EXACT`", alt0, alt1, ...].
			parentSlice, ok := _asList(inj.Parent)
			if !ok {
				return nil
			}

			// Get grandparent and grandkey to replace the structure
			grandparent := inj.Nodes.List[len(inj.Nodes.List)-2]
			grandkey := inj.Path.List[len(inj.Path.List)-2]

			// Clean up structure by replacing [$EXACT, ...] with current value
			SetProp(grandparent, grandkey, inj.Dparent)
      inj.Parent = inj.Dparent

			// Adjust the path
			inj.Path.List = inj.Path.List[:len(inj.Path.List)-1]
			inj.Key = inj.Path.List[len(inj.Path.List)-1]

			// The exact values to match are everything after the first element.
			tvals := parentSlice[1:] // alt0, alt1, ...

			// Ensure we have at least one alternative
			if len(tvals) == 0 {
				inj.Errs.Append("The $EXACT validator at field " +
					Pathify(inj.Path.List, 1, 1) +
					" must have at least one argument.")
				return nil
			}

			// See if we can find an exact value match
			var currentStr *string
			for _, tval := range tvals {
        exactMatch := false

        if !exactMatch {
          // Unwrap ListRefs for comparison since data and spec may have
          // different wrapping levels.
          unwrapFlags := map[string]bool{"unwrap": true}
          utval := CloneFlags(tval, unwrapFlags)
          ucurrent := CloneFlags(inj.Dparent, unwrapFlags)
          exactMatch = reflect.DeepEqual(utval, ucurrent)
        }
        
				if !exactMatch && IsNode(tval) {
					if nil == currentStr {
						tmpstr := Stringify(inj.Dparent)
            currentStr = &tmpstr
					}
					tvalStr := Stringify(tval)
					exactMatch = tvalStr == *currentStr
				}

				if exactMatch {
					return nil
				}
			}

			// If we get here, there was no match
			mapped := make([]string, len(tvals))
			for i, v := range tvals {
				mapped[i] = Stringify(v)
			}

			joined := strings.Join(mapped, ", ")

			re := regexp.MustCompile("`\\$([A-Z]+)`")
			valdesc := re.ReplaceAllStringFunc(joined, func(match string) string {
				submatches := re.FindStringSubmatch(match)
				if len(submatches) == 2 {
					return strings.ToLower(submatches[1])
				}
				return match
			})

			prefix := ""
			if len(inj.Path.List) <= 1 {
				prefix = "value "
			}

			oneOf := ""
			if len(tvals) > 1 {
				oneOf = "one of "
			}

			msg := _invalidTypeMsg(
				inj.Path.List,
				prefix+"exactly equal to "+oneOf+valdesc,
				Typename(Typify(inj.Dparent)),
				inj.Dparent,
				"V0110",
			)
			inj.Errs.Append(msg)
		} else {
			DelProp(inj.Parent, inj.Key)
		}

		return nil
	}
}

func makeValidation(exact bool) Modify {
	return func(
		val any,
		key any,
		parent any,
		inj *Injection,
		_store any,
	) {
		if inj == nil {
			return
		}

		if val == SKIP {
			return
		}

		// Current val to verify — use dparent from injection inj.
		cval := GetProp(inj.Dparent, key)
		if !exact && cval == nil {
			return
		}

		pval := GetProp(parent, key)
		ptype := Typify(pval)

		// Delete any special commands remaining.
		if 0 < (T_string & ptype) && pval != nil {
			if strVal, ok := pval.(string); ok && strings.Contains(strVal, S_DS) {
				return
			}
		}

		ctype := Typify(cval)

		// Type mismatch.
		if ptype != ctype && pval != nil {
			inj.Errs.Append(_invalidTypeMsg(inj.Path.List, Typename(ptype), Typename(ctype), cval))
			return
		}

		if IsMap(cval) {
			if !IsMap(val) {
				var errType string
				if IsList(val) {
					errType = S_array
				} else {
					errType = Typename(ptype)
				}
				inj.Errs.Append(_invalidTypeMsg(inj.Path.List, errType, Typename(ctype), cval))
				return
			}

			ckeys := KeysOf(cval)
			pkeys := KeysOf(pval)

			// Empty spec object {} means object can be open (any keys).
			if len(pkeys) > 0 && GetProp(pval, "`$OPEN`") != true {
				badkeys := []string{}
				for _, ckey := range ckeys {
					if !HasKey(val, ckey) {
						badkeys = append(badkeys, ckey)
					}
				}

				// Closed object, so reject extra keys not in shape.
				if len(badkeys) > 0 {
					inj.Errs.Append("Unexpected keys at field " + Pathify(inj.Path.List, 1) +
						": " + strings.Join(badkeys, ", "))
				}
			} else {
				// Object is open, so merge in extra keys.
				Merge([]any{pval, cval})
				if IsNode(pval) {
					DelProp(pval, "`$OPEN`")
				}
			}
		} else if IsList(cval) {
			if !IsList(val) {
				inj.Errs.Append(_invalidTypeMsg(inj.Path.List, Typename(ptype), Typename(ctype), cval))
			}
		} else if exact {
			// Select needs exact matches for scalar values.
			if cval != pval {
				pathmsg := ""
				if len(inj.Path.List) > 1 {
					pathmsg = "at field " + Pathify(inj.Path.List, 1) + ": "
				}
				inj.Errs.Append("Value " + pathmsg + fmt.Sprintf("%v", cval) +
					" should equal " + fmt.Sprintf("%v", pval) + ".")
			} else if pval == nil {
				// Both nil: in Go, nil represents both null and undefined.
				// For exact matching (Select), verify the key actually exists in the data.
				keyExists := false
				if m, ok := inj.Dparent.(map[string]any); ok {
					if keyStr, ok := key.(string); ok {
						_, keyExists = m[keyStr]
					}
				}
				if !keyExists {
					pathmsg := ""
					if len(inj.Path.List) > 1 {
						pathmsg = "at field " + Pathify(inj.Path.List, 1) + ": "
					}
					inj.Errs.Append("Value " + pathmsg + "undefined" +
						" should equal " + fmt.Sprintf("%v", pval) + ".")
				}
			}
		} else {
			// Spec value was a default, copy over data
			SetProp(parent, key, cval)
		}

		return
	}
}

// Default validation modify (non-exact mode).
var validation Modify = makeValidation(false)

// _validatehandler processes meta path operators in validation.
var _validatehandler Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	out := val

	refStr := ""
	if ref != nil {
		refStr = *ref
	}
	m := reMetaPath.FindStringSubmatch(refStr)
	ismetapath := m != nil

	if ismetapath {
		if m[2] == "=" {
			inj.setval([]any{S_BEXACT, val})
		} else {
			inj.setval(val)
		}
		inj.KeyI = -1
		out = SKIP
	} else {
		out = injectHandler(inj, val, ref, store)
	}

	return out
}

func Validate(
	data any, // The input data
	spec any, // The shape specification
	injdefs ...*Injection,
) (any, error) {
	var extra map[string]any
	var collecterrs *ListRef[any]
	if len(injdefs) > 0 && injdefs[0] != nil {
		if e, ok := injdefs[0].Extra.(map[string]any); ok {
			extra = e
		}
		collecterrs = injdefs[0].Errs
	}

	// Use the provided error collection or create a new one
	errs := collecterrs
	if nil == errs {
		errs = ListRefCreate[any]()
	}

  
	// Initialize validate_ONE if not already initialized.
	// This avoids a circular reference error, validate_ONE calls Validate.
	if validate_ONE == nil {
		init_validate_ONE()
	}

	// Initialize validate_EXACT if not already initialized.
	if validate_EXACT == nil {
		init_validate_EXACT()
	}

	// Create the store with validation commands
	store := map[string]any{
		// Remove the transform commands
		"$DELETE": nil,
		"$COPY":   nil, 
		"$KEY":    nil,
		"$META":   nil,
		"$MERGE":  nil,
		"$EACH":   nil,
		"$PACK":   nil,
		"$BT":     nil,
		"$DS":     nil,
		"$WHEN":   nil,

		// Add validation commands
		"$STRING":   validate_STRING,
		"$NUMBER":   validate_TYPE,
		"$INTEGER":  validate_TYPE,
		"$DECIMAL":  validate_TYPE,
		"$BOOLEAN":  validate_TYPE,
		"$NULL":     validate_TYPE,
		"$NIL":      validate_TYPE,
		"$MAP":      validate_TYPE,
		"$LIST":     validate_TYPE,
		"$FUNCTION": validate_TYPE,
		"$INSTANCE": validate_TYPE,
		"$OBJECT":   validate_OBJECT,
		"$ARRAY":    validate_ARRAY,
		"$ANY":      validate_ANY,
		"$CHILD":    validate_CHILD,
		"$ONE":      validate_ONE,
		"$EXACT":    validate_EXACT,
	}

	// Add any extra validation commands
	if extra != nil {
		for k, fn := range extra {
			store[k] = fn
		}
	}

	// A special top level value to collect errors
	store["$ERRS"] = errs

	// Set up meta with exact mode.
	meta := map[string]any{}
	if extra != nil {
		if metaVal, ok := extra["meta"]; ok {
			if metaMap, ok := metaVal.(map[string]any); ok {
				meta = metaMap
			}
			delete(store, "meta")
		}
	}
	if _, ok := meta[S_BEXACT]; !ok {
		meta[S_BEXACT] = false
	}

	// Check if exact mode is requested via meta.
	validationFn := validation
	exactVal, _ := meta[S_BEXACT].(bool)
	if exactVal {
		validationFn = makeValidation(true)
	}

	// Run the transformation with validation and _validatehandler
	out := TransformModifyHandler(data, spec, store, validationFn, _validatehandler, errs, meta)

	// Generate an error if we collected any errors and the caller didn't provide 
	// their own error collection
	var err error
	generr := 0 < len(errs.List) && collecterrs == nil
	if generr {
		// Join error messages
		errmsgs := make([]string, len(errs.List))
		for i, e := range errs.List {
			if s, ok := e.(string); ok {
				errmsgs[i] = s
			} else {
				errmsgs[i] = fmt.Sprintf("%v", e)
			}
		}
		err = fmt.Errorf("Invalid data: %s", strings.Join(errmsgs, " | "))
	}

	return out, err
}


// Mode names for injection modes.
var MODENAME = map[int]string{
	M_VAL:     "val",
	M_KEYPRE:  "key:pre",
	M_KEYPOST: "key:post",
}

// Placement names for injection modes.
var PLACEMENT = map[int]string{
	M_VAL:     "value",
	M_KEYPRE:  S_key,
	M_KEYPOST: S_key,
}

// Validate that an injector is placed in a valid mode and parent type.
func CheckPlacement(modes int, ijname string, parentTypes int, inj *Injection) bool {
	if 0 == (modes & inj.Mode) {
		allModes := []int{M_KEYPRE, M_KEYPOST, M_VAL}
		expected := []string{}
		for _, m := range allModes {
			if 0 != (modes & m) {
				expected = append(expected, PLACEMENT[m])
			}
		}
		inj.Errs.Append("$" + ijname + ": invalid placement as " + PLACEMENT[inj.Mode] +
			", expected: " + strings.Join(expected, ",") + ".")
		return false
	}
	if !IsEmpty(parentTypes) {
		ptype := Typify(inj.Parent)
		if 0 == (parentTypes & ptype) {
			inj.Errs.Append("$" + ijname + ": invalid placement in parent " + Typename(ptype) +
				", expected: " + Typename(parentTypes) + ".")
			return false
		}
	}
	return true
}

// Validate and extract injector arguments against expected type bitmasks.
// Returns a slice where [0] is nil on success or an error string on failure,
// and [1..N] are the validated arguments.
func InjectorArgs(argTypes []int, args []any) []any {
	numargs := len(argTypes)
	found := make([]any, 1+numargs)
	found[0] = nil
	for argI := 0; argI < numargs; argI++ {
		arg := args[argI]
		argType := Typify(arg)
		if 0 == (argTypes[argI] & argType) {
			found[0] = "invalid argument: " + Stringify(arg, 22) +
				" (" + Typename(argType) + " at position " + strconv.Itoa(1+argI) +
				") is not of type: " + Typename(argTypes[argI]) + "."
			break
		}
		found[1+argI] = arg
	}
	return found
}


// Select helpers - internal injectors for query matching.

var select_AND Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if M_KEYPRE == inj.Mode {
		terms := GetProp(inj.Parent, inj.Key)

		pathList := inj.Path.List
		ppath := pathList[:len(pathList)-1]
		point := GetPath(ppath, store)

		vstore := Merge([]any{map[string]any{}, store})
		SetProp(vstore, S_DTOP, point)

		termList, _ := _asList(terms)
		for _, term := range termList {
			terrs := ListRefCreate[any]()
			vstoreMap, _ := vstore.(map[string]any)
			validateCollectExact(point, term, vstoreMap, terrs)
			if 0 != len(terrs.List) {
				inj.Errs.Append("AND:" + Pathify(ppath) + S_VIZ +
					Stringify(point) + " fail:" + Stringify(terms))
			}
		}

		if len(pathList) >= 2 {
			gkey := pathList[len(pathList)-2]
			gp := inj.Nodes.List[len(inj.Nodes.List)-2]
			SetProp(gp, gkey, point)
		}
	}
	return nil
}

var select_OR Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if M_KEYPRE == inj.Mode {
		terms := GetProp(inj.Parent, inj.Key)

		pathList := inj.Path.List
		ppath := pathList[:len(pathList)-1]
		point := GetPath(ppath, store)

		vstore := Merge([]any{map[string]any{}, store})
		SetProp(vstore, S_DTOP, point)

		termList, _ := _asList(terms)
		for _, term := range termList {
			terrs := ListRefCreate[any]()
			vstoreMap, _ := vstore.(map[string]any)
			validateCollectExact(point, term, vstoreMap, terrs)
			if 0 == len(terrs.List) {
				if len(pathList) >= 2 {
					gkey := pathList[len(pathList)-2]
					gp := inj.Nodes.List[len(inj.Nodes.List)-2]
					SetProp(gp, gkey, point)
				}
				return nil
			}
		}

		inj.Errs.Append("OR:" + Pathify(ppath) + S_VIZ +
			Stringify(point) + " fail:" + Stringify(terms))
	}
	return nil
}

var select_NOT Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if M_KEYPRE == inj.Mode {
		term := GetProp(inj.Parent, inj.Key)

		pathList := inj.Path.List
		ppath := pathList[:len(pathList)-1]
		point := GetPath(ppath, store)

		vstore := Merge([]any{map[string]any{}, store})
		SetProp(vstore, S_DTOP, point)

		terrs := ListRefCreate[any]()
		vstoreMap, _ := vstore.(map[string]any)
		validateCollectExact(point, term, vstoreMap, terrs)

		if 0 == len(terrs.List) {
			inj.Errs.Append("NOT:" + Pathify(ppath) + S_VIZ +
				Stringify(point) + " fail:" + Stringify(term))
		}

		if len(pathList) >= 2 {
			gkey := pathList[len(pathList)-2]
			gp := inj.Nodes.List[len(inj.Nodes.List)-2]
			SetProp(gp, gkey, point)
		}
	}
	return nil
}

var select_CMP Injector = func(
	inj *Injection,
	val any,
	ref *string,
	store any,
) any {
	if M_KEYPRE == inj.Mode {
		term := GetProp(inj.Parent, inj.Key)

		pathList := inj.Path.List
		ppath := pathList[:len(pathList)-1]
		point := GetPath(ppath, store)

		pass := false
		refStr := ""
		if ref != nil {
			refStr = *ref
		}

		pf, pErr := _toFloat64(point)
		tf, tErr := _toFloat64(term)

		switch refStr {
		case "$GT":
			if pErr == nil && tErr == nil {
				pass = pf > tf
			}
		case "$LT":
			if pErr == nil && tErr == nil {
				pass = pf < tf
			}
		case "$GTE":
			if pErr == nil && tErr == nil {
				pass = pf >= tf
			}
		case "$LTE":
			if pErr == nil && tErr == nil {
				pass = pf <= tf
			}
		case "$LIKE":
			if ts, ok := term.(string); ok {
				re, err := regexp.Compile(ts)
				if err == nil {
					pass = re.MatchString(Stringify(point))
				}
			}
		}

		if pass {
			if len(pathList) >= 2 {
				gkey := pathList[len(pathList)-2]
				gp := inj.Nodes.List[len(inj.Nodes.List)-2]
				SetProp(gp, gkey, point)
			}
		} else {
			inj.Errs.Append("CMP: " + Pathify(ppath) + S_VIZ +
				Stringify(point) + " fail:" + refStr + " " + Stringify(term))
		}
	}
	return nil
}


// Internal exact-mode validation for Select.
// Like Validate but uses exact scalar comparison.
func validateCollectExact(
	data any,
	spec any,
	extra map[string]any,
	collecterrs *ListRef[any],
) {
	errs := collecterrs
	if nil == errs {
		errs = ListRefCreate[any]()
	}

	if validate_ONE == nil {
		init_validate_ONE()
	}
	if validate_EXACT == nil {
		init_validate_EXACT()
	}

	store := map[string]any{
		"$DELETE": nil,
		"$COPY":   nil,
		"$KEY":    nil,
		"$META":   nil,
		"$MERGE":  nil,
		"$EACH":   nil,
		"$PACK":   nil,
		"$BT":     nil,
		"$DS":     nil,
		"$WHEN":   nil,

		"$STRING":   validate_STRING,
		"$NUMBER":   validate_TYPE,
		"$INTEGER":  validate_TYPE,
		"$DECIMAL":  validate_TYPE,
		"$BOOLEAN":  validate_TYPE,
		"$NULL":     validate_TYPE,
		"$NIL":      validate_TYPE,
		"$MAP":      validate_TYPE,
		"$LIST":     validate_TYPE,
		"$FUNCTION": validate_TYPE,
		"$INSTANCE": validate_TYPE,
		"$OBJECT":   validate_OBJECT,
		"$ARRAY":    validate_ARRAY,
		"$ANY":      validate_ANY,
		"$CHILD":    validate_CHILD,
		"$ONE":      validate_ONE,
		"$EXACT":    validate_EXACT,
	}

	if extra != nil {
		for k, fn := range extra {
			store[k] = fn
		}
	}

	store["$ERRS"] = errs

	meta := map[string]any{S_BEXACT: true}
	TransformModifyHandler(data, spec, store, makeValidation(true), _validatehandler, errs, meta)
}


// Select children from a node that match a query.
// Uses validate internally with query operators ($AND, $OR, $NOT,
// $GT, $LT, $GTE, $LTE, $LIKE).
// For maps, children are values (tagged with $KEY). For lists, children are elements.
func Select(children any, query any) []any {
	if !IsNode(children) {
		return []any{}
	}

	var childList []any

	if IsMap(children) {
		pairs := Items(children)
		childList = make([]any, len(pairs))
		for i, pair := range pairs {
			child := pair[1]
			if IsMap(child) {
				SetProp(child, "$KEY", pair[0])
			}
			childList[i] = child
		}
	} else {
		list, _ := _asList(children)
		if list == nil {
			list = _listify(children)
		}
		childList = make([]any, len(list))
		for i, child := range list {
			if IsMap(child) {
				SetProp(child, "$KEY", i)
			}
			childList[i] = child
		}
	}

	results := []any{}
	extra := map[string]any{
		"$AND":  select_AND,
		"$OR":   select_OR,
		"$NOT":  select_NOT,
		"$GT":   select_CMP,
		"$LT":   select_CMP,
		"$GTE":  select_CMP,
		"$LTE":  select_CMP,
		"$LIKE": select_CMP,
	}

	q := Clone(query)

	// Mark all map nodes as open so extra keys don't fail validation.
	Walk(q, func(key *string, v any, parent any, path []string) any {
		if IsMap(v) {
			m := v.(map[string]any)
			if _, has := m[S_BOPEN]; !has {
				m[S_BOPEN] = true
			}
		}
		return v
	})

	for _, child := range childList {
		errs := ListRefCreate[any]()
		validateCollectExact(child, Clone(q), extra, errs)
		if 0 == len(errs.List) {
			results = append(results, child)
		}
	}

	return results
}


// Internal utilities
// ==================

type ListRef[T any] struct {
	List []T
}

func ListRefCreate[T any]() *ListRef[T] {
	return &ListRef[T]{
		List: make([]T, 0),
	}
}


func (l *ListRef[T]) Append(elem T) {
	l.List = append(l.List, elem)
}


func (l *ListRef[T]) Prepend(elem T) {
	l.List = append([]T{elem}, l.List...)
}

func _join(vals []any, sep string) string {
	strVals := make([]string, len(vals))
	for i, v := range vals {
		strVals[i] = fmt.Sprint(v)
	}
	return strings.Join(strVals, sep)
}


func _invalidTypeMsg(path []string, needtype string, vt string, v any, whence ...string) string {
	vs := "no value"
	if v != nil {
		vs = Stringify(v)
	}

	fieldPart := ""
	if len(path) > 1 {
		fieldPart = "field " + Pathify(path, 1) + " to be "
	}

	typePart := ""
	if v != nil {
		typePart = vt + ": "
	}

	// Build the main error message
	message := "Expected " + fieldPart + needtype + ", but found " + typePart + vs

	// Uncomment to help debug validation errors
	// if len(whence) > 0 {
	//    message += " [" + whence[0] + "]"
	// }

	return message + "."
}

func _getType(v any) string {
	if nil == v {
		return "nil"
	}
	return reflect.TypeOf(v).String()
}


// StrKey converts different types of keys to string representation.
// String keys are returned as is.
// Number keys are converted to strings.
// Floats are truncated to integers.
// Booleans, objects, arrays, null, undefined all return empty string.

// TODO: rename to _strKey
func StrKey(key any) string {
	if nil == key {
		return S_MT
	}

	switch v := key.(type) {
	case string:
		return v
	case *string:
		if nil != v {
			return *v
		}
		return S_MT
	case int:
		return strconv.Itoa(v)
	case int64:
		return strconv.FormatInt(v, 10)
	case int32:
		return strconv.FormatInt(int64(v), 10)
	case float64:
		return strconv.FormatInt(int64(v), 10)
	case float32:
		return strconv.FormatInt(int64(v), 10)
	case bool:
		return S_MT
	default:
		return S_MT
	}
}


func _resolveStrings(input []any) []string {
	var result []string

	for _, v := range input {
		if str, ok := v.(string); ok {
			result = append(result, str)
		} else {
			result = append(result, StrKey(v))
		}
	}

	return result
}


// Extract a bare []any from either a []any or a *ListRef[any].
// Recursively unwrap *ListRef[any] to []any for JSON marshaling.
func _unwrapListRefs(val any) any {
	return _unwrapListRefsD(val, 0)
}

func _unwrapListRefsD(val any, depth int) any {
	if depth > 32 {
		return val
	}
	if lr, ok := val.(*ListRef[any]); ok {
		out := make([]any, len(lr.List))
		for i, v := range lr.List {
			out[i] = _unwrapListRefsD(v, depth+1)
		}
		return out
	}
	if m, ok := val.(map[string]any); ok {
		out := make(map[string]any, len(m))
		for k, v := range m {
			out[k] = _unwrapListRefsD(v, depth+1)
		}
		return out
	}
	if list, ok := val.([]any); ok {
		out := make([]any, len(list))
		for i, v := range list {
			out[i] = _unwrapListRefsD(v, depth+1)
		}
		return out
	}
	return val
}

func _asList(val any) ([]any, bool) {
	if lr, ok := val.(*ListRef[any]); ok {
		return lr.List, true
	}
	if list, ok := val.([]any); ok {
		return list, true
	}
	return nil, false
}


func _listify(src any) []any {
	if lr, ok := src.(*ListRef[any]); ok {
		return lr.List
	}

	if list, ok := src.([]any); ok {
		return list
	}

	if src == nil {
		return nil
	}

	val := reflect.ValueOf(src)
	if val.Kind() == reflect.Slice {
		length := val.Len()
		result := make([]any, length)

		for i := 0; i < length; i++ {
			result[i] = val.Index(i).Interface()
		}
		return result
	}

	return nil
}


// toFloat64 helps unify numeric types for floor conversion.
func _toFloat64(val any) (float64, error) {
	switch n := val.(type) {
	case float64:
		return n, nil
	case float32:
		return float64(n), nil
	case int:
		return float64(n), nil
	case int8:
		return float64(n), nil
	case int16:
		return float64(n), nil
	case int32:
		return float64(n), nil
	case int64:
		return float64(n), nil
	case uint:
		return float64(n), nil
	case uint8:
		return float64(n), nil
	case uint16:
		return float64(n), nil
	case uint32:
		return float64(n), nil
	case uint64:
		// might overflow if > math.MaxFloat64, but for demonstration that's rare
		return float64(n), nil
	default:
		return 0, fmt.Errorf("not a numeric type")
	}
}


// _parseInt is a helper to convert a string to int safely.
func _parseInt(s string) (int, error) {
	// We'll do a very simple parse:
	var x int
	var sign int = 1
	for i, c := range s {
		if c == '-' && i == 0 {
			sign = -1
			continue
		}
		if c < '0' || c > '9' {
			return 0, &ParseIntError{s}
		}
		x = 10*x + int(c-'0')
	}
	return x * sign, nil
}


type ParseIntError struct{ input string }


func (e *ParseIntError) Error() string {
	return "cannot parse int from: " + e.input
}


func _makeArrayType(values []any, target any) any {
	targetElem := reflect.TypeOf(target).Elem()
	out := reflect.MakeSlice(reflect.SliceOf(targetElem), len(values), len(values))

	for i, v := range values {
		elemVal := reflect.ValueOf(v)
		if !elemVal.Type().ConvertibleTo(targetElem) {
			return values
		}

		out.Index(i).Set(elemVal.Convert(targetElem))
	}

	return out.Interface()
}


func _stringifyValue(v any) string {
	switch vv := v.(type) {
	case string:
		return vv
	case float64, int, bool:
		return Stringify(v)
	default:
		return Stringify(v)
	}
}




// DEBUG

func fdt(data any) string {
	return fdti(data, "")
}

func fdti(data any, indent string) string {
	result := ""

	if data == nil {
		return indent + "nil\n"
	}

	// Get a pointer for memory address
	memoryAddr := "0x???"
	val := reflect.ValueOf(data)

	// For non-pointer types that are addressable, get their pointer
	if val.Kind() != reflect.Ptr && val.CanAddr() {
		ptr := val.Addr()
		memoryAddr = fmt.Sprintf("0x%x", ptr.Pointer())
	} else if val.Kind() == reflect.Ptr {
		// For pointer types, use the pointer value directly
		memoryAddr = fmt.Sprintf("0x%x", val.Pointer())
	} else if val.Kind() == reflect.Map || val.Kind() == reflect.Slice {
		// For maps and slices, use the pointer to internal data
		memoryAddr = fmt.Sprintf("0x%x", val.Pointer())
	}

	switch v := data.(type) {
	case map[string]any:
		result += indent + fmt.Sprintf("{ @%s\n", memoryAddr)
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, fdti(value, indent+"  "))
		}
		result += indent + "}\n"

	case []any:
		result += indent + fmt.Sprintf("[ @%s\n", memoryAddr)
		for _, value := range v {
			result += fmt.Sprintf("%s  - %s", indent, fdti(value, indent+"  "))
		}
		result += indent + "]\n"

	default:
		// Check if it's a struct using reflection
		typ := val.Type()

		// Handle pointers by dereferencing
		isPtr := false
		if val.Kind() == reflect.Ptr {
			isPtr = true
			if val.IsNil() {
				return indent + "nil\n"
			}
			val = val.Elem()
			typ = val.Type()
		}

		if val.Kind() == reflect.Struct {
			structName := typ.Name()
			if isPtr {
				structName = "*" + structName
			}
			result += indent + fmt.Sprintf("struct %s @%s {\n", structName, memoryAddr)

			// Iterate over all fields of the struct
			for i := 0; i < val.NumField(); i++ {
				field := val.Field(i)
				fieldType := typ.Field(i)

				// Skip unexported fields (lowercase field names)
				if !fieldType.IsExported() {
					continue
				}

				fieldName := fieldType.Name
				fieldValue := field.Interface()

				result += fmt.Sprintf("%s  %s: %s", indent, fieldName, fdti(fieldValue, indent+"  "))
			}
			result += indent + "}\n"
		} else {
			// For non-struct types, just format value with its type
			result += fmt.Sprintf("%v (%s) @%s\n", v, reflect.TypeOf(v), memoryAddr)
		}
	}

	return result
}
