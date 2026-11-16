package main

import (
	"context"
	"os"
	"path/filepath"
	"strconv"
	"testing"
	"time"
)

func fixtureServiceGlobalGuard(t *testing.T, directory string) string {
	t.Helper()
	path := filepath.Join(directory, "global.lock")
	if err := os.Mkdir(path, 0700); err != nil {
		t.Fatal(err)
	}
	pid := strconv.Itoa(os.Getppid())
	leaseID := "home-edge-service-run.fixtureXYZ." + pid
	for name, value := range map[string]string{"pid": pid, "operation": "service-health", "started_at": "1800000000", "service-health.owner": leaseID} {
		if err := os.WriteFile(filepath.Join(path, name), []byte(value+"\n"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv(serviceGlobalLockEnv, path)
	t.Setenv(serviceGlobalTokenEnv, leaseID)
	t.Setenv(serviceGlobalPIDEnv, pid)
	return path
}

func TestServiceGlobalGuardDirectCLIAndMalformedEnvironment(t *testing.T) {
	for _, key := range []string{serviceGlobalLockEnv, serviceGlobalTokenEnv, serviceGlobalPIDEnv} {
		t.Setenv(key, "")
	}
	if owned, err := captureServiceGlobalGuard(); err != nil || owned != nil {
		t.Fatal("direct CLI compatibility changed")
	}
	t.Setenv(serviceGlobalTokenEnv, "partial")
	if _, err := captureServiceGlobalGuard(); err == nil {
		t.Fatal("partial wrapper facts accepted")
	}
}

func TestServiceGlobalGuardIdentityAndContents(t *testing.T) {
	for _, kind := range []string{"unchanged", "leaseID-content", "same-content-new-file", "directory-replaced", "foreign-entry", "owner-pid", "foreign-operation", "symlink"} {
		t.Run(kind, func(t *testing.T) {
			path := fixtureServiceGlobalGuard(t, t.TempDir())
			owned, err := captureServiceGlobalGuard()
			if err != nil || owned == nil || !owned() {
				t.Fatalf("valid live wrapper ownership rejected: %v", err)
			}
			switch kind {
			case "leaseID-content":
				os.WriteFile(filepath.Join(path, "service-health.owner"), []byte("foreign\n"), 0600)
			case "same-content-new-file":
				file := filepath.Join(path, "operation")
				os.Rename(file, filepath.Join(t.TempDir(), "old-operation"))
				os.WriteFile(file, []byte("service-health\n"), 0600)
			case "directory-replaced":
				os.Rename(path, path+"-old")
				os.Mkdir(path, 0700)
			case "foreign-entry":
				os.WriteFile(filepath.Join(path, "foreign"), []byte("keep"), 0600)
			case "owner-pid":
				os.WriteFile(filepath.Join(path, "pid"), []byte(strconv.Itoa(os.Getpid())+"\n"), 0600)
			case "foreign-operation":
				os.WriteFile(filepath.Join(path, "operation"), []byte("subscription\n"), 0600)
			case "symlink":
				file := filepath.Join(path, "operation")
				old := filepath.Join(t.TempDir(), "original-operation")
				os.Rename(file, old)
				if err := os.Symlink(old, file); err != nil {
					t.Skip("symlinks unavailable")
				}
			}
			if owned() != (kind == "unchanged") {
				t.Fatal("changed global ownership remained valid")
			}
		})
	}
}

func TestServiceGlobalGuardRejectsForeignAndUnrelatedPID(t *testing.T) {
	path := fixtureServiceGlobalGuard(t, t.TempDir())
	t.Setenv(serviceGlobalPIDEnv, strconv.Itoa(os.Getpid()))
	if _, err := captureServiceGlobalGuard(); err == nil {
		t.Fatal("an alive process other than the parent was accepted")
	}
	t.Setenv(serviceGlobalPIDEnv, strconv.Itoa(os.Getppid()))
	os.WriteFile(filepath.Join(path, "operation"), []byte("foreign\n"), 0600)
	if _, err := captureServiceGlobalGuard(); err == nil {
		t.Fatal("foreign writer accepted")
	}
	raw, _ := os.ReadFile(filepath.Join(path, "operation"))
	if string(raw) != "foreign\n" {
		t.Fatal("guard changed the foreign writer")
	}
}

func TestServiceHealthGlobalOwnerChangeDuringProbeStopsWrites(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	path := fixtureServiceGlobalGuard(t, f.dir)
	original := serviceHealthProbe
	serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
		result, err := original(ctx, profile, config, node, core, timeout)
		if node == "good" {
			os.WriteFile(filepath.Join(path, "service-health.owner"), []byte("new-owner\n"), 0600)
		}
		return result, err
	}
	f.tick()
	if len(f.puts) != 0 {
		t.Fatalf("lost global ownership still wrote a selector: %v", f.puts)
	}
	raw, _ := os.ReadFile(filepath.Join(path, "service-health.owner"))
	if string(raw) != "new-owner\n" {
		t.Fatal("engine removed/replaced another writer's marker")
	}
}

func TestServiceHealthGlobalGuardInitialFailureAndObserve(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	t.Setenv(serviceGlobalTokenEnv, "partial")
	if got := f.tick().Services[0]; got.State != "global_writer_ownership_unverified" || len(f.puts) != 0 {
		t.Fatalf("partial ownership did not hold: %+v", got)
	}
	if _, err := os.Stat(filepath.Join(f.r.StateDir, "service-health.json")); !os.IsNotExist(err) {
		t.Fatal("unverified writer persisted policy state")
	}
	f.r.Mode = "observe"
	if got := f.tick().Services[0]; got.ProbeState != "region_denied" || len(f.puts) != 0 {
		t.Fatalf("read-only observation incorrectly needed writer ownership: %+v", got)
	}
}
