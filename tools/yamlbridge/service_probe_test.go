package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestClassifyServiceResponse(t *testing.T) {
	for _, tc := range []struct {
		name, profile                 string
		status                        int
		body, location, state, reason string
	}{
		{"gemini 200 region", "gemini", 200, `<html><h1>Gemini isn't available in your country</h1></html>`, "", "region_denied", "explicit_region_rejection"},
		{"gemini curly apostrophe", "gemini", 200, `<h1>Gemini isn’t available in your country</h1>`, "", "region_denied", "explicit_region_rejection"},
		{"gemini current support rejection", "gemini", 200, `<h1>Gemini isn’t currently supported in your country</h1>`, "", "region_denied", "explicit_region_rejection"},
		{"gemini observed Chinese region rejection", "gemini", 200, `<main><h1>Gemini 目前不支持你所在的地区。</h1><p>敬请期待！</p></main>`, "", "region_denied", "explicit_region_rejection"},
		{"Chinese rejection in script is not page evidence", "gemini", 200, `<h1>Gemini</h1><script>const message="Gemini 目前不支持你所在的地区。敬请期待！";</script>`, "", "unknown", "unrecognized_response"},
		{"hidden Gemini capability flag is not frontend", "gemini", 200, `<h1>Gemini</h1><script>const flags=[45631641,null,true];</script><a>Sign in</a>`, "", "unknown", "authentication_required"},
		{"hidden Chinese rejection plus entry is ambiguous", "gemini", 200, `<div hidden><p>Gemini 目前不支持你所在的地区。敬请期待！</p></div><bard-chat-app><div contenteditable="true">Ask Gemini</div></bard-chat-app>`, "", "unknown", "ambiguous_hidden_markup"},
		{"aria hidden ancestor rejection is ambiguous", "gemini", 200, `<section aria-hidden="true"><p>Gemini isn't available in your country</p></section><bard-chat-app><div contenteditable="true">Ask Gemini</div></bard-chat-app>`, "", "unknown", "ambiguous_hidden_markup"},
		{"template rejection plus entry is ambiguous", "gemini", 200, `<template><p>Gemini 目前不支持你所在的地区。敬请期待！</p></template><bard-chat-app><div contenteditable="true">Ask Gemini</div></bard-chat-app>`, "", "unknown", "ambiguous_hidden_markup"},
		{"display none ancestor hides input markers", "openai", 200, `<h1>ChatGPT</h1><div style="display: none"><div id="prompt-textarea"></div><button data-testid="send-button"></button></div>`, "", "unknown", "ambiguous_hidden_markup"},
		{"unquoted display none ancestor", "openai", 200, `<h1>ChatGPT</h1><div style=color:red;display:none><div id="prompt-textarea"></div><button data-testid="send-button"></button></div>`, "", "unknown", "ambiguous_hidden_markup"},
		{"hidden input markers plus brand", "openai", 200, `<h1>ChatGPT</h1><div hidden="false" id="prompt-textarea"></div><button data-testid="send-button"></button>`, "", "unknown", "ambiguous_hidden_markup"},
		{"visibility hidden ancestor hides entry", "anthropic", 200, `<h1>Claude</h1><section style='visibility: hidden'><div contenteditable="true" data-testid="chat-input"></div></section>`, "", "unknown", "ambiguous_hidden_markup"},
		{"template input markers plus brand", "openai", 200, `<h1>ChatGPT</h1><template><div id="prompt-textarea"></div><button data-testid="send-button"></button></template>`, "", "unknown", "ambiguous_hidden_markup"},
		{"script hidden strings do not contaminate entry", "gemini", 200, `<script>const example='<div hidden>Gemini 目前不支持你所在的地区。敬请期待！</div>';</script><bard-chat-app><div contenteditable="true">Ask Gemini</div></bard-chat-app>`, "", "frontend_available", "interactive_frontend_markup"},
		{"aria hidden false is not hidden", "openai", 200, `<h1>ChatGPT</h1><div aria-hidden="false" id="prompt-textarea"></div><button data-testid="send-button"></button>`, "", "frontend_available", "interactive_frontend_markup"},
		{"bundled region errors are not visible", "gemini", 200, `<title>Gemini</title><script>"Gemini isn't available in your country"</script>`, "", "unknown", "unrecognized_response"},
		{"openai structured region", "openai", 403, `{"error":{"code":"unsupported_country_region_territory"}}`, "", "region_denied", "explicit_region_rejection"},
		{"openai code in script", "openai", 200, `<script>const code="unsupported_country_region_territory";</script>ChatGPT`, "", "unknown", "unrecognized_response"},
		{"app markers in script are not DOM", "openai", 200, `<h1>ChatGPT</h1><script>const fake='<div id="prompt-textarea" data-testid="send-button">';</script>`, "", "unknown", "unrecognized_response"},
		{"region phrase belongs to another product", "gemini", 200, `<h1>Gemini</h1><p>Other product is not available in your country</p>`, "", "unknown", "unrecognized_response"},
		{"challenge beats apparent app", "openai", 200, `<div id="prompt-textarea" data-testid="send-button">ChatGPT</div><script src="/cdn-cgi/challenge-platform/cf-chl-x"></script>`, "", "unknown", "browser_challenge"},
		{"rate limit", "anthropic", 429, `Claude`, "", "unknown", "rate_limited"},
		{"auth", "gemini", 401, `Gemini`, "", "unknown", "authentication_required"},
		{"auth redirect", "gemini", 302, ``, "https://accounts.google.com/ServiceLogin?private=secret", "unknown", "authentication_required"},
		{"unfollowed redirect", "openai", 302, ``, "https://example.invalid/", "unknown", "redirect_unverified"},
		{"generic denied", "anthropic", 403, `Forbidden`, "", "unknown", "permission_or_policy_unknown"},
		{"generic error", "gemini", 200, `Gemini Something went wrong`, "", "unknown", "unrecognized_response"},
		{"title is insufficient", "anthropic", 200, `<title>Claude</title><h1>Claude is an AI assistant</h1>`, "", "unknown", "unrecognized_response"},
		{"login is not interactive acceptance", "anthropic", 200, `<h1>Claude</h1><button>Log in</button>`, "", "unknown", "authentication_required"},
		{"gemini frontend", "gemini", 200, `<bard-chat-app><div contenteditable="true">Ask Gemini</div></bard-chat-app>`, "", "frontend_available", "interactive_frontend_markup"},
		{"openai frontend", "openai", 200, `<h1>ChatGPT</h1><div id="prompt-textarea"></div><button data-testid="send-button"></button>`, "", "frontend_available", "interactive_frontend_markup"},
		{"claude frontend", "anthropic", 200, `<h1>Claude</h1><div contenteditable="true" data-testid="chat-input"></div>`, "", "frontend_available", "interactive_frontend_markup"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := classifyServiceResponse(tc.profile, tc.status, []byte(tc.body), tc.location)
			if r.State != tc.state || r.Reason != tc.reason {
				t.Fatalf("got %s/%s", r.State, r.Reason)
			}
			if r.AccountVerified || r.EgressBound {
				t.Fatal("classifier invented runtime/account evidence")
			}
		})
	}
}

func writeProbeFixture(t *testing.T, raw string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "source.yaml")
	if err := os.WriteFile(p, []byte(raw), 0600); err != nil {
		t.Fatal(err)
	}
	return p
}

const probeFixture = `routing-mark: 7894
proxies:
  - {name: candidate, type: http, server: example.invalid, port: 443, password: <example>, dialer-proxy: hop}
  - {name: hop, type: ss, server: example.invalid, port: 443, cipher: aes-128-gcm, password: <example>}
mixed-port: 7890
external-controller: 0.0.0.0:9999
tun: {enable: true}
dns: {enable: true, listen: 0.0.0.0:53}
profile: {store-selected: true}
rules: [MATCH,DIRECT]
`

func TestProbeBuildExactDependencyAndIsolation(t *testing.T) {
	path := writeProbeFixture(t, probeFixture)
	cfg, mark, err := buildProbeConfig(path, "candidate", "127.0.0.1:12345", "fixture-credential")
	if err != nil {
		t.Fatal(err)
	}
	if mark != 7894 || len(cfg["proxies"].([]any)) != 2 {
		t.Fatal("dependency chain lost")
	}
	for _, k := range []string{"mixed-port", "external-controller", "proxy-groups", "proxy-providers"} {
		if _, exists := cfg[k]; exists {
			t.Fatalf("inherited production %s", k)
		}
	}
	listener := cfg["listeners"].([]any)[0].(map[string]any)
	if listener["listen"] != "127.0.0.1" || listener["proxy"] != "candidate" {
		t.Fatal("listener not bound")
	}
	if cfg["tun"].(map[string]any)["enable"] != false || cfg["dns"].(map[string]any)["enable"] != false {
		t.Fatal("unsafe global effects")
	}
	if cfg["profile"].(map[string]any)["store-selected"] != false {
		t.Fatal("shared selections")
	}
}

func TestProbeRejectUnprovenDependencies(t *testing.T) {
	for _, raw := range []string{
		strings.Replace(probeFixture, "routing-mark: 7894\n", "", 1),
		strings.Replace(probeFixture, "dialer-proxy: hop", "dialer-proxy: production-group", 1),
		strings.Replace(probeFixture, "dialer-proxy: hop", "dialer-proxy: candidate", 1),
		strings.Replace(probeFixture, "type: http", "type: wireguard", 1),
		probeFixture + "proxy-providers: {remote: {type: http, url: https://example.invalid/sub, path: ./cached.yaml}}\n",
		probeFixture + "proxy-providers: {remote: {type: http, url: https://example.invalid/sub, path: /unavailable/cache.yaml, override: {udp: true}}}\n",
		strings.Replace(probeFixture, "type: http", "routing-mark: 9999, type: http", 1),
		probeFixture + "ipv6: true\n",
		strings.Replace(probeFixture, "server: example.invalid", "server: '2001:db8::1'", 1),
		strings.Replace(probeFixture, "name: hop, type: ss, server: example.invalid", "name: hop, type: ss, server: '[::1]'", 1),
		strings.Replace(probeFixture, "type: http", "ip-version: ipv6, type: http", 1),
	} {
		_, _, err := buildProbeConfig(writeProbeFixture(t, raw), "candidate", "127.0.0.1:12345", "secret")
		if err == nil {
			t.Fatal("accepted unverified source")
		}
		if strings.Contains(err.Error(), "example-value") {
			t.Fatal("credential leak")
		}
	}
}

func TestProbeCachedProviderNoRefresh(t *testing.T) {
	cache := writeProbeFixture(t, "proxies: [{name: cached, type: http, server: example.invalid, port: 443}]\n")
	doc := map[string]any{"routing-mark": 7894, "proxy-providers": map[string]any{"p": map[string]any{"type": "http", "url": "https://must-not-fetch.invalid/sub", "path": cache}}}
	raw, _ := json.Marshal(doc)
	cfg, _, err := buildProbeConfig(writeProbeFixture(t, string(raw)), "cached", "127.0.0.1:12345", "secret")
	if err != nil {
		t.Fatal(err)
	}
	if len(cfg["proxies"].([]any)) != 1 {
		t.Fatal("cache not expanded")
	}
	if _, ok := cfg["proxy-providers"]; ok {
		t.Fatal("provider refresh inherited")
	}
}

func TestProbeInlineProvider(t *testing.T) {
	path := writeProbeFixture(t, "routing-mark: 7894\nproxy-providers:\n  p:\n    type: inline\n    payload: [{name: inline-node, type: http, server: example.invalid, port: 443}]\n")
	cfg, _, err := buildProbeConfig(path, "inline-node", "127.0.0.1:12345", "secret")
	if err != nil || len(cfg["proxies"].([]any)) != 1 {
		t.Fatalf("inline provider unavailable: %v", err)
	}
}

func TestProbeIPv6RequiresVerifiedDualStackBypass(t *testing.T) {
	path := writeProbeFixture(t, strings.Replace(probeFixture, "server: example.invalid", "server: '2001:db8::1'", 1)+"ipv6: true\n")
	if _, _, err := buildProbeConfigWithIPv6(path, "candidate", "127.0.0.1:12345", "secret", false); err == nil {
		t.Fatal("unverified IPv6 accepted")
	}
	cfg, _, err := buildProbeConfigWithIPv6(path, "candidate", "127.0.0.1:12345", "secret", true)
	if err != nil || cfg["ipv6"] != true {
		t.Fatalf("source IPv6 disabled or rejected: %v", err)
	}
	proxies := cfg["proxies"].([]any)
	if proxies[len(proxies)-1].(map[string]any)["server"] != "2001:db8::1" {
		t.Fatal("IPv6 candidate changed")
	}
	started := false
	r, err := serviceProbeWithRuntime("gemini", path, "candidate", "fixture", time.Second, serviceProbeRuntime{verifyIPv6Bypass: func() bool { return true }, verifyBypass: func(int) bool { return false }, start: func(context.Context, string, string, string, string) (func() error, error) {
		started = true
		return nil, nil
	}})
	if err != nil || started || r.EgressBound || r.Precondition != "routing_bypass_unverified" {
		t.Fatal("IPv6 attestation bypassed mark verification")
	}
	path = writeProbeFixture(t, strings.Replace(probeFixture, "type: http", "ip-version: ipv6, type: http", 1)+"ipv6: true\n")
	cfg, _, err = buildProbeConfigWithIPv6(path, "candidate", "127.0.0.1:12345", "secret", true)
	if err != nil || cfg["ipv6"] != true {
		t.Fatal("verified IPv6 ip-version rejected")
	}
}

func TestServiceProbeRuntimeSeamAndCleanup(t *testing.T) {
	path := writeProbeFixture(t, probeFixture)
	original, _ := os.ReadFile(path)
	var dir string
	stopped := false
	requested := false
	r, err := serviceProbeWithRuntime("gemini", path, "candidate", "fixture-core", time.Second, serviceProbeRuntime{
		verifyBypass: func(mark int) bool { return mark == 7894 },
		start: func(ctx context.Context, core, home, config, address string) (func() error, error) {
			dir = home
			info, e := os.Stat(home)
			if e != nil || !info.IsDir() {
				t.Fatal("missing private directory")
			}
			raw, e := os.ReadFile(config)
			if e != nil {
				t.Fatal(e)
			}
			var cfg map[string]any
			if json.Unmarshal(raw, &cfg) != nil {
				t.Fatal("invalid config")
			}
			if cfg["routing-mark"] != float64(7894) {
				t.Fatal("bypass mark lost")
			}
			return func() error { stopped = true; return nil }, nil
		},
		request: func(ctx context.Context, proxy, target string) (int, []byte, string, error) {
			requested = true
			if target != probeTargets["gemini"] || !strings.HasPrefix(proxy, "http://probe:") {
				t.Fatal("wrong request binding")
			}
			return 200, []byte("<h1>Gemini isn't available in your country</h1>"), "", nil
		},
	})
	if err != nil || r.State != "region_denied" || !r.EgressBound || r.AccountVerified || !stopped || !requested {
		t.Fatalf("bad result %+v, %v", r, err)
	}
	if _, e := os.Stat(dir); !os.IsNotExist(e) {
		t.Fatal("private directory retained")
	}
	after, _ := os.ReadFile(path)
	if string(after) != string(original) {
		t.Fatal("production source modified")
	}
}

func TestProbePreconditionAndTimeoutNeverClaimAvailability(t *testing.T) {
	path := writeProbeFixture(t, probeFixture)
	started := false
	r, err := serviceProbeWithRuntime("gemini", path, "candidate", "fixture", time.Second, serviceProbeRuntime{verifyBypass: func(int) bool { return false }, start: func(context.Context, string, string, string, string) (func() error, error) {
		started = true
		return nil, nil
	}})
	if err != nil || started || r.State != "unknown" || r.EgressBound || r.Precondition != "routing_bypass_unverified" {
		t.Fatalf("unverified bypass %+v %v", r, err)
	}
	stopped := false
	r, err = serviceProbeWithRuntime("gemini", path, "candidate", "fixture", 20*time.Millisecond, serviceProbeRuntime{verifyBypass: func(int) bool { return true }, start: func(context.Context, string, string, string, string) (func() error, error) {
		return func() error { stopped = true; return nil }, nil
	}, request: func(ctx context.Context, _, _ string) (int, []byte, string, error) {
		<-ctx.Done()
		return 0, nil, "", ctx.Err()
	}})
	if err != nil || !stopped || r.State != "transport_failed" || r.Reason != "request_transport_failed" {
		t.Fatalf("timeout mishandled %+v %v", r, err)
	}
}

func TestProbeParentContextCancelsOwnedWork(t *testing.T) {
	path := writeProbeFixture(t, probeFixture)
	ctx, cancel := context.WithCancel(context.Background())
	stopped := false
	r, err := serviceProbeWithRuntime("gemini", path, "candidate", "fixture", time.Second, serviceProbeRuntime{baseContext: ctx, verifyBypass: func(int) bool { return true }, start: func(context.Context, string, string, string, string) (func() error, error) {
		return func() error { stopped = true; return nil }, nil
	}, request: func(ctx context.Context, _, _ string) (int, []byte, string, error) {
		cancel()
		<-ctx.Done()
		return 200, []byte(`<bard-chat-app><div contenteditable="true">Ask Gemini</div></bard-chat-app>`), "", nil
	}})
	if err != nil || !stopped || r.State != "unknown" || r.Reason != "probe_cancelled" || r.AccountVerified {
		t.Fatalf("cancelled response trusted %+v %v", r, err)
	}
}

func TestProbeTransportFailureRequiresNoHTTPResponse(t *testing.T) {
	for _, status := range []int{0, 200, 302, 401, 429} {
		t.Run(strconv.Itoa(status), func(t *testing.T) {
			r, err := serviceProbeWithRuntime("gemini", writeProbeFixture(t, probeFixture), "candidate", "fixture", time.Second, serviceProbeRuntime{verifyBypass: func(int) bool { return true }, start: func(context.Context, string, string, string, string) (func() error, error) {
				return func() error { return nil }, nil
			}, request: func(context.Context, string, string) (int, []byte, string, error) {
				return status, nil, "", errors.New("fixture transport or incomplete body")
			}})
			want, reason := "unknown", "transport_or_body_incomplete"
			if status == 0 {
				want, reason = "transport_failed", "request_transport_failed"
			}
			if err != nil || r.State != want || r.Reason != reason || !r.EgressBound || r.AccountVerified {
				t.Fatalf("wrong result %+v %v", r, err)
			}
		})
	}
}

func TestProbeCleanupFailureInvalidatesVerdict(t *testing.T) {
	r, err := serviceProbeWithRuntime("openai", writeProbeFixture(t, probeFixture), "candidate", "fixture", time.Second, serviceProbeRuntime{verifyBypass: func(int) bool { return true }, start: func(context.Context, string, string, string, string) (func() error, error) {
		return func() error { return errors.New("fixture failure") }, nil
	}, request: func(context.Context, string, string) (int, []byte, string, error) {
		return 403, []byte(`{"error":{"code":"unsupported_country_region_territory"}}`), "", nil
	}})
	if err == nil || r.State != "unknown" || r.Reason != "probe_process_cleanup_failed" {
		t.Fatal("cleanup failure hidden")
	}
}

func TestRequestProbeUsesRealHTTPAdapter(t *testing.T) {
	var received bool
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received = true
		if r.Method != "GET" || r.URL.Host != "frontend.invalid" || r.Header.Get("Accept-Language") == "" {
			t.Error("request semantics lost")
		}
		w.Header().Set("Location", "https://accounts.google.com/ServiceLogin")
		w.WriteHeader(302)
		_, _ = w.Write([]byte("redirect body"))
	}))
	defer proxy.Close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	status, body, location, err := requestProbeFrontend(ctx, proxy.URL, "http://frontend.invalid/app")
	if err != nil || !received || status != 302 || string(body) != "redirect body" || location != "https://accounts.google.com/ServiceLogin" {
		t.Fatalf("request failed %d %v", status, err)
	}
}

func TestProbeCoreEnvironmentCannotInheritOverrides(t *testing.T) {
	t.Setenv("CLASH_OVERRIDE_EXTERNAL_CONTROLLER", "0.0.0.0:9999")
	t.Setenv("CLASH_POST_UP", "must-not-run")
	for _, entry := range probeCoreEnvironment() {
		if strings.HasPrefix(strings.ToUpper(entry), "CLASH_") {
			t.Fatal("core override leaked")
		}
	}
}

func TestRequestProbeRejectsOversizedBody(t *testing.T) {
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(strings.Repeat("x", 2*1024*1024+1)))
	}))
	defer proxy.Close()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	status, body, _, err := requestProbeFrontend(ctx, proxy.URL, "http://frontend.invalid/app")
	if err == nil || body != nil || status != 200 {
		t.Fatal("oversized body accepted")
	}
}

func TestProbeLinuxOwnedProcessLifecycle(t *testing.T) {
	if runtime.GOOS != "linux" {
		t.Skip("Linux parent-death and reap contract")
	}
	python, err := exec.LookPath("python3")
	if err != nil {
		t.Skip("Python fixture unavailable")
	}
	dir := t.TempDir()
	core := filepath.Join(dir, "fixture-core")
	script := "#!" + python + "\n" + `import sys,json,socket
if '-t' in sys.argv: sys.exit(0)
c=json.load(open(sys.argv[sys.argv.index('-f')+1]))
l=c['listeners'][0]
s=socket.socket();s.bind((l['listen'],int(l['port'])));s.listen()
while True:
    conn,addr=s.accept();conn.close()
`
	if err := os.WriteFile(core, []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := listener.Addr().String()
	_ = listener.Close()
	cfg, _, err := buildProbeConfig(writeProbeFixture(t, probeFixture), "candidate", address, "secret")
	if err != nil {
		t.Fatal(err)
	}
	config := filepath.Join(dir, "config.json")
	raw, _ := json.Marshal(cfg)
	if err := os.WriteFile(config, raw, 0600); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(core)
	if err := prepareProbeProcess(cmd); err != nil {
		t.Fatal(err)
	}
	attribute := reflect.ValueOf(cmd.SysProcAttr).Elem().FieldByName("Pdeathsig")
	if !attribute.IsValid() || attribute.Int() != 9 {
		t.Fatal("missing SIGKILL parent-death signal")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	stop, err := startProbeCore(ctx, core, dir, config, address)
	if err != nil {
		t.Fatal(err)
	}
	cancel()
	if err := stop(); err != nil {
		t.Fatal(err)
	}
	conn, err := net.DialTimeout("tcp4", address, 100*time.Millisecond)
	if err == nil {
		_ = conn.Close()
		t.Fatal("owned core still listening after reap")
	}
}
