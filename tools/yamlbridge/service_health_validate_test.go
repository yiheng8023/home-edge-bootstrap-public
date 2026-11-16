package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestRegistrationValidationBeforeShellTransform(t *testing.T) {
	base := `"schema_version":1,"mode":"observe","api":"http://127.0.0.1:9999","secret_file":"/private/credential","runtime_config":"/runtime.yaml","core_path":"/core","state_dir":"/state","services":[{"name":"gemini","selector":"Edge-gemini","auto_selector":"Edge-gemini-Auto"}]`
	for _, tc := range []struct {
		name, raw string
		valid     bool
	}{
		{"valid", "{" + base + "}", true},
		{"duplicate_mode", "{" + base + `,"mode":"auto"}`, false},
		{"case_alias", "{" + base + `,"Mode":"auto"}`, false},
		{"unknown", "{" + base + `,"unrecognized":true}`, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			input := filepath.Join(dir, "request.json")
			output := filepath.Join(dir, "validated.json")
			if err := os.WriteFile(input, []byte(tc.raw), 0600); err != nil {
				t.Fatal(err)
			}
			err := runServiceHealthValidate([]string{input, output})
			if (err == nil) != tc.valid {
				t.Fatalf("valid=%v error=%v", tc.valid, err)
			}
			if !tc.valid {
				if _, err := os.Stat(output); !os.IsNotExist(err) {
					t.Fatal("invalid request created output")
				}
			}
			after, _ := os.ReadFile(input)
			if string(after) != tc.raw {
				t.Fatal("registration was modified")
			}
			if tc.valid && runServiceHealthValidate([]string{input, output}) == nil {
				t.Fatal("overwrote an existing output")
			}
		})
	}
}
