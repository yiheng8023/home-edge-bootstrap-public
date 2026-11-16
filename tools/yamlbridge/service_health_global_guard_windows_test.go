//go:build windows

package main

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestServiceGlobalGuardWindowsShortTempAlias(t *testing.T) {
	// Do not parallelize: both the wrapper contract and this fixture use the
	// process environment. testing.T.Setenv enforces that restriction.
	root := canonicalHealthTempDir(t)
	first, second := filepath.Join(root, "before"), filepath.Join(root, "after")
	for _, dir := range []string{first, second} {
		if err := os.Mkdir(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	fixtureServiceGlobalGuard(t, first)
	wide, err := syscall.UTF16PtrFromString(root)
	if err != nil {
		t.Fatal(err)
	}
	buffer := make([]uint16, 32768)
	n, err := syscall.GetShortPathName(wide, &buffer[0], uint32(len(buffer)))
	if err != nil || n == 0 || n >= uint32(len(buffer)) {
		t.Fatalf("cannot inspect short-path support: %v", err)
	}
	short := syscall.UTF16ToString(buffer[:n])
	if strings.EqualFold(short, root) {
		t.Skip("this filesystem does not allocate an 8.3 alias; ordinary Windows ownership tests remain enabled")
	}
	longInfo, err := os.Stat(root)
	if err != nil {
		t.Fatal(err)
	}
	shortInfo, err := os.Stat(short)
	if err != nil || !os.SameFile(longInfo, shortInfo) {
		t.Fatal("short path does not name the same fixture directory")
	}
	// Reproduce a runner environment whose temp root uses the short name,
	// while canonicalHealthTempDir has expanded the fixture path to its long
	// name. The production check intentionally remains lexical and fail-closed.
	t.Setenv("TMP", short)
	t.Setenv("TEMP", short)
	if !strings.EqualFold(os.TempDir(), short) {
		t.Fatalf("short temp environment was not selected: %q", os.TempDir())
	}
	if _, err := captureServiceGlobalGuard(); err == nil {
		t.Fatal("production guard accepted an unnormalized temp-root alias")
	}
	// The ordinary fixture must repair its own representation mismatch without
	// changing the guard, skipping positive coverage, or changing directories.
	path := fixtureServiceGlobalGuard(t, second)
	if !strings.EqualFold(os.TempDir(), root) {
		t.Fatalf("fixture did not canonicalize the actual temp root: %q", os.TempDir())
	}
	owned, err := captureServiceGlobalGuard()
	if err != nil || owned == nil || !owned() {
		t.Fatalf("canonical fixture still rejected: %v", err)
	}
	if err := os.WriteFile(filepath.Join(path, "service-health.owner"), []byte("later-owner\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if owned() {
		t.Fatal("canonical fixture weakened the later-owner check")
	}
}
