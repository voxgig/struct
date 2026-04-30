
// RUN: go test
// RUN-SOME: go test -v -run=TestStruct/getpath


package voxgigstruct_test

import (
	// "fmt"
	// "reflect"
	// "strings"
	"testing"

	// "github.com/voxgig/struct/go"
	"github.com/voxgig/struct/go/testutil"
)

const TEST_JSON_FILE = "../build/test/test.json"


func TestClient(t *testing.T) {
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

	var spec map[string]any = runnerMap.Spec
	var runset runner.RunSet = runnerMap.RunSet
	var subject runner.Subject = runnerMap.Subject

	t.Run("client-check-basic", func(t *testing.T) {
    runset(t, spec["basic"], subject)
	})
}
