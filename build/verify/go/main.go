package main

import (
	"fmt"
	"os"

	voxgigstruct "github.com/voxgig/struct/go"
)

func main() {
	store := map[string]any{
		"db": map[string]any{"host": "localhost"},
	}

	got := voxgigstruct.GetPath(store, "db.host")

	if got == "localhost" {
		fmt.Println("OK go: getpath(db.host) = localhost")
		os.Exit(0)
	}

	fmt.Printf("FAIL go: getpath(db.host) = %v (want localhost)\n", got)
	os.Exit(1)
}
