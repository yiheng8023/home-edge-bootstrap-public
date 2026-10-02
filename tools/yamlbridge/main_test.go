package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestRealYAMLVariations(t *testing.T) {
	for _, raw := range []string{
		"proxies: [{name: 'Tokyo: one', type: http, port: 443}]\ndns: {enable: true}\n",
		"base: &node {type: anytls, port: 443}\nproxies:\n  - <<: *node\n    name: 日本\n",
		`{"proxies":[{"name":"JP","password":"private-value"}],"rules":["MATCH,DIRECT"]}`,
	} {
		out, err := convert("decode", []byte(raw))
		if err != nil {
			t.Fatal(err)
		}
		var doc map[string]any
		if err = json.Unmarshal(out, &doc); err != nil {
			t.Fatal(err)
		}
		y, err := convert("encode", out)
		if err != nil {
			t.Fatal(err)
		}
		if _, err = convert("decode", y); err != nil {
			t.Fatal(err)
		}
	}
}

func TestRejectAmbiguousAndUnsafeInput(t *testing.T) {
	for _, raw := range []string{"x: 1\nx: 2", "x: 1\n---\nx: 2", "1: value", "[a, b]", "payload: [private-value"} {
		_, err := convert("decode", []byte(raw))
		if err == nil {
			t.Fatalf("accepted malformed fixture")
		}
		if strings.Contains(err.Error(), "private-value") {
			t.Fatal("source data leaked")
		}
	}
}
