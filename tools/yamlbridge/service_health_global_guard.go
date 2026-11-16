package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
)

const serviceGlobalLockEnv = "HOME_EDGE_SERVICE_GLOBAL_LOCK"
const serviceGlobalTokenEnv = "HOME_EDGE_SERVICE_GLOBAL_TOKEN"
const serviceGlobalPIDEnv = "HOME_EDGE_SERVICE_GLOBAL_PID"

type serviceGlobalFile struct {
	info os.FileInfo
	raw  []byte
}

// These optional facts are supplied together by the wrapper that owns the
// shared directory lock. They do not authorize taking or recovering that lock.
// A direct CLI invocation without them retains its engine lease protection.
func captureServiceGlobalGuard() (func() bool, error) {
	path, token, pidText := os.Getenv(serviceGlobalLockEnv), os.Getenv(serviceGlobalTokenEnv), os.Getenv(serviceGlobalPIDEnv)
	if path == "" && token == "" && pidText == "" {
		return nil, nil
	}
	invalid := func() (func() bool, error) { return nil, errors.New("global_writer_ownership_unverified") }
	root := "/tmp"
	if runtime.GOOS == "windows" {
		root = os.TempDir()
	}
	root = filepath.Clean(root)
	if !filepath.IsAbs(path) || filepath.Clean(path) != path || path == root {
		return invalid()
	}
	relative, err := filepath.Rel(root, path)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
		return invalid()
	}
	pid, err := strconv.Atoi(pidText)
	if err != nil || pid <= 1 || strconv.Itoa(pid) != pidText || pid != os.Getppid() || !serviceGlobalProcessAlive(pid) {
		return invalid()
	}
	prefix, suffix := "home-edge-service-run.", "."+pidText
	if !strings.HasPrefix(token, prefix) || !strings.HasSuffix(token, suffix) || len(token) > 160 || len(token) < len(prefix)+6+len(suffix) {
		return invalid()
	}
	for _, character := range token {
		if !((character >= 'A' && character <= 'Z') || (character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '.' || character == '-' || character == '_') {
			return invalid()
		}
	}
	// Snapshot every path component so an ancestor symlink/replacement cannot
	// silently move our ownership checks onto a different lock directory.
	directories := map[string]os.FileInfo{}
	for directory := path; ; directory = filepath.Dir(directory) {
		info, err := os.Lstat(directory)
		if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return invalid()
		}
		if directory == path && runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0 {
			return invalid()
		}
		directories[directory] = info
		if filepath.Dir(directory) == directory {
			break
		}
	}
	files := map[string]serviceGlobalFile{}
	for _, name := range []string{"pid", "operation", "started_at", "service-health.owner"} {
		file := filepath.Join(path, name)
		info, err := os.Lstat(file)
		if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || (runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0) {
			return invalid()
		}
		raw, err := shRead(file, 256)
		if err != nil {
			return invalid()
		}
		files[name] = serviceGlobalFile{info: info, raw: raw}
	}
	if string(files["pid"].raw) != pidText+"\n" || string(files["operation"].raw) != "service-health\n" || string(files["service-health.owner"].raw) != token+"\n" {
		return invalid()
	}
	started := strings.TrimSuffix(string(files["started_at"].raw), "\n")
	when, err := strconv.ParseInt(started, 10, 64)
	if err != nil || when <= 0 || strconv.FormatInt(when, 10) != started || string(files["started_at"].raw) != started+"\n" {
		return invalid()
	}
	owned := func() bool {
		if os.Getppid() != pid || !serviceGlobalProcessAlive(pid) {
			return false
		}
		for directory, expected := range directories {
			current, err := os.Lstat(directory)
			if err != nil || !current.IsDir() || current.Mode() != expected.Mode() || !os.SameFile(current, expected) {
				return false
			}
		}
		entries, err := os.ReadDir(path)
		if err != nil || len(entries) != len(files) {
			return false
		}
		for name, expected := range files {
			file := filepath.Join(path, name)
			current, err := os.Lstat(file)
			if err != nil || !current.Mode().IsRegular() || current.Mode() != expected.info.Mode() || !os.SameFile(current, expected.info) || current.Size() != expected.info.Size() || !current.ModTime().Equal(expected.info.ModTime()) {
				return false
			}
			raw, err := shRead(file, 256)
			if err != nil || !bytes.Equal(raw, expected.raw) {
				return false
			}
		}
		return true
	}
	if !owned() {
		return invalid()
	}
	return owned, nil
}
