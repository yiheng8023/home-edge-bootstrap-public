package main

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestProtocolObserverDoesNotRequireRuntimeOrController(t *testing.T) {
	old := serviceProxyRequest
	t.Cleanup(func() { serviceProxyRequest = old })
	serviceProxyRequest = func(ctx context.Context, proxy, target string) (int, []byte, string, error) {
		if proxy != "http://127.0.0.1:7890" || target != probeTargets["gemini"] {
			t.Fatal("protocol binding changed")
		}
		return 200, []byte(`<p>Gemini 目前不支持你所在的地区。敬请期待！</p>`), "", nil
	}
	r, err := serviceProxyObserver(context.Background(), "gemini", "http://127.0.0.1:7890", time.Second)
	if err != nil || r.State != "region_denied" || r.EgressBound || r.AccountVerified || r.RouteBinding != "proxy_endpoint_only" || r.Adapter != "http-proxy-observe" {
		t.Fatalf("protocol evidence scope incorrect: %+v %v", r, err)
	}
	if strings.Contains(r.Node, "127.0.0.1") {
		t.Fatal("endpoint leaked into report")
	}
	if r.PolicyAction == "select_candidate" || r.PolicyReason != "egress_unbound" {
		t.Fatalf("read-only adapter bypassed common policy: %+v", r)
	}
}

func TestProtocolObserverRejectsUnboundOrCredentialEndpoints(t *testing.T) {
	old := serviceProxyRequest
	t.Cleanup(func() { serviceProxyRequest = old })
	serviceProxyRequest = func(context.Context, string, string) (int, []byte, string, error) {
		t.Fatal("invalid endpoint used")
		return 0, nil, "", nil
	}
	for _, endpoint := range []string{"http://public.invalid:7890", "http://8.8.8.8:7890", "http://example@127.0.0.1:7890", "http://127.0.0.1:7890/path", "socks5://127.0.0.1:1080", "http://127.0.0.1:0", "http://127.0.0.1:7890?x=1"} {
		if _, err := serviceProxyObserver(context.Background(), "gemini", endpoint, time.Second); err == nil {
			t.Fatalf("unsafe endpoint accepted: %s", endpoint)
		}
	}
}

func TestProtocolObserverUnknownAndCancellationCannotBecomeNamedEvidence(t *testing.T) {
	old := serviceProxyRequest
	t.Cleanup(func() { serviceProxyRequest = old })
	serviceProxyRequest = func(context.Context, string, string) (int, []byte, string, error) {
		return 429, []byte("rate limited"), "", nil
	}
	r, err := serviceProxyObserver(context.Background(), "openai", "http://192.168.50.1:7890", time.Second)
	if err != nil || r.State != "unknown" || r.Reason != "rate_limited" || r.EgressBound {
		t.Fatalf("429 misclassified: %+v %v", r, err)
	}
	serviceProxyRequest = func(context.Context, string, string) (int, []byte, string, error) {
		return 0, nil, "", errors.New("unavailable")
	}
	r, err = serviceProxyObserver(context.Background(), "openai", "http://[::1]:7890", time.Second)
	if err != nil || r.State != "transport_failed" || r.EgressBound {
		t.Fatal("endpoint transport evidence incorrectly promoted")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	r, err = serviceProxyObserver(ctx, "openai", "http://127.0.0.1:7890", time.Second)
	if err != nil || r.State != "unknown" || r.Reason != "probe_cancelled" {
		t.Fatal("cancelled observation promoted")
	}
}
