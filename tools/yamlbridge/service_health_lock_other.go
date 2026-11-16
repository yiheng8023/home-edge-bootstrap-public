//go:build !linux && !darwin && !freebsd && !dragonfly && !netbsd && !openbsd && !windows

package main

import (
	"errors"
	"os"
)

func lockServiceHealthFile(*os.File) error   { return errors.New("kernel lock unsupported") }
func unlockServiceHealthFile(*os.File) error { return errors.New("kernel lock unsupported") }

func serviceGlobalProcessAlive(int) bool { return false }
