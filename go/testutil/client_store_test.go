// RUN: go test
// RUN-SOME: go test -v -run=TestStruct/getpath

package runner_test

import (
	"testing"

	"github.com/voxgig/struct/go/testutil"
)

const TEST_JSON_FILE = "../../build/test/test.json"

// TestClient's check, given a store to resolve client options against.
func TestClientWithStore(t *testing.T) {
	store := make(map[string]any)

	sdk, err := runner.TestSDK(nil)
	if err != nil {
		t.Fatalf("Failed to create SDK: %v", err)
	}
	runnerFunc := runner.MakeRunner(TEST_JSON_FILE, sdk)
	runnerMap, err := runnerFunc("check", store)
	if err != nil {
		t.Fatalf("Failed to create runner check: %v", err)
	}

	spec := runnerMap.Spec
	runset := runnerMap.RunSet
	subject := runnerMap.Subject

	t.Run("client-check-basic", func(t *testing.T) {
		runset(t, spec["basic"], subject)
	})
}
