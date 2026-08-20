// Test helpers that are not runner API, and so do not come from omni's
// compat shim. NullModifier's signature names struct's own
// *voxgigstruct.Injection; Fdt and ToJSONString are debug printers the
// test file uses directly.

package runner

import (
	"encoding/json"
	"fmt"
	"reflect"
	"strings"

	voxgigstruct "github.com/voxgig/struct/go"
)

func NullModifier(
	val any,
	key any,
	parent any,
	inj *voxgigstruct.Injection,
	store any,
) {
	switch v := val.(type) {
	case string:
		if NULLMARK == v {
			_ = voxgigstruct.SetProp(parent, key, nil)
		} else if UNDEFMARK == v {
			// Handle undefined values - in Go, we just set to nil
			_ = voxgigstruct.SetProp(parent, key, nil)
		} else if EXISTSMARK == v {
			// For EXISTSMARK, we don't need to do anything special in the modifier
			// since this is a marker used during matching, not a value to be transformed
		} else {
			_ = voxgigstruct.SetProp(parent, key,
				strings.ReplaceAll(v, NULLMARK, "null"))
		}
	}
}

func Fdt(data any) string {
	return fdti(data, "")
}

func fdti(data any, indent string) string {
	result := ""

	switch v := data.(type) {
	case map[string]any:
		result += indent + "{\n"
		for key, value := range v {
			result += fmt.Sprintf("%s  \"%s\": %s", indent, key, fdti(value, indent+"  "))
		}
		result += indent + "}\n"

	case []any:
		result += indent + "[\n"
		for _, value := range v {
			result += fmt.Sprintf("%s  - %s", indent, fdti(value, indent+"  "))
		}
		result += indent + "]\n"

	default:
		// Format value with its type
		result += fmt.Sprintf("%v (%s)\n", v, reflect.TypeOf(v))
	}

	return result
}

func ToJSONString(data any) string {
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return ""
	}
	return string(jsonBytes)
}
