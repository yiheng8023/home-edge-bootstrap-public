package main

import (
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"
	"time"
)

type coreTestRequest struct {
	SchemaVersion int    `json:"schema_version"`
	CorePath      string `json:"core_path"`
	ConfigFile    string `json:"config_file"`
	RuntimeDir    string `json:"runtime_dir"`
	TimeoutSec    int    `json:"timeout_sec"`
}

func validateCoreWithContext(ctx context.Context, r coreTestRequest) error {
	if r.SchemaVersion != 1 || !filepath.IsAbs(r.CorePath) || !filepath.IsAbs(r.ConfigFile) || !filepath.IsAbs(r.RuntimeDir) || r.TimeoutSec < 1 || r.TimeoutSec > 60 {
		return errors.New("invalid core-test request")
	}
	if !probePlatformSupported() {
		return errors.New("bounded core-test unsupported on this host")
	}
	ctx, cancel := context.WithTimeout(ctx, time.Duration(r.TimeoutSec)*time.Second)
	defer cancel()
	// Keep Linux's creating thread alive until its own validation child is reaped.
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()
	cmd := exec.CommandContext(ctx, r.CorePath, "-d", r.RuntimeDir, "-f", r.ConfigFile, "-t")
	if err := prepareProbeProcess(cmd); err != nil {
		return errors.New("core-test process isolation unavailable")
	}
	cmd.Env = probeCoreEnvironment()
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if err := cmd.Run(); err != nil {
		return errors.New("core-test rejected or deadline exceeded")
	}
	return nil
}

func runCoreTest(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: core-test REQUEST NEW_REPORT")
	}
	if _, err := os.Lstat(args[1]); !os.IsNotExist(err) {
		return errors.New("core-test output must be new")
	}
	raw, err := shRead(args[0], 65536)
	if err != nil {
		return err
	}
	var request coreTestRequest
	if err := shDecode(raw, &request); err != nil {
		return errors.New("invalid core-test request")
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM, syscall.SIGHUP)
	defer cancel()
	if err := validateCoreWithContext(ctx, request); err != nil {
		return err
	}
	return shWriteJSON(args[1], map[string]any{"schema_version": 1, "core_test": "accepted"}, true)
}
