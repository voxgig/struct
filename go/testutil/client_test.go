package runner

import (
	"testing"
)

// TestClient is the Go equivalent to client.test.ts
// It tests the SDK client with the test runner
func TestClient(t *testing.T) {
	// Create a test SDK client
	sdk, err := TestSDK(nil)
	if err != nil {
		t.Fatalf("Failed to create SDK: %v", err)
	}

	// Create the runner with the SDK client
	runnerFunc := MakeRunner("../../build/test/test.json", sdk)
	runnerMap, err := runnerFunc("check", nil)
	if err != nil {
		t.Fatalf("Failed to create runner check: %v", err)
	}

	// Extract the spec, runset, and subject
	spec := runnerMap.Spec
	runset := runnerMap.RunSet
	subject := runnerMap.Subject

	// Run the client-check-basic test
	t.Run("client-check-basic", func(t *testing.T) {
		runset(t, spec["basic"], subject)
	})
}
