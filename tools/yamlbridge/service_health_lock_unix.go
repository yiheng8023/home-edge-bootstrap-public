//go:build linux || darwin || freebsd || dragonfly || netbsd || openbsd

package main

import (
	"os"
	"syscall"
)

func lockServiceHealthFile(file *os.File) error {
	return syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
}
func unlockServiceHealthFile(file *os.File) error {
	return syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
}

func serviceGlobalProcessAlive(pid int) bool { return syscall.Kill(pid, 0) == nil }
