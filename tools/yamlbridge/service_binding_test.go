package main

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The controller fixture models fresh UUIDs on a synchronous config reload.
// Unlike the driver's pre-seeded receipts, these tests exercise the real
// receipt producer and consume its output through the real driver guard.
func bindingFixtureRequest(t *testing.T, f *healthFixture) (serviceBindRequest, string, string) {
	t.Helper()
	f.r.CorePath = filepath.Join(f.dir, "core")
	if err := os.WriteFile(f.r.CorePath, []byte("fixture-core"), 0700); err != nil {
		t.Fatal(err)
	}
	f.rebind()
	before := filepath.Join(f.dir, "before.json")
	if err := shWriteJSON(before, map[string]any{"proxies": f.g}, true); err != nil {
		t.Fatal(err)
	}
	hash, err := shConfigHash(f.r.RuntimeConfig)
	if err != nil {
		t.Fatal(err)
	}
	r := serviceBindRequest{SchemaVersion: 1, API: f.r.API, RuntimeConfig: f.r.RuntimeConfig, CorePath: f.r.CorePath, ExpectedRuntimeHash: hash, BeforeGraphFile: before}
	in, out := filepath.Join(f.dir, "bind-request.json"), filepath.Join(f.dir, "new-binding.json")
	return r, in, out
}

func writeBindingRequest(t *testing.T, path string, r serviceBindRequest) {
	t.Helper()
	if err := shWriteJSON(path, r, false); err != nil {
		t.Fatal(err)
	}
}

func TestServiceBindingPreflightNeverReloadsOrIssuesBinding(t *testing.T) {
	f := newHealthFixture(t)
	r, in, out := bindingFixtureRequest(t, f)
	writeBindingRequest(t, in, r)
	if err := runServiceBindCheck([]string{in, out}); err != nil {
		t.Fatal(err)
	}
	if f.reloads != 0 || len(f.puts) != 0 {
		t.Fatal("read-only preflight mutated controller")
	}
	raw, _ := os.ReadFile(out)
	if !strings.Contains(string(raw), `"binding_preflight":"passed"`) || strings.Contains(string(raw), `"node_instances"`) {
		t.Fatal("preflight produced a live binding")
	}
}

func TestServiceBindingOpaqueUnicodeAndCaseSensitiveNodeNames(t *testing.T) {
	f := newHealthFixture(t)
	replacements := map[string]string{"bad": "東京AI", "good": "東京ai"}
	graph := serviceHealthGraph{}
	for name, p := range f.g {
		if replacement, ok := replacements[name]; ok {
			name = replacement
		}
		if replacement, ok := replacements[p.Now]; ok {
			p.Now = replacement
		}
		for i, child := range p.All {
			if replacement, ok := replacements[child]; ok {
				p.All[i] = replacement
			}
		}
		graph[name] = p
	}
	f.g = graph
	runtimeSource := strings.ReplaceAll(strings.ReplaceAll(healthRuntimeConfig, "bad", "東京AI"), "good", "東京ai")
	if err := os.WriteFile(f.r.RuntimeConfig, []byte(runtimeSource), 0600); err != nil {
		t.Fatal(err)
	}
	r, in, out := bindingFixtureRequest(t, f)
	writeBindingRequest(t, in, r)
	if err := runServiceBindReload([]string{in, out}); err != nil {
		t.Fatal(err)
	}
	f.r.LoadedBindingFile = out
	if got := f.tick().Services[0]; got.State != "healthy" {
		t.Fatalf("opaque node names broke live binding: %+v", got)
	}
	raw, _ := os.ReadFile(out)
	var binding serviceLoadedBinding
	if decodeServiceLoadedBinding(raw, &binding) != nil || binding.NodeInstances["東京AI"] == binding.NodeInstances["東京ai"] {
		t.Fatal("distinct node names collapsed")
	}
	duplicate := strings.Replace(string(raw), `"schema_version":1`, `"schema_version":1,"Schema_version":1`, 1)
	if decodeServiceLoadedBinding([]byte(duplicate), &binding) == nil {
		t.Fatal("schema case alias accepted")
	}
}

func TestServiceBindingControlledReloadAndDriver(t *testing.T) {
	f := newHealthFixture(t)
	// A rule provider is a matcher. Its outbound target is in static rules and
	// cannot independently replace an inline node definition.
	if err := os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nrule-providers:\n  known: {type: file, behavior: domain, path: rules.yaml}\nrules: ['RULE-SET,known,Edge-gemini']\n"), 0600); err != nil {
		t.Fatal(err)
	}
	r, in, out := bindingFixtureRequest(t, f)
	writeBindingRequest(t, in, r)
	if err := runServiceBindReload([]string{in, out}); err != nil {
		t.Fatal(err)
	}
	if f.reloads != 1 || len(f.puts) != 0 {
		t.Fatalf("reload was not a single controlled transaction: reloads=%d selectors=%v", f.reloads, f.puts)
	}
	raw, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	var receipt serviceLoadedBinding
	if shDecode(raw, &receipt) != nil || len(receipt.NodeInstances) != 9 || receipt.RuntimeHash != r.ExpectedRuntimeHash || receipt.Kind != loadedBindingKind {
		t.Fatal("invalid successful receipt")
	}
	for name, id := range receipt.NodeInstances {
		if !bindingUUID(id) || f.g[name].ID != id {
			t.Fatal("receipt not bound to loaded instances")
		}
	}
	f.r.LoadedBindingFile = out
	f.r.FailChecks = 1
	if got := f.tick().Services[0]; got.State != "repaired" || len(f.puts) != 1 {
		t.Fatalf("real receipt did not authorize dedicated repair: %+v %v", got, f.puts)
	}
	if err := runServiceBindReload([]string{in, out}); err == nil || err.Error() != "binding_output_must_be_new" || f.reloads != 1 {
		t.Fatal("existing output allowed another reload")
	}
}

func TestServiceBindingRefusesBeforeReload(t *testing.T) {
	for _, kind := range []string{"source-drift", "graph-drift", "unknown-version", "missing-instance", "proxy-provider", "rule-mode", "missing-core", "duplicate-request", "remote-controller"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			r, in, out := bindingFixtureRequest(t, f)
			switch kind {
			case "source-drift":
				os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nrevision: 2\n"), 0600)
			case "graph-drift":
				f.change("Manual", "good")
			case "unknown-version":
				f.version = "v1.19.35"
			case "missing-instance":
				p := f.g["bad"]
				p.ID = ""
				f.g["bad"] = p
				shWriteJSON(r.BeforeGraphFile, map[string]any{"proxies": f.g}, false)
			case "proxy-provider":
				os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nproxy-providers:\n  dynamic: {type: file, path: nodes.yaml}\n"), 0600)
				r.ExpectedRuntimeHash, _ = shConfigHash(f.r.RuntimeConfig)
			case "rule-mode":
				f.mode = "global"
			case "missing-core":
				os.Remove(r.CorePath)
			case "remote-controller":
				r.API = "http://192.0.2.1:9999"
			}
			writeBindingRequest(t, in, r)
			if kind == "duplicate-request" {
				raw, _ := os.ReadFile(in)
				raw = []byte(strings.Replace(string(raw), `"schema_version":1`, `"schema_version":1,"schema_version":1`, 1))
				os.WriteFile(in, raw, 0600)
			}
			err := runServiceBindReload([]string{in, out})
			if err == nil || f.reloads != 0 || len(f.puts) != 0 {
				t.Fatalf("unsafe reload: %v reloads=%d", err, f.reloads)
			}
			if _, err := os.Lstat(out); !os.IsNotExist(err) {
				t.Fatal("unverified binding output exists")
			}
		})
	}
}

func TestServiceBindingUncertainOrUnverifiedReloadHasNoReceipt(t *testing.T) {
	for _, kind := range []string{"unchanged-instances", "failed-but-applied", "post-source-change", "post-core-change", "post-graph-unavailable", "post-mode-change", "duplicate-instances"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			r, in, out := bindingFixtureRequest(t, f)
			want := "binding_post_reload_unverified"
			switch kind {
			case "unchanged-instances":
				f.reloadNoChange = true
			case "failed-but-applied":
				f.reloadFailure = true
				want = "binding_reload_unconfirmed"
			case "post-source-change":
				f.onReload = func() { os.WriteFile(r.RuntimeConfig, []byte(healthRuntimeConfig+"\nrevision: 2\n"), 0600) }
			case "post-core-change":
				f.onReload = func() { os.WriteFile(r.CorePath, []byte("changed-core-binary"), 0700) }
			case "post-graph-unavailable":
				f.onReload = func() { f.graphUnavailable = true }
			case "post-mode-change":
				f.onReload = func() { f.mode = "direct" }
			case "duplicate-instances":
				f.onReload = func() {
					p := f.g["good"]
					p.ID = f.g["bad"].ID
					f.g["good"] = p
				}
			}
			writeBindingRequest(t, in, r)
			err := runServiceBindReload([]string{in, out})
			if err == nil || err.Error() != want || f.reloads != 1 || len(f.puts) != 0 {
				t.Fatalf("unexpected unsafe reload result: %v reloads=%d", err, f.reloads)
			}
			if _, err := os.Lstat(out); !os.IsNotExist(err) {
				t.Fatal("uncertain reload minted a binding")
			}
		})
	}
}

func TestServiceHealthLoadedDefinitionGuard(t *testing.T) {
	for _, kind := range []string{"missing", "same-name-new-instance", "source-drift", "same-instance-config-patch", "core-change", "proxy-provider", "version-change", "duplicate-receipt"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			calls := 0
			original := serviceHealthProbe
			serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
				calls++
				return original(ctx, profile, config, node, core, timeout)
			}
			switch kind {
			case "missing":
				f.r.LoadedBindingFile = ""
			case "same-name-new-instance":
				f.mu.Lock()
				f.bumpInstancesLocked()
				f.mu.Unlock()
			case "source-drift":
				os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nrevision: 2\n"), 0600)
			case "same-instance-config-patch":
				f.liveInterface = "other-egress"
			case "core-change":
				f.r.CorePath = "/proc/new-core-instance/exe"
			case "proxy-provider":
				os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nproxy-providers: {dynamic: {type: file, path: nodes.yaml}}\n"), 0600)
			case "version-change":
				f.version = "v9.0.0"
			case "duplicate-receipt":
				raw, _ := os.ReadFile(f.r.LoadedBindingFile)
				os.WriteFile(f.r.LoadedBindingFile, []byte(strings.Replace(string(raw), `"schema_version":1`, `"schema_version":1,"schema_version":1`, 1)), 0600)
			}
			got := f.tick().Services[0]
			if got.State != "observe_only" || got.ProbeState != "unknown" || !strings.HasPrefix(got.ProbeReason, "loaded_definition_") || calls != 0 || len(f.puts) != 0 {
				t.Fatalf("unbound source authorized a probe/repair: %+v calls=%d puts=%v", got, calls, f.puts)
			}
		})
	}
}

func TestServiceHealthPendingBindingLossNeverReplays(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	f.putFailure, f.hideGraphAfterPut = true, true
	if first := f.tick().Services[0]; !first.Pending || len(f.puts) != 1 {
		t.Fatalf("no uncertain transaction: %+v", first)
	}
	f.graphUnavailable, f.hideGraphAfterPut, f.putFailure = false, false, false
	f.liveInterface = "changed-after-dispatch"
	if second := f.tick().Services[0]; second.State != "observe_only" || !second.Pending || len(f.puts) != 1 {
		t.Fatalf("unbound recovery replayed: %+v %v", second, f.puts)
	}
	state, err := shLoadState(filepath.Join(f.r.StateDir, "service-health.json"), serviceHealthNow().Unix())
	if err != nil || state.Services["gemini"].Pending == nil {
		t.Fatal("unresolved transaction responsibility discarded")
	}
}

func TestServiceHealthInstanceChangeDuringProbeCancelsWrite(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	original := serviceHealthProbe
	serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
		result, err := original(ctx, profile, config, node, core, timeout)
		if node == "good" {
			f.mu.Lock()
			f.bumpInstancesLocked()
			f.mu.Unlock()
		}
		return result, err
	}
	f.tick()
	if len(f.puts) != 0 {
		t.Fatalf("probe for replaced instances authorized a write: %v", f.puts)
	}
}

func TestServiceBindingUUIDAndStrictGraph(t *testing.T) {
	if !bindingUUID("00000001-0001-4000-8000-000000000001") || bindingUUID("00000001-0001-1000-8000-000000000001") {
		t.Fatal("instance UUID version validation")
	}
	if _, err := bindingGraph([]byte(`{"proxies":{"node":{"type":"Vless","id":"a","id":"b"}}}`)); err == nil {
		t.Fatal("ambiguous instance graph accepted")
	}
}
