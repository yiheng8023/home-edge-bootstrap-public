//go:build windows

package main

import (
	"errors"
	"os"
	"syscall"
	"unsafe"
)

var healthLockLibrary = syscall.NewLazyDLL("kernel32.dll")
var healthLockProc = healthLockLibrary.NewProc("LockFileEx")
var healthUnlockProc = healthLockLibrary.NewProc("UnlockFileEx")

func lockServiceHealthFile(file *os.File) error {
	var overlapped syscall.Overlapped
	ok, _, _ := healthLockProc.Call(file.Fd(), 3, 0, 1, 0, uintptr(unsafe.Pointer(&overlapped)))
	if ok == 0 {
		return errors.New("kernel lock unavailable")
	}
	return nil
}
func unlockServiceHealthFile(file *os.File) error {
	var overlapped syscall.Overlapped
	ok, _, _ := healthUnlockProc.Call(file.Fd(), 0, 1, 0, uintptr(unsafe.Pointer(&overlapped)))
	if ok == 0 {
		return errors.New("kernel unlock unavailable")
	}
	return nil
}

func serviceGlobalProcessAlive(pid int) bool {
	handle, err := syscall.OpenProcess(0x00100000, false, uint32(pid)) // SYNCHRONIZE
	if err != nil {
		return false
	}
	defer syscall.CloseHandle(handle)
	result, err := syscall.WaitForSingleObject(handle, 0)
	return err == nil && result == syscall.WAIT_TIMEOUT
}
