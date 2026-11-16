//go:build !linux

package main

import (
	"errors"
	"os/exec"
)

func probePlatformSupported() bool { return false }

func prepareProbeProcess(cmd *exec.Cmd) error {
	return errors.New("probe process isolation unsupported")
}
