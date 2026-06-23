// Test Provider (prototype) — Go port of the canonical TypeScript
// implementation (../ts/provider.ts).
//
// Reads the shared corpus (build/test/test.json) and hands test code clean,
// normalized cases. It is NOT a test runner: it never calls the subject and
// never asserts. See ../PROVIDER.md for the model and ../AGENTS.md for usage.
//
// Zero runtime dependencies (Go standard library only), matching repo policy.

package provider

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
)

const (
	nullMark   = "__NULL__"
	undefMark  = "__UNDEF__"
	existsMark = "__EXISTS__"
)

// Input is a tagged invocation: exactly one of in/args/ctx is meaningful,
// selected by Kind (mirrors the runner's ctx → args → in precedence).
type Input struct {
	Kind string         // "in" | "args" | "ctx"
	In   any            // Kind=="in"
	Args []any          // Kind=="args"
	Ctx  map[string]any // Kind=="ctx"
}

// ErrorCheck is the parsed form of a raw `err` spec.
type ErrorCheck struct {
	Any     bool
	Text    string
	HasText bool
	Regex   bool
}

// Expect is a tagged expectation: value | error | match | absent.
type Expect struct {
	Kind     string // "value" | "error" | "match" | "absent"
	Value    any    // Kind=="value"
	HasValue bool   // distinguishes present-null from absent
	Error    *ErrorCheck
	Match    any // populated whenever a `match` key is present
}

// Entry is the normalized record for a single corpus test case.
type Entry struct {
	Function string
	Group    string
	Index    int
	ID       *string
	Doc      bool
	Client   *string
	Input    Input
	Expect   Expect
	Raw      map[string]any
}

// MatchResult is the outcome of a structural match.
type MatchResult struct {
	Ok       bool
	Path     []string
	Expected any
	Actual   any
}

// TestProvider holds the parsed corpus.
type TestProvider struct {
	spec  any
	order map[string][]string // object-path -> ordered keys (for stable listing)
}

// defaultTestFile resolves build/test/test.json relative to the repo root,
// using the location of this source file so it works regardless of cwd.
func defaultTestFile() string {
	_, here, _, _ := runtime.Caller(0) // .../test/proto/go/provider.go
	dir := filepath.Dir(here)          // test/proto/go
	return filepath.Join(dir, "..", "..", "..", "build", "test", "test.json")
}

// Load parses test.json. An empty testfile means the default corpus path.
func Load(testfile string) (*TestProvider, error) {
	file := testfile
	if file == "" {
		file = defaultTestFile()
	}
	data, err := os.ReadFile(file) // #nosec G304 -- fixed test-corpus path.
	if err != nil {
		return nil, err
	}
	var spec any
	if err := json.Unmarshal(data, &spec); err != nil {
		return nil, err
	}
	order := map[string][]string{}
	if err := recordOrder(data, order); err != nil {
		return nil, err
	}
	return &TestProvider{spec: spec, order: order}, nil
}

// recordOrder walks the raw JSON with a streaming decoder, recording the key
// order of every object keyed by its slash-joined path. encoding/json does not
// preserve object key order, so this restores deterministic, corpus-faithful
// ordering for Functions()/Groups().
func recordOrder(data []byte, order map[string][]string) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	return scanValue(dec, "", order)
}

func scanValue(dec *json.Decoder, path string, order map[string][]string) error {
	tok, err := dec.Token()
	if err != nil {
		return err
	}
	delim, ok := tok.(json.Delim)
	if !ok {
		return nil // scalar
	}
	switch delim {
	case '{':
		var keys []string
		for dec.More() {
			kt, err := dec.Token()
			if err != nil {
				return err
			}
			key := kt.(string)
			keys = append(keys, key)
			child := path + "/" + key
			if path == "" {
				child = key
			}
			if err := scanValue(dec, child, order); err != nil {
				return err
			}
		}
		order[path] = keys
		_, err := dec.Token() // consume '}'
		return err
	case '[':
		i := 0
		for dec.More() {
			child := path + "/" + strconv.Itoa(i)
			if err := scanValue(dec, child, order); err != nil {
				return err
			}
			i++
		}
		_, err := dec.Token() // consume ']'
		return err
	}
	return nil
}

// Raw returns the parsed test.json (escape hatch).
func (p *TestProvider) Raw() any {
	return p.spec
}

// root returns spec.struct if present, else spec itself, as a map.
func (p *TestProvider) root() map[string]any {
	if m, ok := p.spec.(map[string]any); ok {
		if s, ok := m["struct"].(map[string]any); ok {
			return s
		}
		return m
	}
	return nil
}

// fnNode resolves the node for a function (under struct, falling back to root).
func (p *TestProvider) fnNode(fn string) map[string]any {
	if m, ok := p.spec.(map[string]any); ok {
		if s, ok := m["struct"].(map[string]any); ok {
			if n, ok := s[fn].(map[string]any); ok {
				return n
			}
		}
		if n, ok := m[fn].(map[string]any); ok {
			return n
		}
	}
	return nil
}

// rootPath returns the order-table path prefix for the function-bearing root
// ("struct" if present, else "").
func (p *TestProvider) rootPath() string {
	if m, ok := p.spec.(map[string]any); ok {
		if _, ok := m["struct"].(map[string]any); ok {
			return "struct"
		}
	}
	return ""
}

// Functions lists the function names in corpus order.
func (p *TestProvider) Functions() []string {
	root := p.root()
	if root == nil {
		return nil
	}
	out := []string{}
	for _, k := range p.orderedKeys(p.rootPath(), root) {
		if isGroupBag(root[k]) || hasGroups(root[k]) {
			out = append(out, k)
		}
	}
	return out
}

// Groups lists the group names for a function in corpus order.
func (p *TestProvider) Groups(fn string) []string {
	node := p.fnNode(fn)
	if node == nil {
		return nil
	}
	rp := p.rootPath()
	fnPath := fn
	if rp != "" {
		fnPath = rp + "/" + fn
	}
	out := []string{}
	for _, k := range p.orderedKeys(fnPath, node) {
		if k != "name" && isGroupBag(node[k]) {
			out = append(out, k)
		}
	}
	return out
}

// orderedKeys returns the keys of node m in corpus order if known, else in map
// iteration order (which is acceptable for callers that only need the set).
func (p *TestProvider) orderedKeys(path string, m map[string]any) []string {
	if ord, ok := p.order[path]; ok {
		return ord
	}
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	return keys
}

// Entries returns all entries for a function, or for one specific group.
func (p *TestProvider) Entries(fn string, group ...string) []Entry {
	node := p.fnNode(fn)
	if node == nil {
		return nil
	}
	var groups []string
	if len(group) > 0 {
		groups = []string{group[0]}
	} else {
		groups = p.Groups(fn)
	}
	out := []Entry{}
	for _, g := range groups {
		bag, ok := node[g].(map[string]any)
		if !ok || !isGroupBag(bag) {
			continue
		}
		set, _ := bag["set"].([]any)
		for i, raw := range set {
			rawMap, _ := raw.(map[string]any)
			out = append(out, normalize(fn, g, i, rawMap))
		}
	}
	return out
}

// isGroupBag reports whether v is a map containing a `set` array.
func isGroupBag(v any) bool {
	m, ok := v.(map[string]any)
	if !ok {
		return false
	}
	_, ok = m["set"].([]any)
	return ok
}

// hasGroups reports whether v is a map with at least one child group bag.
func hasGroups(v any) bool {
	m, ok := v.(map[string]any)
	if !ok {
		return false
	}
	for k, cv := range m {
		if k != "name" && isGroupBag(cv) {
			return true
		}
	}
	return false
}

func has(m map[string]any, key string) bool {
	if m == nil {
		return false
	}
	_, ok := m[key]
	return ok
}

func normalize(fn, group string, index int, raw map[string]any) Entry {
	var id *string
	if v, ok := raw["id"]; ok && v != nil {
		s := stringify(v)
		id = &s
	}
	var client *string
	if v, ok := raw["client"]; ok && v != nil {
		s := stringify(v)
		client = &s
	}
	doc := raw["doc"] == true
	return Entry{
		Function: fn,
		Group:    group,
		Index:    index,
		ID:       id,
		Doc:      doc,
		Client:   client,
		Input:    resolveInput(raw),
		Expect:   resolveExpect(raw),
		Raw:      raw,
	}
}

func resolveInput(raw map[string]any) Input {
	if has(raw, "ctx") {
		ctx, _ := raw["ctx"].(map[string]any)
		return Input{Kind: "ctx", Ctx: ctx}
	}
	if has(raw, "args") {
		args, _ := raw["args"].([]any)
		return Input{Kind: "args", Args: args}
	}
	if has(raw, "in") {
		return Input{Kind: "in", In: raw["in"]}
	}
	return Input{Kind: "in", In: nil}
}

func parseErr(err any) ErrorCheck {
	if err == true {
		return ErrorCheck{Any: true}
	}
	if s, ok := err.(string); ok {
		if m := reErr.FindStringSubmatch(s); m != nil {
			return ErrorCheck{Text: m[1], HasText: true, Regex: true}
		}
		return ErrorCheck{Text: s, HasText: true}
	}
	// Non-true, non-string err spec: treat as "any error".
	return ErrorCheck{Any: true}
}

var reErr = regexp.MustCompile(`^/(.+)/$`)

func resolveExpect(raw map[string]any) Expect {
	var matchPart any
	hasMatch := has(raw, "match")
	if hasMatch {
		matchPart = raw["match"]
	}
	if has(raw, "err") {
		ec := parseErr(raw["err"])
		return Expect{Kind: "error", Error: &ec, Match: matchPart}
	}
	if has(raw, "out") {
		return Expect{Kind: "value", Value: raw["out"], HasValue: true, Match: matchPart}
	}
	if hasMatch {
		return Expect{Kind: "match", Match: matchPart}
	}
	return Expect{Kind: "absent"}
}

// ─── pure comparison helpers ───────────────────────────────────────────────

func stringify(x any) string {
	if s, ok := x.(string); ok {
		return s
	}
	b, err := json.Marshal(x)
	if err != nil {
		return ""
	}
	return string(b)
}

// Matchval reproduces the runner's scalar match: deep-equal, then string rules.
func Matchval(check, base any) bool {
	if EqualStrict(check, base) {
		return true
	}
	if cs, ok := check.(string); ok {
		basestr := stringify(base)
		if m := reErr.FindStringSubmatch(cs); m != nil {
			re, err := regexp.Compile(m[1])
			if err != nil {
				return false
			}
			return re.MatchString(basestr)
		}
		return strings.Contains(strings.ToLower(basestr), strings.ToLower(cs))
	}
	return false
}

// Equal is deep equality collapsing "__NULL__" and nil to nil on both sides.
func Equal(expected, actual any) bool {
	return deepEq(normNull(expected), normNull(actual))
}

// EqualStrict is deep equality normalizing only "__NULL__" to nil.
func EqualStrict(expected, actual any) bool {
	return deepEq(normMark(expected), normMark(actual))
}

func normNull(x any) any {
	if x == nullMark || x == nil {
		return nil
	}
	switch v := x.(type) {
	case []any:
		out := make([]any, len(v))
		for i, e := range v {
			out[i] = normNull(e)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(v))
		for k, e := range v {
			out[k] = normNull(e)
		}
		return out
	}
	return x
}

func normMark(x any) any {
	if x == nullMark {
		return nil
	}
	switch v := x.(type) {
	case []any:
		out := make([]any, len(v))
		for i, e := range v {
			out[i] = normMark(e)
		}
		return out
	case map[string]any:
		out := make(map[string]any, len(v))
		for k, e := range v {
			out[k] = normMark(e)
		}
		return out
	}
	return x
}

func deepEq(a, b any) bool {
	if scalarEq(a, b) {
		return true
	}
	al, aok := a.([]any)
	bl, bok := b.([]any)
	if aok && bok {
		if len(al) != len(bl) {
			return false
		}
		for i := range al {
			if !deepEq(al[i], bl[i]) {
				return false
			}
		}
		return true
	}
	am, aok := a.(map[string]any)
	bm, bok := b.(map[string]any)
	if aok && bok {
		if len(am) != len(bm) {
			return false
		}
		for k, av := range am {
			bv, ok := bm[k]
			if !ok || !deepEq(av, bv) {
				return false
			}
		}
		return true
	}
	return false
}

// scalarEq compares scalars; JSON numbers are float64 so numeric values compare
// directly. nil==nil is true here.
func scalarEq(a, b any) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	af, aok := toFloat(a)
	bf, bok := toFloat(b)
	if aok && bok {
		return af == bf
	}
	if aok != bok {
		return false
	}
	switch av := a.(type) {
	case string:
		bv, ok := b.(string)
		return ok && av == bv
	case bool:
		bv, ok := b.(bool)
		return ok && av == bv
	}
	return false
}

func toFloat(x any) (float64, bool) {
	switch v := x.(type) {
	case float64:
		return v, true
	case float32:
		return float64(v), true
	case int:
		return float64(v), true
	case int64:
		return float64(v), true
	}
	return 0, false
}

// ErrorMatches checks an ErrorCheck against a thrown message.
func ErrorMatches(check ErrorCheck, message string) bool {
	if check.Any {
		return true
	}
	if !check.HasText {
		return false
	}
	if check.Regex {
		re, err := regexp.Compile(check.Text)
		if err != nil {
			return false
		}
		return re.MatchString(message)
	}
	return strings.Contains(strings.ToLower(message), strings.ToLower(check.Text))
}

// StructMatch performs a partial structural match: every leaf of check must
// match base at its path.
func StructMatch(check, base any) MatchResult {
	result := MatchResult{Ok: true}
	walkLeaves(check, nil, func(val any, path []string) {
		if !result.Ok {
			return
		}
		baseval, found := getpath(base, path)
		if found && scalarEq(baseval, val) {
			return
		}
		if val == undefMark && (!found || baseval == nil) {
			return
		}
		if val == existsMark && found && baseval != nil {
			return
		}
		if !Matchval(val, baseval) {
			result = MatchResult{Ok: false, Path: path, Expected: val, Actual: baseval}
		}
	})
	return result
}

func walkLeaves(node any, path []string, fn func(val any, path []string)) {
	switch v := node.(type) {
	case []any:
		for i, e := range v {
			walkLeaves(e, appendPath(path, strconv.Itoa(i)), fn)
		}
	case map[string]any:
		for k, e := range v {
			walkLeaves(e, appendPath(path, k), fn)
		}
	default:
		fn(node, path)
	}
}

func appendPath(path []string, key string) []string {
	out := make([]string, len(path)+1)
	copy(out, path)
	out[len(path)] = key
	return out
}

// getpath descends store following path. The bool reports whether the leaf was
// present (false means it ran off a nil or a missing key).
func getpath(store any, path []string) (any, bool) {
	cur := store
	for _, key := range path {
		if cur == nil {
			return nil, false
		}
		switch c := cur.(type) {
		case map[string]any:
			v, ok := c[key]
			if !ok {
				return nil, false
			}
			cur = v
		case []any:
			idx, err := strconv.Atoi(key)
			if err != nil || idx < 0 || idx >= len(c) {
				return nil, false
			}
			cur = c[idx]
		default:
			return nil, false
		}
	}
	return cur, true
}
