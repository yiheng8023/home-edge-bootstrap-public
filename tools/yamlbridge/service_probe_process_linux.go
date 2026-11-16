//go:build linux

package main

import (
	"os/exec"
	"syscall"
)

func probePlatformSupported() bool { return true }

func prepareProbeProcess(cmd *exec.Cmd) error {
	cmd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGKILL}
	return nil
}
