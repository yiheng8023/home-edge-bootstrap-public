package main

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestCoreValidationHasBoundedOwnedChild(t *testing.T) {
	if !probePlatformSupported() {
		t.Skip("Linux isolated child adapter")
	}
	dir := t.TempDir()
	program := filepath.Join(dir, "validator")
	if err := os.WriteFile(program, []byte("#!/bin/sh\nexec sleep 15\n"), 0700); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	err := validateCoreWithContext(context.Background(), coreTestRequest{SchemaVersion: 1, CorePath: program, ConfigFile: filepath.Join(dir, "config.yaml"), RuntimeDir: dir, TimeoutSec: 1})
	if err == nil || time.Since(start) > 4*time.Second {
		t.Fatal("validation escaped its deadline")
	}
	if err := os.WriteFile(program, []byte("#!/bin/sh\nexit 0\n"), 0700); err != nil {
		t.Fatal(err)
	}
	if err := validateCoreWithContext(context.Background(), coreTestRequest{SchemaVersion: 1, CorePath: program, ConfigFile: filepath.Join(dir, "config.yaml"), RuntimeDir: dir, TimeoutSec: 1}); err != nil {
		t.Fatal(err)
	}
}
