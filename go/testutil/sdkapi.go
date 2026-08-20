// The SDK shapes the test harness builds and the runner consumes. These
// stay in struct's tree rather than moving to omni's compat shim: they name
// struct's own types (*voxgigstruct.Injection, WalkApply), which the shim
// deliberately never imports - it reaches the SDK by reflection so that omni
// cannot end up depending on the library it is meant to check.

package runner

import (
	voxgigstruct "github.com/voxgig/struct/go"
)

// Client interface defines the minimum needed to work with the runner
type Client interface {
	Utility() Utility
}

type Utility interface {
	Struct() *StructUtility
	Check(ctx map[string]any) map[string]any
}

type StructUtility struct {
	IsNode     func(val any) bool
	Clone      func(val any) any
	CloneFlags func(val any, flags map[string]bool) any
	GetPath    func(store any, path any, injdefs ...*voxgigstruct.Injection) any
	Inject     func(val any, store any, injdefs ...*voxgigstruct.Injection) any
	Items      func(val any) [][2]any
	Stringify  func(val any, maxlen ...int) string
	Walk       func(val any, apply voxgigstruct.WalkApply, opts ...any) any

	DelProp   func(parent any, key any) any
	EscRe     func(s string) string
	EscUrl    func(s string) string
	Filter    func(val any, check func([2]any) bool) []any
	Flatten   func(list any, depths ...int) any
	GetDef    func(val any, alt any) any
	GetElem   func(val any, key any, alts ...any) any
	GetProp   func(val any, key any, alts ...any) any
	HasKey    func(val any, key any) bool
	IsEmpty   func(val any) bool
	IsFunc    func(val any) bool
	IsKey     func(val any) bool
	IsList    func(val any) bool
	IsMap     func(val any) bool
	Join      func(arr []any, args ...any) string
	Jsonify   func(val any, flags ...map[string]any) string
	KeysOf    func(val any) []string
	Merge     func(val any, maxdepths ...int) any
	Pad       func(str any, args ...any) string
	Pathify   func(val any, from ...int) string
	Select    func(children any, query any) []any
	SetPath   func(store any, path any, val any, injdefs ...map[string]any) any
	SetProp   func(parent any, key any, newval any) any
	Size      func(val any) int
	Slice     func(val any, args ...any) any
	StrKey    func(key any) string
	Transform func(data any, spec any, injdefs ...*voxgigstruct.Injection) (any, error)
	Typify    func(value any) int
	Typename  func(t int) string
	Validate  func(data any, spec any, injdefs ...*voxgigstruct.Injection) (any, error)

	SKIP   any
	DELETE any
	NOVAL  any

	Jm func(kv ...any) map[string]any
	Jt func(v ...any) []any

	CheckPlacement func(modes int, ijname string, parentTypes int, inj *voxgigstruct.Injection) bool
	InjectorArgs   func(argTypes []int, args []any) []any
	InjectChild    func(child any, store any, inj *voxgigstruct.Injection) *voxgigstruct.Injection
}
