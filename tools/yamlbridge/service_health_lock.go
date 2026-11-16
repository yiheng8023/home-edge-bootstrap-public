package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"runtime"
)

type serviceHealthLockRecord struct {
	Schema   int    `json:"schema"`
	Kind     string `json:"kind"`
	Identity string `json:"identity"`
}

// Kernel leases are released by process death and by reboot. The recognized,
// immutable file stays in place; deleting a lock file could create two writers
// holding locks on different inodes. Unknown/legacy locks are never adopted.
func acquireServiceHealthLock(dir string) (owned func() bool, release func(), err error) {
	path := filepath.Join(dir, "service-health.lock")
	var file *os.File
	for attempt := 0; attempt < 2; attempt++ {
		info, statErr := os.Lstat(path)
		if statErr == nil {
			if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || (runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0) {
				return nil, nil, errors.New("unknown service-health lock")
			}
			file, err = os.OpenFile(path, os.O_RDWR, 0)
			if err != nil {
				return nil, nil, errors.New("service-health lock unavailable")
			}
			if err = lockServiceHealthFile(file); err != nil {
				file.Close()
				return nil, nil, errors.New("service-health lock held")
			}
			break
		}
		if !os.IsNotExist(statErr) {
			return nil, nil, errors.New("service-health lock unavailable")
		}
		file, err = os.CreateTemp(dir, ".service-health-lock-*")
		if err != nil {
			return nil, nil, errors.New("cannot stage service-health lock")
		}
		temp := file.Name()
		cleanup := func() { _ = unlockServiceHealthFile(file); _ = file.Close(); _ = os.Remove(temp) }
		if err = lockServiceHealthFile(file); err != nil {
			cleanup()
			return nil, nil, errors.New("kernel lock unavailable")
		}
		var nonce [16]byte
		if _, err = rand.Read(nonce[:]); err != nil {
			cleanup()
			return nil, nil, errors.New("cannot initialize service-health lock")
		}
		record := serviceHealthLockRecord{Schema: 1, Kind: "service-health-kernel-lease", Identity: hex.EncodeToString(nonce[:])}
		raw, _ := json.Marshal(record)
		if _, err = file.Write(raw); err != nil {
			cleanup()
			return nil, nil, errors.New("cannot initialize service-health lock")
		}
		if err = file.Sync(); err != nil {
			cleanup()
			return nil, nil, errors.New("cannot persist service-health lock")
		}
		if err = os.Link(temp, path); err != nil {
			cleanup()
			file = nil
			if os.IsExist(err) {
				continue
			}
			return nil, nil, errors.New("cannot publish service-health lock")
		}
		_ = os.Remove(temp)
		break
	}
	if file == nil {
		return nil, nil, errors.New("service-health lock contended")
	}
	closeLease := func() { _ = unlockServiceHealthFile(file); _ = file.Close() }
	info, statErr := file.Stat()
	current, pathErr := os.Lstat(path)
	if statErr != nil || pathErr != nil || !current.Mode().IsRegular() || !os.SameFile(info, current) {
		closeLease()
		return nil, nil, errors.New("service-health lock changed")
	}
	if _, err = file.Seek(0, io.SeekStart); err != nil {
		closeLease()
		return nil, nil, errors.New("cannot read service-health lock")
	}
	raw, readErr := io.ReadAll(io.LimitReader(file, 4097))
	var record serviceHealthLockRecord
	if readErr != nil || len(raw) > 4096 || shDecode(raw, &record) != nil {
		closeLease()
		return nil, nil, errors.New("unknown service-health lock")
	}
	identity, decodeErr := hex.DecodeString(record.Identity)
	if record.Schema != 1 || record.Kind != "service-health-kernel-lease" || decodeErr != nil || len(identity) != 16 {
		closeLease()
		return nil, nil, errors.New("unknown service-health lock")
	}
	active := true
	owned = func() bool {
		if !active {
			return false
		}
		current, err := os.Lstat(path)
		if err != nil || !current.Mode().IsRegular() || current.Mode()&os.ModeSymlink != 0 || current.Size() != int64(len(raw)) || !os.SameFile(info, current) {
			return false
		}
		// Read through the current path, skipping the one byte leased on platforms
		// with byte-range locks. A replacement must not inherit our writer lease.
		check, err := os.Open(path)
		if err != nil {
			return false
		}
		defer check.Close()
		observed := make([]byte, len(raw)-1)
		n, err := check.ReadAt(observed, 1)
		return (err == nil || err == io.EOF) && n == len(observed) && bytes.Equal(observed, raw[1:])
	}
	release = func() {
		if active {
			active = false
			closeLease()
		}
	}
	return owned, release, nil
}
