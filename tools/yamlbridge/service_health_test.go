package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"home-edge-bootstrap/yamlbridge/internal/healthpolicy"
)

type healthFixture struct {
	t                 *testing.T
	dir               string
	r                 serviceHealthRequest
	mu                sync.Mutex
	g                 serviceHealthGraph
	puts              []string
	putFailure        bool
	putNoApply        bool
	authorizations    []string
	count             int
	mode              string
	modeMissing       bool
	graphUnavailable  bool
	hideGraphAfterPut bool
	onPut             func()
	generation        int
	reloads           int
	reloadNoChange    bool
	reloadFailure     bool
	version           string
	liveInterface     string
	onReload          func()
}

const healthRuntimeConfig = `proxies:
  - {name: bad, type: vless, server: bad.example, port: 443}
  - {name: good, type: vless, server: good.example, port: 443}
  - {name: third, type: vless, server: third.example, port: 443}
  - {name: a, type: vless, server: a.example, port: 443}
  - {name: b, type: vless, server: b.example, port: 443}
  - {name: c, type: vless, server: c.example, port: 443}
  - {name: d, type: vless, server: d.example, port: 443}
  - {name: e, type: vless, server: e.example, port: 443}
  - {name: z, type: vless, server: z.example, port: 443}
proxy-groups:
  - name: Edge-gemini
    type: select
    proxies: [Edge-gemini-Auto, Manual]
  - name: Edge-gemini-Auto
    type: select
    proxies: [bad, good]
  - name: Edge-openai
    type: select
    proxies: [Edge-openai-Auto, Manual]
  - name: Edge-openai-Auto
    type: select
    proxies: [bad, good]
  - name: Edge-anthropic
    type: select
    proxies: [Edge-anthropic-Auto, Manual]
  - name: Edge-anthropic-Auto
    type: select
    proxies: [bad, good]
`

// macOS exposes its temporary directory through /var -> /private/var. Tests
// exercise real private directories, while production deliberately rejects
// symlink ancestors in caller-supplied state paths.
func canonicalHealthTempDir(t *testing.T) string {
	t.Helper()
	path, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return path
}

func newHealthFixture(t *testing.T) *healthFixture {
	t.Helper()
	f := &healthFixture{t: t, dir: canonicalHealthTempDir(t), g: serviceHealthGraph{}, mode: "rule", version: loadedBindingVersion}
	for _, name := range []string{"gemini", "openai", "anthropic"} {
		outer, auto := "Edge-"+name, "Edge-"+name+"-Auto"
		f.g[outer] = serviceHealthProxy{Type: "Selector", Now: auto, All: []string{auto, "Manual"}}
		f.g[auto] = serviceHealthProxy{Type: "Selector", Now: "bad", All: []string{"bad", "good"}}
	}
	f.g["bad"] = serviceHealthProxy{Type: "Vless"}
	f.g["good"] = serviceHealthProxy{Type: "Vless"}
	f.g["third"] = serviceHealthProxy{Type: "Vless"}
	for _, name := range []string{"a", "b", "c", "d", "e", "z"} {
		f.g[name] = serviceHealthProxy{Type: "Vless"}
	}
	f.g["Manual"] = serviceHealthProxy{Type: "Selector", Now: "bad", All: []string{"bad", "good"}}
	for i := 0; i < 13; i++ {
		f.g[fmt.Sprintf("Other-%d", i)] = serviceHealthProxy{Type: "Selector", Now: "bad", All: []string{"bad", "good"}}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.authorizations = append(f.authorizations, req.Header.Get("Authorization"))
		if req.Method == "GET" && req.URL.Path == "/version" {
			json.NewEncoder(w).Encode(map[string]any{"version": f.version})
			return
		}
		if req.Method == "GET" && req.URL.Path == "/configs" {
			if f.modeMissing {
				json.NewEncoder(w).Encode(map[string]any{})
			} else {
				json.NewEncoder(w).Encode(f.configsLocked())
			}
			return
		}
		if req.Method == "PUT" && req.URL.Path == "/configs" {
			var body map[string]string
			original, _ := os.ReadFile(f.r.RuntimeConfig)
			if json.NewDecoder(req.Body).Decode(&body) != nil || len(body) != 1 || body["payload"] != string(original) {
				w.WriteHeader(400) // Configured files outside the home root reject explicit path reloads.
				return
			}
			f.reloads++
			if !f.reloadNoChange {
				f.bumpInstancesLocked()
			}
			if f.onReload != nil {
				f.onReload()
			}
			if f.reloadFailure {
				w.WriteHeader(500)
			} else {
				w.WriteHeader(204)
			}
			return
		}
		if req.Method == "GET" && req.URL.Path == "/proxies" {
			if f.graphUnavailable {
				w.WriteHeader(503)
				return
			}
			json.NewEncoder(w).Encode(map[string]any{"proxies": f.g})
			return
		}
		if req.Method == "PUT" && strings.HasPrefix(req.URL.Path, "/proxies/") {
			var body struct {
				Name string `json:"name"`
			}
			if json.NewDecoder(req.Body).Decode(&body) != nil {
				w.WriteHeader(400)
				return
			}
			group := strings.TrimPrefix(req.URL.Path, "/proxies/")
			if f.onPut != nil {
				f.onPut()
			}
			f.puts = append(f.puts, group+"="+body.Name)
			if !f.putNoApply {
				p := f.g[group]
				p.Now = body.Name
				f.g[group] = p
			}
			if f.hideGraphAfterPut {
				f.graphUnavailable = true
			}
			if f.putFailure {
				w.WriteHeader(500)
			} else {
				w.WriteHeader(204)
			}
			return
		}
		w.WriteHeader(404)
	}))
	t.Cleanup(server.Close)
	f.r = serviceHealthRequest{SchemaVersion: 1, Mode: "auto", API: server.URL, RuntimeConfig: filepath.Join(f.dir, "runtime.yaml"), CorePath: "unused-core", StateDir: filepath.Join(f.dir, "state"), Services: []serviceHealthSpec{{Name: "gemini", Selector: "Edge-gemini", AutoSelector: "Edge-gemini-Auto"}}}
	if err := os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig), 0600); err != nil {
		t.Fatal(err)
	}
	f.r.LoadedBindingFile = filepath.Join(f.dir, "loaded-binding.json")
	f.rebind()
	oldProbe, oldNow := serviceHealthProbe, serviceHealthNow
	serviceHealthNow = func() time.Time { return time.Unix(1800000000, 0) }
	serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
		state := "frontend_available"
		if profile == "gemini" && node == "bad" {
			state = "region_denied"
		}
		return serviceProbeResult{Profile: profile, Node: node, State: state, EgressBound: true}, nil
	}
	t.Cleanup(func() { serviceHealthProbe = oldProbe; serviceHealthNow = oldNow })
	return f
}

func (f *healthFixture) configsLocked() map[string]any {
	m := map[string]any{"mode": f.mode}
	if f.liveInterface != "" {
		m["interface-name"] = f.liveInterface
	}
	return m
}
func (f *healthFixture) bumpInstancesLocked() {
	f.generation++
	i := 0
	for name, p := range f.g {
		i++
		p.ID = fmt.Sprintf("%08x-%04x-4000-8000-%012x", f.generation, i, i)
		f.g[name] = p
	}
}
func (f *healthFixture) rebind() {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.bumpInstancesLocked()
	config, _ := json.Marshal(f.configsLocked())
	digest := sha256.Sum256(config)
	instances := map[string]string{}
	names, err := bindingInlineNames(f.r.RuntimeConfig)
	if err != nil {
		f.t.Fatal(err)
	}
	for _, name := range names {
		instances[name] = f.g[name].ID
	}
	hash, _ := shConfigHash(f.r.RuntimeConfig)
	binding := serviceLoadedBinding{SchemaVersion: 1, Kind: loadedBindingKind, UpstreamVersion: loadedBindingVersion, RuntimeHash: hash, CoreIdentity: shCoreIdentity(f.r.CorePath), ConfigsHash: hex.EncodeToString(digest[:]), NodeInstances: instances}
	if err := shWriteJSON(f.r.LoadedBindingFile, binding, false); err != nil {
		f.t.Fatal(err)
	}
}

func (f *healthFixture) change(name, node string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	p := f.g[name]
	p.Now = node
	f.g[name] = p
}
func (f *healthFixture) tick() serviceHealthReport {
	f.t.Helper()
	f.count++
	in, out := filepath.Join(f.dir, fmt.Sprintf("request-%d.json", f.count)), filepath.Join(f.dir, fmt.Sprintf("report-%d.json", f.count))
	b, _ := json.Marshal(f.r)
	if err := os.WriteFile(in, b, 0600); err != nil {
		f.t.Fatal(err)
	}
	if err := runServiceHealth([]string{in, out}); err != nil {
		f.t.Fatal(err)
	}
	b, err := os.ReadFile(out)
	if err != nil {
		f.t.Fatal(err)
	}
	if strings.Contains(string(b), "bad") || strings.Contains(string(b), "good") || strings.Contains(string(b), "Bearer") || strings.Contains(string(b), "private-secret") {
		f.t.Fatalf("private identity in report: %s", b)
	}
	var report serviceHealthReport
	if json.Unmarshal(b, &report) != nil {
		f.t.Fatal("invalid report")
	}
	return report
}

func TestServiceHealthGoogleOnlyRepair(t *testing.T) {
	f := newHealthFixture(t)
	for _, name := range []string{"openai", "anthropic"} {
		f.r.Services = append(f.r.Services, serviceHealthSpec{Name: name, Selector: "Edge-" + name, AutoSelector: "Edge-" + name + "-Auto"})
	}
	for i := 0; i < 2; i++ {
		r := f.tick()
		if r.Services[0].State != "failure_pending" {
			t.Fatalf("premature action: %+v", r)
		}
	}
	r := f.tick()
	if r.Services[0].State != "repaired" {
		t.Fatalf("no repair: %+v", r)
	}
	if len(f.puts) != 1 || f.puts[0] != "Edge-gemini-Auto=good" {
		t.Fatalf("unexpected writes: %v", f.puts)
	}
	for name, p := range f.g {
		if strings.HasPrefix(name, "Other-") || name == "Manual" || name == "Edge-openai-Auto" || name == "Edge-anthropic-Auto" {
			if p.Now != "bad" {
				t.Fatalf("other selector moved: %s", name)
			}
		}
	}
	s, err := shLoadState(filepath.Join(f.r.StateDir, "service-health.json"), serviceHealthNow().Unix())
	if err != nil || len(s.Attempts) != 1 {
		t.Fatalf("reservation not released: %+v %v", s, err)
	}
}

func TestServiceHealthObserveNeverWritesStateOrController(t *testing.T) {
	f := newHealthFixture(t)
	f.r.Mode = "observe"
	for i := 0; i < 4; i++ {
		if state := f.tick().Services[0].State; state != "observed" {
			t.Fatal(state)
		}
	}
	if len(f.puts) != 0 {
		t.Fatal(f.puts)
	}
	if _, err := os.Stat(f.r.StateDir); !os.IsNotExist(err) {
		t.Fatal("observe created state")
	}
}

func TestServiceHealthIncludeAllRepeatedSeedIsOneCandidate(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	g := f.g["Edge-gemini-Auto"]
	g.All = []string{"bad", "bad", "good", "good"}
	f.g["Edge-gemini-Auto"] = g
	if !shOwned(f.g, f.r.Services[0]) {
		t.Fatal("native include-all repeated seed refused")
	}
	if got := f.tick().Services[0]; got.State != "repaired" || len(f.puts) != 1 {
		t.Fatalf("repeated native seed broke isolated repair: %+v", got)
	}
}

func TestServiceHealthUnknownAndUnboundDoNotRepair(t *testing.T) {
	for _, kind := range []string{"unknown", "rate", "unbound", "wrong-node", "wrong-profile", "challenge", "auth"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
				r := serviceProbeResult{Profile: profile, Node: node, State: "region_denied", EgressBound: true}
				switch kind {
				case "unknown":
					r.State = "unknown"
				case "rate":
					r.HTTPStatus = 429
				case "unbound":
					r.EgressBound = false
				case "wrong-node":
					r.Node = "other"
				case "wrong-profile":
					r.Profile = "openai"
				case "challenge":
					r.State = "challenge"
				case "auth":
					r.HTTPStatus = 401
				}
				return r, nil
			}
			for i := 0; i < 3; i++ {
				if state := f.tick().Services[0].State; state != "unknown" {
					t.Fatal(state)
				}
			}
			if len(f.puts) != 0 {
				t.Fatal(f.puts)
			}
		})
	}
}

func TestServiceHealthUnknownResetsFailureSequence(t *testing.T) {
	f := newHealthFixture(t)
	f.tick()
	f.tick()
	old := serviceHealthProbe
	serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
		return serviceProbeResult{Profile: p, Node: n, State: "unknown", EgressBound: true}, nil
	}
	f.tick()
	serviceHealthProbe = old
	r := f.tick()
	if r.Services[0].Failures != 1 || len(f.puts) != 0 {
		t.Fatalf("nonconsecutive failures repaired: %+v", r)
	}
}

func TestServiceHealthManualNestedAndOwnership(t *testing.T) {
	for _, kind := range []string{"manual", "shared", "nested", "readonly"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			switch kind {
			case "manual":
				f.change("Edge-gemini", "Manual")
			case "shared":
				f.g["Shared"] = serviceHealthProxy{Type: "Selector", Now: "Edge-gemini-Auto", All: []string{"Edge-gemini-Auto"}}
			case "nested":
				p := f.g["Edge-gemini-Auto"]
				p.All = append(p.All, "Manual")
				f.g["Edge-gemini-Auto"] = p
			case "readonly":
				p := f.g["Edge-gemini-Auto"]
				p.Type = "URLTest"
				f.g["Edge-gemini-Auto"] = p
			}
			if kind != "manual" {
				serviceHealthProbe = func(context.Context, string, string, string, string, time.Duration) (serviceProbeResult, error) {
					t.Fatal("unowned branch probed")
					return serviceProbeResult{}, nil
				}
			}
			r := f.tick()
			if len(f.puts) != 0 || r.Services[0].State == "repaired" {
				t.Fatal(r)
			}
			if kind == "manual" && (r.Services[0].State != "manual_held" || r.Services[0].ProbeState != "region_denied") {
				t.Fatalf("manual health was hidden: %+v", r)
			}
		})
	}
}

func TestServiceHealthCandidateRacesCancel(t *testing.T) {
	for _, kind := range []string{"manual", "member", "other-group", "config"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			old := serviceHealthProbe
			serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
				if n == "good" {
					switch kind {
					case "manual":
						f.change("Edge-gemini", "Manual")
					case "other-group":
						f.change("Other-0", "good")
					case "member":
						f.mu.Lock()
						a := f.g["Edge-gemini-Auto"]
						a.All = append(a.All, "third")
						f.g["Edge-gemini-Auto"] = a
						f.mu.Unlock()
					case "config":
						os.WriteFile(f.r.RuntimeConfig, []byte("changed: true"), 0600)
					}
				}
				return old(ctx, p, c, n, k, d)
			}
			r := f.tick()
			if r.Services[0].State != "selection_changed" || len(f.puts) != 0 {
				t.Fatalf("stale plan applied: %+v %v", r, f.puts)
			}
		})
	}
}

func TestServiceHealthRollbackAndLaterChoice(t *testing.T) {
	for _, kind := range []string{"restore", "user-auto", "user-outer"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			old := serviceHealthProbe
			goodCalls := 0
			serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
				if n == "good" {
					goodCalls++
					if goodCalls == 2 {
						if kind == "user-auto" {
							f.change("Edge-gemini-Auto", "third")
						}
						if kind == "user-outer" {
							f.change("Edge-gemini", "Manual")
						}
						return serviceProbeResult{Profile: p, Node: n, State: "transport_failed", EgressBound: true}, nil
					}
				}
				return old(ctx, p, c, n, k, d)
			}
			r := f.tick()
			if kind == "restore" {
				if r.Services[0].State != "rolled_back" || len(f.puts) != 2 || f.g["Edge-gemini-Auto"].Now != "bad" {
					t.Fatalf("rollback missing: %+v %v", r, f.puts)
				}
			} else {
				if len(f.puts) != 1 || r.Services[0].State != "selection_changed_or_unresolved" {
					t.Fatalf("later choice overwritten: %+v %v", r, f.puts)
				}
			}
		})
	}
}

func TestServiceHealthPUTUncertainAppliedAndFailed(t *testing.T) {
	for _, noApply := range []bool{false, true} {
		t.Run(fmt.Sprint(noApply), func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			f.putFailure = true
			f.putNoApply = noApply
			r := f.tick()
			want := "repaired"
			if noApply {
				want = "switch_failed"
			}
			if r.Services[0].State != want || len(f.puts) != 1 {
				t.Fatalf("uncertain PUT mishandled: %+v", r)
			}
		})
	}
}

func TestServiceHealthBudgetCooldownAndFingerprint(t *testing.T) {
	t.Run("budget", func(t *testing.T) {
		f := newHealthFixture(t)
		f.r.FailChecks = 1
		f.r.MaxAttempts = 1
		r := f.tick()
		if r.Services[0].State != "attempt_budget" || len(f.puts) != 0 {
			t.Fatal(r)
		}
	})
	t.Run("cooldown", func(t *testing.T) {
		f := newHealthFixture(t)
		f.r.FailChecks = 1
		old := serviceHealthProbe
		goodCalls := 0
		serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
			if n == "good" {
				goodCalls++
				if goodCalls%2 == 0 {
					return serviceProbeResult{Profile: p, Node: n, State: "unknown", EgressBound: true}, nil
				}
			}
			return old(ctx, p, c, n, k, d)
		}
		if f.tick().Services[0].State != "rolled_back" {
			t.Fatal("first attempt did not roll back")
		}
		if f.tick().Services[0].State != "cooldown" || len(f.puts) != 2 {
			t.Fatal("cooldown failed")
		}
	})
	t.Run("config-fingerprint", func(t *testing.T) {
		f := newHealthFixture(t)
		f.tick()
		f.tick()
		os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nrevision: 2\n"), 0600)
		f.rebind() // A new controlled load authorizes the new source revision.
		r := f.tick()
		if r.Services[0].Failures != 1 || len(f.puts) != 0 {
			t.Fatal(r)
		}
	})
	t.Run("manual-reset", func(t *testing.T) {
		f := newHealthFixture(t)
		f.tick()
		f.tick()
		f.change("Edge-gemini", "Manual")
		f.tick()
		f.change("Edge-gemini", "Edge-gemini-Auto")
		r := f.tick()
		if r.Services[0].Failures != 1 || len(f.puts) != 0 {
			t.Fatal(r)
		}
	})
}

func TestServiceHealthInputAndLockFailClosed(t *testing.T) {
	for _, kind := range []string{"remote", "redirect-style", "arbitrary-group", "lock", "future-state", "existing-report"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			out := filepath.Join(f.dir, "output.json")
			switch kind {
			case "remote":
				f.r.API = "http://192.0.2.1:9999"
			case "redirect-style":
				f.r.API = "http://127.0.0.1:9999@192.0.2.1:9999"
			case "arbitrary-group":
				f.r.Services[0].AutoSelector = "Manual"
			case "lock":
				os.MkdirAll(filepath.Join(f.r.StateDir, "service-health.lock"), 0700)
			case "future-state":
				os.MkdirAll(f.r.StateDir, 0700)
				s := serviceHealthState{SchemaVersion: 1, Attempts: []int64{serviceHealthNow().Unix() + 1}, Services: map[string]serviceHealthRecord{}}
				shWriteJSON(filepath.Join(f.r.StateDir, "service-health.json"), s, false)
			case "existing-report":
				os.WriteFile(out, []byte("sentinel"), 0600)
			}
			b, _ := json.Marshal(f.r)
			in := filepath.Join(f.dir, "request.json")
			os.WriteFile(in, b, 0600)
			err := runServiceHealth([]string{in, out})
			if kind == "lock" || kind == "future-state" {
				if err != nil {
					t.Fatal(err)
				}
				b, _ := os.ReadFile(out)
				want := "state_unavailable"
				if kind == "lock" {
					want = "state_locked"
				}
				if !strings.Contains(string(b), want) {
					t.Fatal("state failure not reported")
				}
			} else if err == nil {
				t.Fatal("invalid input accepted")
			}
			if len(f.puts) != 0 {
				t.Fatal(f.puts)
			}
		})
	}
}

func TestServiceHealthSecretOnlyInControllerHeader(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	f.r.SecretFile = filepath.Join(f.dir, "secret")
	os.WriteFile(f.r.SecretFile, []byte("private-secret\n"), 0600)
	f.tick()
	if len(f.authorizations) == 0 {
		t.Fatal("no controller requests")
	}
	for _, auth := range f.authorizations {
		if auth != "Bearer private-secret" {
			t.Fatal("missing private authentication")
		}
	}
}

func TestServiceHealthRuntimeRuleCannotReferencePrivateAuto(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	os.WriteFile(f.r.RuntimeConfig, []byte("rules:\n  - DOMAIN,other.example,Edge-gemini-Auto\n"), 0600)
	r := f.tick()
	if r.Services[0].State != "ownership_unverified" || len(f.puts) != 0 {
		t.Fatal(r)
	}
}

func TestServiceHealthManualObserveAndCycle(t *testing.T) {
	for _, cycle := range []bool{false, true} {
		t.Run(fmt.Sprint(cycle), func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.Mode = "observe"
			f.change("Edge-gemini", "Manual")
			if cycle {
				f.change("Manual", "Manual")
				p := f.g["Manual"]
				p.All = append(p.All, "Manual")
				f.g["Manual"] = p
			}
			r := f.tick()
			want := "region_denied"
			if cycle {
				want = "unknown"
			}
			if r.Services[0].State != "manual_held" || r.Services[0].ProbeState != want || len(f.puts) != 0 {
				t.Fatal(r)
			}
			if _, err := os.Stat(f.r.StateDir); !os.IsNotExist(err) {
				t.Fatal("manual observe wrote state")
			}
		})
	}
}

func TestServiceHealthCandidateBudgetBoundsProbes(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	f.r.MaxCandidates = 3
	p := f.g["Edge-gemini-Auto"]
	p.All = []string{"bad", "a", "b", "c", "d"}
	f.g["Edge-gemini-Auto"] = p
	calls := []string{}
	serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
		calls = append(calls, node)
		state := "unknown"
		if node == "bad" {
			state = "region_denied"
		}
		if node == "d" {
			state = "frontend_available"
		}
		return serviceProbeResult{Profile: profile, Node: node, State: state, EgressBound: true}, nil
	}
	r := f.tick()
	if r.Services[0].State != "no_verified_candidate" || strings.Join(calls, ",") != "bad,a,b,c" || len(f.puts) != 0 {
		t.Fatalf("unbounded candidate probes: %+v %v", r, calls)
	}
}

func TestServiceHealthBuiltinGlobalAndRuleMode(t *testing.T) {
	for _, kind := range []string{"rule", "global", "direct", "missing", "changed", "active-global", "explicit-shared"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			all := []string{}
			for name := range f.g {
				all = append(all, name)
			}
			f.g["GLOBAL"] = serviceHealthProxy{Type: "Selector", Now: "bad", All: all}
			switch kind {
			case "global", "direct":
				f.mode = kind
			case "missing":
				f.modeMissing = true
			case "active-global":
				f.change("GLOBAL", "Edge-gemini-Auto")
			case "explicit-shared":
				f.g["Other-0"] = serviceHealthProxy{Type: "Selector", Now: "bad", All: []string{"bad", "Edge-gemini-Auto"}}
			case "changed":
				old := serviceHealthProbe
				serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
					if n == "good" {
						f.mu.Lock()
						f.mode = "global"
						f.mu.Unlock()
					}
					return old(ctx, p, c, n, k, d)
				}
			}
			r := f.tick()
			if kind == "rule" {
				if r.Services[0].State != "repaired" || len(f.puts) != 1 {
					t.Fatalf("passive GLOBAL blocked repair: %+v %v", r, f.puts)
				}
			} else if len(f.puts) != 0 {
				t.Fatalf("unsafe runtime mode/reference wrote: %+v %v", r, f.puts)
			}
		})
	}
}

func TestServiceHealthModeChangeBlocksRollback(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	old := serviceHealthProbe
	goodCalls := 0
	serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
		if n == "good" {
			goodCalls++
			if goodCalls == 2 {
				f.mu.Lock()
				f.mode = "direct"
				f.mu.Unlock()
				return serviceProbeResult{Profile: p, Node: n, State: "unknown", EgressBound: true}, nil
			}
		}
		return old(ctx, p, c, n, k, d)
	}
	r := f.tick()
	if len(f.puts) != 1 || r.Services[0].State != "selection_changed_or_unresolved" {
		t.Fatalf("mode change allowed rollback: %+v %v", r, f.puts)
	}
}

func TestServiceHealthDuplicateKeysRejected(t *testing.T) {
	for _, raw := range []string{
		`{"mode":"observe","mode":"auto"}`,
		`{"mode":"observe","MODE":"auto"}`,
		`{"services":[{"name":"gemini","name":"openai"}]}`,
		`{"schema_version":1,"attempts":[],"services":{"gemini":{"failures":0,"failures":3}}}`,
		`{"schema_version":1,"attempts":[],"services":{"gemini":{"failures":0},"gemini":{"failures":3}}}`,
	} {
		var target any
		if shDecode([]byte(raw), &target) == nil {
			t.Fatalf("ambiguous JSON accepted: %s", raw)
		}
	}
	f := newHealthFixture(t)
	raw, _ := json.Marshal(f.r)
	raw = append(raw[:len(raw)-1], []byte(`,"mode":"observe"}`)...)
	in, out := filepath.Join(f.dir, "duplicate.json"), filepath.Join(f.dir, "unused.json")
	os.WriteFile(in, raw, 0600)
	if runServiceHealth([]string{in, out}) == nil || len(f.puts) != 0 {
		t.Fatal("duplicate request reached mutation")
	}
	os.MkdirAll(f.r.StateDir, 0700)
	os.WriteFile(filepath.Join(f.r.StateDir, "service-health.json"), []byte(`{"schema_version":1,"attempts":[],"attempts":[],"services":{}}`), 0600)
	r := f.tick()
	if r.Services[0].State != "state_unavailable" || len(f.puts) != 0 {
		t.Fatal("duplicate state was used")
	}
}

func TestServiceHealthLockCleanupPreservesReplacement(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	old := serviceHealthProbe
	replaced := false
	serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
		if !replaced {
			replaced = true
			lock := filepath.Join(f.r.StateDir, "service-health.lock")
			if err := os.Rename(lock, lock+".original"); err != nil {
				t.Fatal(err)
			}
			if err := os.Mkdir(lock, 0700); err != nil {
				t.Fatal(err)
			}
		}
		return old(ctx, p, c, n, k, d)
	}
	f.tick()
	if len(f.puts) != 0 {
		t.Fatal("lost lock ownership allowed mutation")
	}
	if _, err := os.Stat(filepath.Join(f.r.StateDir, "service-health.lock")); err != nil {
		t.Fatal("later writer lock removed")
	}
}

func TestServiceHealthPrivateAutoReferencesAnywhereRejected(t *testing.T) {
	for name, extra := range map[string]string{
		"sub-rules":           "sub-rules:\n  other: [MATCH,Edge-gemini-Auto]\n",
		"embedded-sub-rule":   "sub-rules:\n  other: ['DOMAIN,other.example,Edge-gemini-Auto']\n",
		"listener":            "listeners:\n  - name: shared\n    proxy: Edge-gemini-Auto\n",
		"dialer":              "proxies:\n  - name: other\n    type: vless\n    dialer-proxy: Edge-gemini-Auto\n",
		"provider-override":   "proxy-providers:\n  shared:\n    override:\n      dialer-proxy: Edge-gemini-Auto\n",
		"dns-outbound":        "dns:\n  nameserver: ['https://dns.example/dns-query#Edge-gemini-Auto']\n",
		"unrecognized-nested": "future-policy:\n  deeply:\n    nested: [Edge-gemini-Auto]\n",
	} {
		t.Run(name, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+extra), 0600)
			r := f.tick()
			if r.Services[0].State != "ownership_unverified" || len(f.puts) != 0 {
				t.Fatalf("hidden shared reference allowed repair: %+v %v", r, f.puts)
			}
		})
	}
	t.Run("missing-declaration", func(t *testing.T) {
		f := newHealthFixture(t)
		os.WriteFile(f.r.RuntimeConfig, []byte("proxy-groups: []"), 0600)
		r := f.tick()
		if r.Services[0].State != "ownership_unverified" {
			t.Fatal(r)
		}
	})
}

func TestServiceHealthCancellationWaitsForSynchronousBackend(t *testing.T) {
	f := newHealthFixture(t)
	f.r.Mode = "observe"
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	started, cleaned, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
		close(started)
		<-ctx.Done()
		close(cleaned)
		return serviceProbeResult{Profile: p, Node: n, State: "frontend_available", EgressBound: true}, nil
	}
	c := &serviceHealthController{api: f.r.API, client: &http.Client{Timeout: time.Second}}
	go func() {
		defer close(finished)
		state := serviceHealthState{SchemaVersion: 1, Services: map[string]serviceHealthRecord{}}
		shProcess(ctx, f.r, c, &state, "", f.r.Services[0])
	}()
	select {
	case <-started:
	case <-time.After(3 * time.Second):
		t.Fatal("backend did not start")
	}
	cancel()
	select {
	case <-finished:
	case <-time.After(3 * time.Second):
		t.Fatal("cancellation did not return")
	}
	select {
	case <-cleaned:
	default:
		t.Fatal("engine returned before backend cleanup")
	}
	if len(f.puts) != 0 {
		t.Fatal("cancelled backend produced a write")
	}
}

func TestServiceHealthDeadlineBeforeDispatch(t *testing.T) {
	f := newHealthFixture(t)
	r := f.r
	r.FailChecks = 1
	if err := r.validate(); err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(r.StateDir, 0700)
	c := &serviceHealthController{api: r.API, client: &http.Client{Timeout: time.Second}, lockOwned: func() bool { return true }}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	state := serviceHealthState{SchemaVersion: 1, Services: map[string]serviceHealthRecord{}}
	entry := shProcess(ctx, r, c, &state, filepath.Join(r.StateDir, "service-health.json"), r.Services[0])
	if entry.State != "deadline_held" || len(f.puts) != 0 || state.Services["gemini"].Pending != nil {
		t.Fatalf("deadline exhaustion dispatched: %+v %v", entry, f.puts)
	}
}

func TestServiceHealthPendingWrittenBeforePUT(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	f.onPut = func() {
		state, err := shLoadState(filepath.Join(f.r.StateDir, "service-health.json"), serviceHealthNow().Unix())
		if err != nil {
			t.Error(err)
			return
		}
		p := state.Services["gemini"].Pending
		if p == nil || p.From != "bad" || p.To != "good" || p.BeforeGraph == p.AfterGraph || len(p.ConfigHash) != 64 || len(p.CoreIdentity) != 64 {
			t.Errorf("PUT lacks prior pending responsibility: %+v", p)
		}
	}
	if f.tick().Services[0].State != "repaired" {
		t.Fatal("repair did not complete")
	}
}

func TestServiceHealthPendingRestartReconciliation(t *testing.T) {
	for _, kind := range []string{"applied-positive", "applied-unknown", "applied-explicit-failure", "not-applied", "later-choice", "core-change", "other-graph-change"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			f.hideGraphAfterPut = true
			if kind == "not-applied" {
				f.putNoApply = true
				f.putFailure = true
			}
			first := f.tick()
			if !first.Services[0].Pending || len(f.puts) != 1 {
				t.Fatalf("uncertain dispatch lost pending: %+v %v", first, f.puts)
			}
			persisted, err := shLoadState(filepath.Join(f.r.StateDir, "service-health.json"), serviceHealthNow().Unix())
			if err != nil || persisted.Services["gemini"].Pending == nil {
				t.Fatal("pending not durable")
			}
			f.mu.Lock()
			f.graphUnavailable = false
			f.hideGraphAfterPut = false
			f.putFailure = false
			f.putNoApply = false
			f.mu.Unlock()
			switch kind {
			case "applied-unknown", "applied-explicit-failure":
				serviceHealthProbe = func(ctx context.Context, p, c, n, k string, d time.Duration) (serviceProbeResult, error) {
					state := "unknown"
					if kind == "applied-explicit-failure" {
						state = "region_denied"
					}
					return serviceProbeResult{Profile: p, Node: n, State: state, EgressBound: true}, nil
				}
			case "later-choice":
				f.change("Edge-gemini", "Manual")
			case "core-change":
				f.r.CorePath = "/proc/new-main-pid/exe"
			case "other-graph-change":
				f.change("Other-1", "good")
			}
			second := f.tick().Services[0]
			want := "pending_verified"
			writes := 1
			switch kind {
			case "applied-unknown":
				want = "pending_unresolved"
			case "applied-explicit-failure":
				want = "pending_rolled_back"
				writes = 2
			case "not-applied":
				want = "pending_not_applied"
			case "later-choice":
				want = "manual_held"
			case "core-change":
				want = "observe_only"
			case "other-graph-change":
				want = "pending_superseded"
			}
			if second.State != want || len(f.puts) != writes {
				t.Fatalf("bad reconciliation: %+v %v", second, f.puts)
			}
			if kind == "applied-unknown" || kind == "later-choice" || kind == "core-change" || kind == "other-graph-change" {
				state, _ := shLoadState(filepath.Join(f.r.StateDir, "service-health.json"), serviceHealthNow().Unix())
				if state.Services["gemini"].Pending == nil {
					t.Fatal("unresolved responsibility dropped")
				}
			}
		})
	}
}

func TestServiceHealthCoreIdentityResetsFailureStreak(t *testing.T) {
	f := newHealthFixture(t)
	f.tick()
	f.tick()
	f.r.CorePath = "/proc/different-main-pid/exe"
	f.rebind() // Only a newly established load may authorize the new core.
	r := f.tick()
	if r.Services[0].Failures != 1 || len(f.puts) != 0 {
		t.Fatalf("main PID change retained old failures: %+v", r)
	}
}

func TestServiceHealthCandidateRotationFindsLaterRoute(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	for _, name := range []string{"openai", "anthropic"} {
		f.r.Services = append(f.r.Services, serviceHealthSpec{Name: name, Selector: "Edge-" + name, AutoSelector: "Edge-" + name + "-Auto"})
		f.change("Edge-"+name, "Manual")
	}
	p := f.g["Edge-gemini-Auto"]
	p.All = []string{"bad", "a", "b", "c", "d", "e", "z"}
	f.g["Edge-gemini-Auto"] = p
	calls := []string{}
	serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
		state := "frontend_available"
		if profile == "gemini" {
			calls = append(calls, node)
			if node != "z" {
				state = "region_denied"
			}
		}
		return serviceProbeResult{Profile: profile, Node: node, State: state, EgressBound: true}, nil
	}
	first := f.tick()
	if first.Services[0].State != "no_verified_candidate" || len(f.puts) != 0 || strings.Join(calls, ",") != "bad,a,b,c" {
		t.Fatalf("wrong first bounded batch: %+v %v", first, calls)
	}
	second := f.tick()
	if second.Services[0].State != "repaired" || len(f.puts) != 1 || f.puts[0] != "Edge-gemini-Auto=z" {
		t.Fatalf("later valid route starved: %+v %v", second, calls)
	}
	if strings.Join(calls, ",") != "bad,a,b,c,bad,d,e,z,z" {
		t.Fatalf("batch rotation failed: %v", calls)
	}
	for i, name := range []string{"openai", "anthropic"} {
		if second.Services[i+1].State != "manual_held" || second.Services[i+1].ProbeState != "frontend_available" || f.g["Edge-"+name].Now != "Manual" || f.g["Edge-"+name+"-Auto"].Now != "bad" {
			t.Fatalf("other service moved: %+v", second)
		}
	}
	for name, p := range f.g {
		if strings.HasPrefix(name, "Other-") || name == "Manual" {
			if p.Now != "bad" {
				t.Fatalf("old manual selector moved: %s", name)
			}
		}
	}
	state, err := shLoadState(filepath.Join(f.r.StateDir, "service-health.json"), serviceHealthNow().Unix())
	if err != nil || state.Services["gemini"].CandidateOffset != 0 {
		t.Fatal("accepted recovery did not reset rotation")
	}
	f.tick()
	if len(f.puts) != 1 || calls[len(calls)-1] != "z" {
		t.Fatal("working current route lost stickiness")
	}
}

func TestServiceHealthRotationResetsForManualAndConfig(t *testing.T) {
	for _, kind := range []string{"manual", "config"} {
		t.Run(kind, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			p := f.g["Edge-gemini-Auto"]
			p.All = []string{"bad", "a", "b", "c", "d"}
			f.g["Edge-gemini-Auto"] = p
			calls := []string{}
			serviceHealthProbe = func(ctx context.Context, profile, config, node, core string, timeout time.Duration) (serviceProbeResult, error) {
				calls = append(calls, node)
				return serviceProbeResult{Profile: profile, Node: node, State: "region_denied", EgressBound: true}, nil
			}
			f.tick()
			if kind == "manual" {
				f.change("Edge-gemini", "Manual")
				f.tick()
				f.change("Edge-gemini", "Edge-gemini-Auto")
			} else {
				os.WriteFile(f.r.RuntimeConfig, []byte(healthRuntimeConfig+"\nrevision: 2\n"), 0600)
				f.rebind()
			}
			calls = nil
			f.tick()
			if strings.Join(calls, ",") != "bad,a,b,c" || len(f.puts) != 0 {
				t.Fatalf("rotation retained stale policy position: %v", calls)
			}
		})
	}
}

func TestServiceHealthDriverUsesPortableCapabilityGate(t *testing.T) {
	for _, missing := range []string{"named", "guarded", "manual", "persistence", "scope"} {
		t.Run(missing, func(t *testing.T) {
			f := newHealthFixture(t)
			f.r.FailChecks = 1
			original := serviceHealthPolicyCapabilities
			caps := original()
			switch missing {
			case "named":
				caps.NamedEgressProbe = false
			case "guarded":
				caps.GuardedSelection = false
			case "manual":
				caps.ManualHold = false
			case "persistence":
				caps.RecoveryPersistence = false
			case "scope":
				caps.ProbeScopes = nil
			}
			serviceHealthPolicyCapabilities = func() healthpolicy.Capabilities { return caps }
			t.Cleanup(func() { serviceHealthPolicyCapabilities = original })
			r := f.tick()
			if len(f.puts) != 0 || r.Services[0].PolicyReason == "" || r.Services[0].State != "unknown" || r.Services[0].Failures != 0 {
				t.Fatalf("driver bypassed portable policy: %+v %v", r, f.puts)
			}
		})
	}
}

func TestServiceHealthPendingCannotBypassPortableCapabilities(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	f.hideGraphAfterPut = true
	first := f.tick()
	if !first.Services[0].Pending {
		t.Fatal("no pending responsibility")
	}
	f.mu.Lock()
	f.graphUnavailable = false
	f.hideGraphAfterPut = false
	f.mu.Unlock()
	original := serviceHealthPolicyCapabilities
	caps := original()
	caps.RecoveryPersistence = false
	serviceHealthPolicyCapabilities = func() healthpolicy.Capabilities { return caps }
	t.Cleanup(func() { serviceHealthPolicyCapabilities = original })
	r := f.tick()
	if len(f.puts) != 1 || !r.Services[0].Pending || r.Services[0].PolicyReason != "recovery_persistence_unavailable" {
		t.Fatalf("pending bypassed capability gate: %+v %v", r, f.puts)
	}
}

func TestServiceHealthKernelLeaseChild(t *testing.T) {
	if os.Getenv("HOME_EDGE_TEST_LEASE_CHILD") != "1" {
		return
	}
	dir := os.Getenv("HOME_EDGE_TEST_LEASE_DIR")
	owned, release, err := acquireServiceHealthLock(dir)
	if err != nil || !owned() {
		t.Fatal("child cannot acquire lease")
	}
	defer release()
	if os.WriteFile(filepath.Join(dir, "child-ready"), []byte("ready"), 0600) != nil {
		t.Fatal("cannot signal child readiness")
	}
	for {
		time.Sleep(time.Hour)
	}
}

func startHealthLeaseChild(t *testing.T, dir string) *exec.Cmd {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^TestServiceHealthKernelLeaseChild$")
	cmd.Env = append(os.Environ(), "HOME_EDGE_TEST_LEASE_CHILD=1", "HOME_EDGE_TEST_LEASE_DIR="+dir)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = cmd.Process.Kill(); _ = cmd.Wait() })
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(filepath.Join(dir, "child-ready")); err == nil {
			return cmd
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("lease child did not become ready")
	return nil
}

func TestServiceHealthKernelLeaseRejectsLiveAndRecoversKilledOwner(t *testing.T) {
	dir := canonicalHealthTempDir(t)
	child := startHealthLeaseChild(t, dir)
	if _, release, err := acquireServiceHealthLock(dir); err == nil {
		release()
		t.Fatal("live writer lease stolen")
	}
	if err := child.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = child.Wait()
	owned, release, err := acquireServiceHealthLock(dir)
	if err != nil {
		t.Fatal("kernel did not release killed owner", err)
	}
	if !owned() {
		t.Fatal("recovered lease is not owned")
	}
	release()
	if owned() {
		t.Fatal("closed lease still claims ownership")
	}
	// A reboot leaves this recognized file but no kernel lease. Reacquiring
	// the same retained artifact exercises that post-boot state without rebooting.
	retained, err := os.ReadFile(filepath.Join(dir, "service-health.lock"))
	if err != nil {
		t.Fatal(err)
	}
	owned, release, err = acquireServiceHealthLock(dir)
	if err != nil || !owned() {
		t.Fatal("retained post-boot record blocked recovery", err)
	}
	release()
	after, _ := os.ReadFile(filepath.Join(dir, "service-health.lock"))
	if string(after) != string(retained) {
		t.Fatal("recovery rewrote immutable ownership evidence")
	}
}

func TestServiceHealthKernelLeasePreservesForeignAndLegacyLocks(t *testing.T) {
	for _, kind := range []string{"foreign-file", "legacy-directory"} {
		t.Run(kind, func(t *testing.T) {
			dir := canonicalHealthTempDir(t)
			path := filepath.Join(dir, "service-health.lock")
			if kind == "foreign-file" {
				os.WriteFile(path, []byte("foreign-owned"), 0600)
			} else {
				os.Mkdir(path, 0700)
				os.WriteFile(filepath.Join(path, "owner"), []byte("unverifiable-old-owner"), 0600)
			}
			if _, release, err := acquireServiceHealthLock(dir); err == nil {
				release()
				t.Fatal("unknown lock adopted")
			}
			if kind == "foreign-file" {
				raw, _ := os.ReadFile(path)
				if string(raw) != "foreign-owned" {
					t.Fatal("foreign bytes changed")
				}
			} else {
				raw, _ := os.ReadFile(filepath.Join(path, "owner"))
				if string(raw) != "unverifiable-old-owner" {
					t.Fatal("legacy ownership bytes changed")
				}
			}
		})
	}
}

func TestServiceHealthPendingResumesAfterKilledKernelLease(t *testing.T) {
	f := newHealthFixture(t)
	f.r.FailChecks = 1
	f.hideGraphAfterPut = true
	if !f.tick().Services[0].Pending {
		t.Fatal("uncertain effect was not retained")
	}
	child := startHealthLeaseChild(t, f.r.StateDir)
	if err := child.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = child.Wait()
	f.mu.Lock()
	f.graphUnavailable = false
	f.hideGraphAfterPut = false
	f.mu.Unlock()
	result := f.tick().Services[0]
	if result.State != "pending_verified" || result.Pending || len(f.puts) != 1 {
		t.Fatalf("killed owner blocked safe reconciliation: %+v %v", result, f.puts)
	}
}
