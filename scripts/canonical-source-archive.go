package main

import (
	"archive/tar"
	"compress/gzip"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

type entry struct {
	rel  string
	abs  string
	dir  bool
	size int64
}

func fail(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}

func collect(source string) ([]entry, []entry, error) {
	root, err := os.Lstat(source)
	if err != nil {
		return nil, nil, err
	}
	if root.Mode()&os.ModeSymlink != 0 || !root.IsDir() {
		return nil, nil, fmt.Errorf("source root must be a real directory")
	}
	var dirs, files []entry
	err = filepath.WalkDir(source, func(name string, item os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if name == source {
			return nil
		}
		if item.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("source entry is a symbolic link: %s", name)
		}
		info, err := item.Info()
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(source, name)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		if !utf8.ValidString(rel) || rel == "." || strings.HasPrefix(rel, "../") {
			return fmt.Errorf("invalid source path: %s", rel)
		}
		current := entry{rel: rel, abs: name, dir: info.IsDir(), size: info.Size()}
		switch {
		case info.IsDir():
			dirs = append(dirs, current)
		case info.Mode().IsRegular():
			files = append(files, current)
		default:
			return fmt.Errorf("unsupported source entry: %s", name)
		}
		return nil
	})
	if err != nil {
		return nil, nil, err
	}
	sort.Slice(dirs, func(i, j int) bool { return dirs[i].rel < dirs[j].rel })
	sort.Slice(files, func(i, j int) bool { return files[i].rel < files[j].rel })
	return dirs, files, nil
}

func header(name string, mode int64, size int64, kind byte, modified time.Time) *tar.Header {
	return &tar.Header{
		Name:       name,
		Mode:       mode,
		Uid:        0,
		Gid:        0,
		Size:       size,
		ModTime:    modified,
		Typeflag:   kind,
		Uname:      "",
		Gname:      "",
		AccessTime: time.Time{},
		ChangeTime: time.Time{},
		Format:     tar.FormatPAX,
	}
}

func build(source, archive, prefix string, epoch int64) (resultErr error) {
	dirs, files, err := collect(source)
	if err != nil {
		return err
	}
	parent := filepath.Dir(archive)
	if info, err := os.Lstat(archive); err == nil {
		return fmt.Errorf("archive already exists: %s (%s)", archive, info.Mode())
	} else if !os.IsNotExist(err) {
		return err
	}
	out, err := os.CreateTemp(parent, ".canonical-source-archive-*")
	if err != nil {
		return err
	}
	temporary := out.Name()
	committed := false
	closed := false
	defer func() {
		if !closed {
			if closeErr := out.Close(); resultErr == nil && closeErr != nil {
				resultErr = closeErr
			}
		}
		if !committed {
			_ = os.Remove(temporary)
		}
	}()

	modified := time.Unix(epoch, 0).UTC()
	compressed, err := gzip.NewWriterLevel(out, gzip.BestCompression)
	if err != nil {
		return err
	}
	compressed.Header.Name = ""
	compressed.Header.Comment = ""
	compressed.Header.ModTime = modified
	compressed.Header.OS = 255
	archiveWriter := tar.NewWriter(compressed)

	writeDirectory := func(name string) error {
		return archiveWriter.WriteHeader(header(name, 0o755, 0, tar.TypeDir, modified))
	}
	if err := writeDirectory(prefix); err != nil {
		return err
	}
	for _, item := range dirs {
		if err := writeDirectory(prefix + "/" + item.rel); err != nil {
			return err
		}
	}
	for _, item := range files {
		mode := int64(0o644)
		if strings.HasSuffix(item.rel, ".sh") {
			mode = 0o755
		}
		if err := archiveWriter.WriteHeader(header(prefix+"/"+item.rel, mode, item.size, tar.TypeReg, modified)); err != nil {
			return err
		}
		input, err := os.Open(item.abs)
		if err != nil {
			return err
		}
		copied, copyErr := io.Copy(archiveWriter, input)
		closeErr := input.Close()
		if copyErr != nil {
			return copyErr
		}
		if closeErr != nil {
			return closeErr
		}
		if copied != item.size {
			return fmt.Errorf("source file changed while archiving: %s", item.abs)
		}
	}
	if err := archiveWriter.Close(); err != nil {
		return err
	}
	if err := compressed.Close(); err != nil {
		return err
	}
	if err := out.Sync(); err != nil {
		return err
	}
	if err := out.Close(); err != nil {
		return err
	}
	closed = true
	if err := os.Rename(temporary, archive); err != nil {
		return err
	}
	committed = true
	return nil
}

func main() {
	if len(os.Args) != 5 {
		fail("usage: canonical-source-archive SOURCE ARCHIVE PREFIX EPOCH")
	}
	prefix := os.Args[3]
	if prefix == "" || prefix == "." || path.IsAbs(prefix) || path.Clean(prefix) != prefix || strings.Contains(prefix, "\\") || strings.HasPrefix(prefix, "../") {
		fail("invalid archive prefix: %s", prefix)
	}
	epoch, err := strconv.ParseInt(os.Args[4], 10, 64)
	if err != nil || epoch < 0 {
		fail("invalid source epoch: %s", os.Args[4])
	}
	if err := build(os.Args[1], os.Args[2], prefix, epoch); err != nil {
		fail("canonical source archive failed: %v", err)
	}
}
