package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"go.yaml.in/yaml/v3"
)

const setupFixture = `proxies:
  - {name: JP private, type: http, server: localhost, port: 1234, password: <example>}
proxy-groups:
  - {name: Shared AI, type: select, proxies: [JP private]}
rules:
  - DOMAIN-SUFFIX,google.com,Google
  - DOMAIN-SUFFIX,openai.com,Shared AI
  - MATCH,DIRECT
`

func setupRequest(names ...string) serviceSetupRequest {
	r := serviceSetupRequest{SchemaVersion: 1, RuntimeConfig: "source.yaml"}
	for _, n := range names {
		r.Services = append(r.Services, setupService{Name: n, InitialNode: "JP private", Mode: "auto"})
	}
	return r
}
func TestServiceSetupIsolationAndPreservation(t *testing.T) {
	raw := []byte(setupFixture)
	before := append([]byte(nil), raw...)
	groups := []byte("# user overlay\n- {name: User group, type: select, proxies: [JP private]}\n")
	rules := []byte("# user comment\nDOMAIN-SUFFIX,example.com,Shared AI\n")
	out, err := buildServiceSetup(setupRequest("gemini"), raw, groups, rules)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(raw, before) {
		t.Fatal("source bytes modified")
	}
	runtime, err := setupYAML(out["runtime.yaml"], yaml.MappingNode)
	if err != nil {
		t.Fatal(err)
	}
	seq := setupValue(runtime, "proxy-groups")
	if len(seq.Content) != 3 {
		t.Fatal("lost user group")
	}
	for _, g := range seq.Content[1:] {
		if setupValue(g, "include-all").Value != "true" {
			t.Fatal("candidate inventory missing")
		}
		for _, p := range setupValue(g, "proxies").Content {
			if p.Value != "JP private" && p.Value != "Edge-gemini-Auto" {
				t.Fatal("shared group dependency")
			}
		}
	}
	if setupValue(seq.Content[1], "proxies").Content[0].Value != "Edge-gemini-Auto" {
		t.Fatal("auto mode ordering")
	}
	rulesOut := setupValue(runtime, "rules")
	if rulesOut.Content[0].Value != "DOMAIN,gemini.google.com,Edge-gemini" {
		t.Fatal("managed rules not first")
	}
	for _, s := range []string{"DOMAIN-SUFFIX,google.com,Google", "DOMAIN-SUFFIX,openai.com,Shared AI", "MATCH,DIRECT"} {
		found := false
		for _, r := range rulesOut.Content {
			if r.Value == s {
				found = true
			}
		}
		if !found {
			t.Fatal("unowned rule lost")
		}
	}
	if strings.Contains(string(out["rules.yaml"]), "DOMAIN-SUFFIX,google.com,Edge-") || strings.Contains(string(out["rules.yaml"]), "DOMAIN-SUFFIX,googleapis.com,Edge-") {
		t.Fatal("blanket Google routing")
	}
	if !bytes.Contains(out["groups.yaml"], []byte("User group")) || !bytes.Contains(out["rules.yaml"], rules) {
		t.Fatal("unowned overlay lost")
	}
	if bytes.Contains(out["groups.yaml"], []byte("proxy-groups:")) {
		t.Fatal("overlay must be flat sequence")
	}
}
func TestServiceSetupManualAndIdempotent(t *testing.T) {
	req := setupRequest("gemini", "openai", "anthropic")
	req.Services[0].Mode = "manual"
	first, err := buildServiceSetup(req, []byte(setupFixture), nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	second, err := buildServiceSetup(req, first["runtime.yaml"], first["groups.yaml"], first["rules.yaml"])
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(first, second) {
		for n := range first {
			if !bytes.Equal(first[n], second[n]) {
				t.Errorf("non-idempotent %s\nFIRST %s\nSECOND %s", n, first[n], second[n])
			}
		}
	}
	runtime, _ := setupYAML(first["runtime.yaml"], yaml.MappingNode)
	group := setupValue(runtime, "proxy-groups").Content[1]
	if setupValue(group, "proxies").Content[0].Value != "JP private" {
		t.Fatal("manual initial selection not first")
	}
	// Updating Gemini must preserve the independent vendor groups and rules.
	only, err := buildServiceSetup(setupRequest("gemini"), first["runtime.yaml"], first["groups.yaml"], first["rules.yaml"])
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"Edge-openai", "Edge-anthropic"} {
		if !bytes.Contains(only["groups.yaml"], []byte(name)) || !bytes.Contains(only["rules.yaml"], []byte(name)) {
			t.Fatal("another profile was lost")
		}
	}
}
func TestServiceSetupRejectsAmbiguity(t *testing.T) {
	for _, tc := range []struct {
		name, runtime, groups, rules string
		req                          serviceSetupRequest
	}{
		{"duplicate root", setupFixture + "rules: []\n", "", "", setupRequest("gemini")},
		{"duplicate group fields", setupFixture, "- {name: A, name: B, type: select}", "", setupRequest("gemini")},
		{"multiple documents", setupFixture + "---\n{}", "", "", setupRequest("gemini")},
		{"reserved collision", strings.Replace(setupFixture, "name: Shared AI", "name: Edge-gemini", 1), "", "", setupRequest("gemini")},
		{"reserved overlay collision", setupFixture, "- {name: Edge-gemini, type: select, proxies: [JP private]}", "", setupRequest("gemini")},
		{"wrong overlay root", setupFixture, "proxy-groups: []", "", setupRequest("gemini")},
		{"proxy group namespace", strings.Replace(setupFixture, "name: Shared AI", "name: JP private", 1), "", "", setupRequest("gemini")},
		{"rule YAML mapping", setupFixture, "", "rules: []", setupRequest("gemini")},
		{"unclosed block", setupFixture, "", "# BEGIN home-edge-service:v1:gemini\n", setupRequest("gemini")},
		{"wrong managed block", setupFixture, "", "# BEGIN home-edge-service:v1:gemini\nMATCH,DIRECT\n# END home-edge-service:v1:gemini", setupRequest("gemini")},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := buildServiceSetup(tc.req, []byte(tc.runtime), []byte(tc.groups), []byte(tc.rules))
			if err == nil {
				t.Fatal("accepted ambiguous source")
			}
			if strings.Contains(err.Error(), "<example>") {
				t.Fatal("source leaked")
			}
		})
	}
	for _, mutate := range []func(*serviceSetupRequest){
		func(r *serviceSetupRequest) { r.SchemaVersion = 2 },
		func(r *serviceSetupRequest) { r.Services[0].Name = "google" },
		func(r *serviceSetupRequest) { r.Services[0].Mode = "url-test" },
		func(r *serviceSetupRequest) { r.Services[0].InitialNode = "Shared AI" },
		func(r *serviceSetupRequest) { r.Services[0].InitialNode = strings.Repeat("x", 513) },
		func(r *serviceSetupRequest) { r.Services[0].InitialNode = "JP private\n" },
		func(r *serviceSetupRequest) { r.Services = append(r.Services, r.Services[0]) },
	} {
		r := setupRequest("gemini")
		mutate(&r)
		if _, err := buildServiceSetup(r, []byte(setupFixture), nil, nil); err == nil {
			t.Fatal("accepted invalid request")
		}
	}
}

func TestServiceSetupNativeSequenceAndCommentStrippedRuntime(t *testing.T) {
	rules := []byte("# native overlay\n  - DOMAIN,example.com,DIRECT\n")
	first, err := buildServiceSetup(setupRequest("gemini", "openai"), []byte(setupFixture), nil, rules)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(first["rules.yaml"], []byte("  - DOMAIN,gemini.google.com,Edge-gemini")) || !bytes.Contains(first["rules.yaml"], rules) {
		t.Fatal("native overlay form or user bytes lost")
	}
	jsonRuntime, err := convert("decode", first["runtime.yaml"])
	if err != nil {
		t.Fatal(err)
	}
	stripped, err := convert("encode", jsonRuntime)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(stripped, []byte("home-edge-service")) {
		t.Fatal("fixture still has comments")
	}
	second, err := buildServiceSetup(setupRequest("gemini"), stripped, first["groups.yaml"], first["rules.yaml"])
	if err != nil {
		t.Fatal(err)
	}
	runtime, _ := setupYAML(second["runtime.yaml"], yaml.MappingNode)
	counts := map[string]int{}
	for _, r := range setupValue(runtime, "rules").Content {
		counts[r.Value]++
	}
	if counts[setupRules("gemini")[0]] != 1 || counts[setupRules("openai")[0]] != 1 {
		t.Fatal("managed rules duplicated or other service lost")
	}
	if _, err := buildServiceSetup(setupRequest("gemini"), stripped, nil, first["rules.yaml"]); err == nil {
		t.Fatal("reserved names adopted without persistent ownership")
	}
	changed := bytes.Replace(stripped, []byte("include-all: true"), []byte("include-all: false"), 1)
	if _, err := buildServiceSetup(setupRequest("gemini"), changed, first["groups.yaml"], first["rules.yaml"]); err == nil {
		t.Fatal("changed runtime shape adopted")
	}
}

func TestServiceSetupEmptyOverlayAndUnrelatedOutbound(t *testing.T) {
	raw := strings.Replace(setupFixture, "proxy-groups:", "  - {name: User direct, type: direct}\nproxy-groups:", 1)
	out, err := buildServiceSetup(setupRequest("gemini"), []byte(raw), []byte("# user empty overlay\n"), []byte("# user empty rules\n"))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(out["groups.yaml"], []byte("user empty overlay")) || !bytes.Contains(out["runtime.yaml"], []byte("User direct")) {
		t.Fatal("unowned content lost")
	}
}
func TestRunServiceSetupPrivateOutputAndHashes(t *testing.T) {
	dir := t.TempDir()
	source := filepath.Join(dir, "source.yaml")
	request := filepath.Join(dir, "request.json")
	output := filepath.Join(dir, "candidate")
	if err := os.WriteFile(source, []byte(setupFixture), 0600); err != nil {
		t.Fatal(err)
	}
	r := setupRequest("gemini")
	r.RuntimeConfig = source
	raw, _ := json.Marshal(r)
	if err := os.WriteFile(request, raw, 0600); err != nil {
		t.Fatal(err)
	}
	if err := runServiceSetup([]string{request, output}); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(source)
	if string(got) != setupFixture {
		t.Fatal("original source changed")
	}
	var manifest struct {
		Inputs  []setupFileDigest `json:"inputs"`
		Outputs []setupFileDigest `json:"outputs"`
	}
	m, _ := os.ReadFile(filepath.Join(output, "manifest.json"))
	if json.Unmarshal(m, &manifest) != nil {
		t.Fatal("invalid manifest")
	}
	if len(manifest.Inputs) != 2 || manifest.Inputs[1] != setupDigest(source, []byte(setupFixture)) {
		t.Fatal("input digest mismatch")
	}
	for _, d := range manifest.Outputs {
		b, err := os.ReadFile(filepath.Join(output, d.Path))
		if err != nil || setupDigest(d.Path, b) != d {
			t.Fatal("output digest mismatch")
		}
	}
	if err := runServiceSetup([]string{request, output}); err == nil {
		t.Fatal("existing output reused")
	}
	bad := []byte(`{"schema_version":1,"runtime_config":"nope","services":[],"unknown":true}`)
	_ = os.WriteFile(request, bad, 0600)
	if err := runServiceSetup([]string{request, filepath.Join(dir, "invalid")}); err == nil {
		t.Fatal("unknown request field accepted")
	}
}
