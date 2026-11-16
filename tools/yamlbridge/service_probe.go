package main

// Service probes own a separate, short-lived core. They never use the production
// controller, selector cache, listeners, or provider refresh mechanism.
import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"html"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"
)

type serviceProbeResult struct {
	Adapter           string `json:"adapter,omitempty"`
	RouteBinding      string `json:"route_binding,omitempty"`
	VerificationScope string `json:"verification_scope,omitempty"`
	PolicyAction      string `json:"policy_action,omitempty"`
	PolicyReason      string `json:"policy_reason,omitempty"`
	Profile           string `json:"profile"`
	Node              string `json:"node"`
	State             string `json:"state"`
	Reason            string `json:"reason"`
	HTTPStatus        int    `json:"http_status"`
	EgressBound       bool   `json:"egress_bound"`
	AccountVerified   bool   `json:"account_verified"`
	Precondition      string `json:"precondition,omitempty"`
}

var probeTargets = map[string]string{
	"gemini":    "https://gemini.google.com/app?hl=en",
	"openai":    "https://chatgpt.com/",
	"anthropic": "https://claude.ai/login",
}

var scriptMarkup = regexp.MustCompile(`(?is)<(script|style)\b[^>]*>.*?</(script|style)\s*>`)
var htmlMarkup = regexp.MustCompile(`(?s)<[^>]*>`)
var htmlComments = regexp.MustCompile(`(?s)<!--.*?-->`)

// This is a refusal guard, not an HTML/CSS renderer. When matching evidence
// coexists with these visibility structures, even an unrelated hidden element
// may make the page ambiguous; prefer unknown over inferring visibility.
var ambiguousVisibilityMarkup = regexp.MustCompile(`(?is)<template(?:[\s/>])|<[a-z][^>]*\shidden(?:[\s=/>])|<[a-z][^>]*\saria-hidden\s*=\s*(?:"true"|'true'|true(?:[\s/>]))|<[a-z][^>]*\sstyle\s*=\s*(?:"[^"]*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))|'[^']*(?:display\s*:\s*none|visibility\s*:\s*(?:hidden|collapse))|[^\s>]*(?:display:none|visibility:(?:hidden|collapse)))`)

func classifyServiceResponse(profile string, status int, body []byte, location string) serviceProbeResult {
	r := serviceProbeResult{Profile: profile, State: "unknown", Reason: "unrecognized_response", HTTPStatus: status}
	if _, ok := probeTargets[profile]; !ok {
		r.Reason = "unsupported_profile"
		return r
	}
	if status == 429 {
		r.Reason = "rate_limited"
		return r
	}
	if status == 401 || status == 407 {
		r.Reason = "authentication_required"
		return r
	}
	raw := strings.ToLower(string(body))
	markup := scriptMarkup.ReplaceAllString(htmlComments.ReplaceAllString(raw, " "), " ")
	text := html.UnescapeString(htmlMarkup.ReplaceAllString(markup, " "))
	text = strings.Join(strings.Fields(strings.NewReplacer("’", "'", "‘", "'").Replace(text)), " ")
	if strings.Contains(raw, "cf-chl-") || strings.Contains(raw, "challenges.cloudflare.com") || strings.Contains(text, "verify you are human") || strings.Contains(text, "just a moment...") {
		r.Reason = "browser_challenge"
		return r
	}
	// A redirect is not evidence that the application frontend loaded. Do not
	// follow authentication redirects with credentials or expose their queries.
	if status >= 300 && status < 400 {
		r.Reason = "redirect_unverified"
		if u, err := url.Parse(location); err == nil && (u.Hostname() == "accounts.google.com" || strings.Contains(u.Path, "/login") || strings.Contains(u.Path, "/auth")) {
			r.Reason = "authentication_required"
		}
		return r
	}
	product := map[string]string{"gemini": "gemini", "openai": "chatgpt", "anthropic": "claude"}[profile]
	region := false
	for _, phrase := range []string{"isn't available in your country", "is not available in your country", "isn't currently available in your country", "is not currently available in your country", "isn't supported in your country", "is not supported in your country", "isn't currently supported in your country", "is not currently supported in your country", "not available in your region", "not supported in your region"} {
		if strings.Contains(text, product+" "+phrase) {
			region = true
		}
	}
	// Exact observed Chinese rejection, including markup split between sentences.
	// As above, script/style/comment strings have already been removed.
	if profile == "gemini" && strings.Contains(strings.Join(strings.Fields(text), ""), "gemini目前不支持你所在的地区。敬请期待！") {
		region = true
	}
	// Only structured error fields count; bundled JavaScript containing a list
	// of possible errors must not turn a normal page into a region rejection.
	var doc struct {
		Error struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if json.Unmarshal(body, &doc) == nil {
		if profile == "openai" && doc.Error.Code == "unsupported_country_region_territory" {
			region = true
		}
		if profile == "gemini" && strings.Contains(strings.ToLower(doc.Error.Message), "user location is not supported") {
			region = true
		}
	}
	if region && (status == 200 || status == 400 || status == 403) {
		if ambiguousVisibilityMarkup.MatchString(markup) {
			r.Reason = "ambiguous_hidden_markup"
			return r
		}
		r.State = "region_denied"
		r.Reason = "explicit_region_rejection"
		return r
	}
	if status == 403 {
		r.Reason = "permission_or_policy_unknown"
		return r
	}
	if status >= 500 {
		r.Reason = "service_error"
		return r
	}
	if status != 200 {
		r.Reason = "unexpected_http_status"
		return r
	}
	if strings.Contains(text, "sign in") || strings.Contains(text, "log in") || strings.Contains(text, "login") {
		r.Reason = "authentication_required"
		return r
	}
	// Positive verdicts recognize bounded entry structure, not browser rendering
	// or executed application behavior. Ambiguous visibility fails closed.
	positive := false
	switch profile {
	case "gemini":
		positive = strings.Contains(markup, "<bard-chat-app") && strings.Contains(markup, "contenteditable=\"true\"") && (strings.Contains(text, "enter a prompt") || strings.Contains(text, "ask gemini"))
	case "openai":
		positive = strings.Contains(markup, "id=\"prompt-textarea\"") && strings.Contains(markup, "data-testid=\"send-button\"") && strings.Contains(text, "chatgpt")
	case "anthropic":
		positive = strings.Contains(markup, "contenteditable=\"true\"") && strings.Contains(markup, "data-testid=\"chat-input\"") && strings.Contains(text, "claude")
	}
	if positive {
		if ambiguousVisibilityMarkup.MatchString(markup) {
			r.Reason = "ambiguous_hidden_markup"
			return r
		}
		r.State = "frontend_available"
		r.Reason = "interactive_frontend_markup"
	}
	return r
}

type serviceProbeRuntime struct {
	baseContext      context.Context
	start            func(context.Context, string, string, string, string) (func() error, error)
	request          func(context.Context, string, string) (int, []byte, string, error)
	verifyBypass     func(int) bool
	verifyIPv6Bypass func() bool
}

func serviceProbe(profile, configPath, nodeName, corePath string, timeout time.Duration) (serviceProbeResult, error) {
	return serviceProbeWithContext(context.Background(), profile, configPath, nodeName, corePath, timeout)
}

func serviceProbeWithContext(ctx context.Context, profile, configPath, nodeName, corePath string, timeout time.Duration) (serviceProbeResult, error) {
	if !probePlatformSupported() {
		return serviceProbeResult{Profile: profile, Node: nodeName, State: "unknown", Reason: "probe_precondition_failed", Precondition: "unsupported_platform"}, nil
	}
	return serviceProbeWithRuntime(profile, configPath, nodeName, corePath, timeout, serviceProbeRuntime{baseContext: ctx, start: startProbeCore, request: requestProbeFrontend, verifyBypass: func(mark int) bool {
		// The caller must first verify this existing mark against the router's
		// OUTPUT bypass rules. A matching config value alone is not that proof.
		v, err := strconv.Atoi(os.Getenv("HOME_EDGE_SERVICE_PROBE_BYPASS_MARK"))
		return err == nil && mark > 0 && v == mark
	}, verifyIPv6Bypass: func() bool { return os.Getenv("HOME_EDGE_SERVICE_PROBE_IPV6_BYPASS") == "verified" }})
}

func privateProbeDocument(path string) (map[string]any, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, errors.New("probe source unavailable")
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxBytes {
		return nil, errors.New("unsupported probe source")
	}
	raw, err := io.ReadAll(io.LimitReader(f, maxBytes+1))
	if err != nil {
		return nil, errors.New("probe source unreadable")
	}
	encoded, err := convert("decode", raw)
	if err != nil {
		return nil, errors.New("invalid probe source")
	}
	var doc map[string]any
	if json.Unmarshal(encoded, &doc) != nil {
		return nil, errors.New("invalid probe source")
	}
	return doc, nil
}

func probeMark(v any) (int, bool) {
	f, ok := v.(float64)
	if !ok || f <= 0 || f > 2147483647 || f != float64(int(f)) {
		return 0, false
	}
	return int(f), true
}

func buildProbeConfig(configPath, nodeName, address, credential string) (map[string]any, int, error) {
	return buildProbeConfigWithIPv6(configPath, nodeName, address, credential, false)
}

func buildProbeConfigWithIPv6(configPath, nodeName, address, credential string, ipv6Verified bool) (map[string]any, int, error) {
	doc, err := privateProbeDocument(configPath)
	if err != nil {
		return nil, 0, err
	}
	mark, ok := probeMark(doc["routing-mark"])
	if !ok {
		return nil, 0, errors.New("routing_bypass_unverified")
	}
	ipv6Enabled := false
	if value, exists := doc["ipv6"]; exists {
		enabled, ok := value.(bool)
		if !ok {
			return nil, 0, errors.New("invalid_ipv6_setting")
		}
		if enabled && !ipv6Verified {
			return nil, 0, errors.New("ipv6_bypass_unverified")
		}
		ipv6Enabled = enabled
	}
	nodes := map[string]map[string]any{}
	add := func(list any) error {
		items, ok := list.([]any)
		if !ok {
			return errors.New("unsupported node inventory")
		}
		for _, item := range items {
			n, ok := item.(map[string]any)
			if !ok {
				return errors.New("unsupported node inventory")
			}
			name, ok := n["name"].(string)
			if !ok || name == "" {
				return errors.New("unsupported node inventory")
			}
			if _, exists := nodes[name]; exists {
				return errors.New("ambiguous node inventory")
			}
			nodes[name] = n
		}
		return nil
	}
	if p, exists := doc["proxies"]; exists {
		if err := add(p); err != nil {
			return nil, 0, err
		}
	}
	// Read existing cache files only. Relative paths depend on the original
	// core's -d argument, which this function does not know, so reject them.
	if providers, exists := doc["proxy-providers"]; exists {
		m, ok := providers.(map[string]any)
		if !ok {
			return nil, 0, errors.New("unsupported provider inventory")
		}
		for _, value := range m {
			p, ok := value.(map[string]any)
			if !ok {
				return nil, 0, errors.New("unsupported provider inventory")
			}
			if _, override := p["override"]; override {
				return nil, 0, errors.New("provider override unsupported")
			}
			if p["type"] == "inline" {
				if err := add(p["payload"]); err != nil {
					return nil, 0, err
				}
				continue
			}
			path, ok := p["path"].(string)
			if !ok || !filepath.IsAbs(path) {
				return nil, 0, errors.New("provider cache path unverified")
			}
			cached, err := privateProbeDocument(path)
			if err != nil {
				return nil, 0, errors.New("provider cache unavailable")
			}
			if err := add(cached["proxies"]); err != nil {
				return nil, 0, err
			}
		}
	}
	selected := []any{}
	visiting := map[string]bool{}
	done := map[string]bool{}
	var visit func(string) error
	visit = func(name string) error {
		if name == "DIRECT" {
			return nil
		}
		if done[name] {
			return nil
		}
		if visiting[name] {
			return errors.New("cyclic outbound dependency")
		}
		n, found := nodes[name]
		if !found {
			return errors.New("exact outbound unavailable")
		}
		visiting[name] = true
		server, ok := n["server"].(string)
		if !ok || server == "" || (!ipv6Verified && strings.Contains(server, ":")) {
			return errors.New("ipv6_or_unknown_server_unsupported")
		}
		if version, exists := n["ip-version"]; exists && version != "ipv4" && !ipv6Verified {
			return errors.New("outbound_ip_version_unsupported")
		}
		kind, _ := n["type"].(string)
		switch kind {
		case "http", "socks5", "ss", "ssr", "vmess", "vless", "trojan", "hysteria", "hysteria2", "tuic", "snell", "anytls":
		default:
			return errors.New("outbound type unsupported")
		}
		if value, exists := n["routing-mark"]; exists {
			nodeMark, valid := probeMark(value)
			if !valid || nodeMark != mark {
				return errors.New("outbound bypass mark differs")
			}
		}
		for _, key := range []string{"private-key", "certificate", "private-key-path", "certificate-path"} {
			if _, exists := n[key]; exists {
				return errors.New("outbound file dependency unsupported")
			}
		}
		if value, exists := n["dialer-proxy"]; exists {
			dep, ok := value.(string)
			if !ok || dep == "" {
				return errors.New("outbound dependency unsupported")
			}
			if err := visit(dep); err != nil {
				return err
			}
		}
		visiting[name] = false
		done[name] = true
		selected = append(selected, n)
		return nil
	}
	if nodeName == "DIRECT" {
		return nil, 0, errors.New("direct is not a service candidate")
	}
	if err := visit(nodeName); err != nil {
		return nil, 0, err
	}
	host, port, err := net.SplitHostPort(address)
	if err != nil || host != "127.0.0.1" {
		return nil, 0, errors.New("invalid private listener")
	}
	cfg := map[string]any{"mode": "rule", "log-level": "silent", "allow-lan": false, "ipv6": ipv6Enabled, "routing-mark": mark, "proxies": selected,
		"listeners": []any{map[string]any{"name": "home-edge-private-service-probe", "type": "http", "listen": host, "port": port, "proxy": nodeName, "users": []any{map[string]any{"username": "probe", "password": credential}}}},
		"rules":     []any{"MATCH,REJECT"}, "dns": map[string]any{"enable": false}, "tun": map[string]any{"enable": false}, "profile": map[string]any{"store-selected": false, "store-fake-ip": false}, "geo-auto-update": false}
	if value, exists := doc["interface-name"]; exists {
		if name, ok := value.(string); ok {
			cfg["interface-name"] = name
		} else {
			return nil, 0, errors.New("unsupported interface setting")
		}
	}
	return cfg, mark, nil
}

func serviceProbeWithRuntime(profile, configPath, nodeName, corePath string, timeout time.Duration, runtime serviceProbeRuntime) (result serviceProbeResult, retErr error) {
	result = serviceProbeResult{Profile: profile, Node: nodeName, State: "unknown", Reason: "probe_precondition_failed"}
	target, ok := probeTargets[profile]
	if !ok {
		return result, errors.New("unsupported service profile")
	}
	if timeout <= 0 || timeout > 2*time.Minute {
		return result, errors.New("probe timeout out of range")
	}
	base := runtime.baseContext
	if base == nil {
		base = context.Background()
	}
	ctx, cancel := context.WithTimeout(base, timeout)
	defer cancel()
	if base.Err() != nil {
		result.Reason = "probe_cancelled"
		return result, nil
	}
	dir, err := os.MkdirTemp("", "home-edge-service-probe-")
	if err != nil {
		return result, errors.New("cannot allocate private probe directory")
	}
	defer func() {
		if err := os.RemoveAll(dir); err != nil {
			result.State = "unknown"
			result.Reason = "probe_cleanup_failed"
			retErr = errors.New("private probe cleanup failed")
		}
	}()
	if os.Chmod(dir, 0700) != nil {
		return result, errors.New("cannot secure private probe directory")
	}
	l, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		return result, errors.New("private listener unavailable")
	}
	address := l.Addr().String()
	_ = l.Close()
	entropy := make([]byte, 24)
	if _, err := rand.Read(entropy); err != nil {
		return result, errors.New("cannot create probe credential")
	}
	credential := hex.EncodeToString(entropy)
	ipv6Verified := runtime.verifyIPv6Bypass != nil && runtime.verifyIPv6Bypass()
	cfg, mark, err := buildProbeConfigWithIPv6(configPath, nodeName, address, credential, ipv6Verified)
	if err != nil {
		result.Precondition = err.Error()
		return result, nil
	}
	if runtime.verifyBypass == nil || !runtime.verifyBypass(mark) {
		result.Precondition = "routing_bypass_unverified"
		return result, nil
	}
	data, err := json.Marshal(cfg)
	if err != nil {
		return result, errors.New("cannot encode probe configuration")
	}
	config := filepath.Join(dir, "probe.json")
	if os.WriteFile(config, data, 0600) != nil {
		return result, errors.New("cannot write private probe configuration")
	}
	stop, err := runtime.start(ctx, corePath, dir, config, address)
	if err != nil {
		result.Reason = "isolated_core_unavailable"
		return result, errors.New("isolated probe core failed")
	}
	defer func() {
		if stop == nil || stop() != nil {
			result.State = "unknown"
			result.Reason = "probe_process_cleanup_failed"
			retErr = errors.New("isolated probe cleanup failed")
		}
	}()
	proxy := &url.URL{Scheme: "http", Host: address, User: url.UserPassword("probe", credential)}
	status, body, location, err := runtime.request(ctx, proxy.String(), target)
	if base.Err() != nil {
		result.Reason = "probe_cancelled"
		return result, nil
	}
	if err != nil {
		result.Reason = "transport_or_body_incomplete"
		result.HTTPStatus = status
		result.EgressBound = true
		if status == 0 {
			result.State = "transport_failed"
			result.Reason = "request_transport_failed"
		}
		return result, nil
	}
	if ctx.Err() != nil {
		result.Reason = "probe_deadline_exceeded"
		return result, nil
	}
	result = classifyServiceResponse(profile, status, body, location)
	result.Node = nodeName
	result.EgressBound = true
	return result, nil
}

func startProbeCore(ctx context.Context, corePath, dir, config, address string) (func() error, error) {
	if !filepath.IsAbs(corePath) {
		return nil, errors.New("core path must be absolute")
	}
	// Linux parent-death signals are tied to the creating OS thread, not merely
	// the Go process. Keep this synchronous probe goroutine on that thread until
	// the owned child has been killed and reaped. stop is called by this same
	// goroutine before serviceProbeWithRuntime returns.
	runtime.LockOSThread()
	threadOwned := true
	defer func() {
		if threadOwned {
			runtime.UnlockOSThread()
		}
	}()
	test := exec.CommandContext(ctx, corePath, "-d", dir, "-f", config, "-t")
	if prepareProbeProcess(test) != nil {
		return nil, errors.New("probe process isolation unsupported")
	}
	test.Env = probeCoreEnvironment()
	test.Stdout = io.Discard
	test.Stderr = io.Discard
	if test.Run() != nil {
		return nil, errors.New("isolated config rejected")
	}
	cmd := exec.CommandContext(ctx, corePath, "-d", dir, "-f", config)
	if prepareProbeProcess(cmd) != nil {
		return nil, errors.New("probe process isolation unsupported")
	}
	cmd.Env = probeCoreEnvironment()
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	if cmd.Start() != nil {
		return nil, errors.New("isolated core start failed")
	}
	done := make(chan struct{})
	go func() { _ = cmd.Wait(); close(done) }()
	var once sync.Once
	var unlockOnce sync.Once
	stop := func() error {
		once.Do(func() { _ = cmd.Process.Kill() })
		select {
		case <-done:
			unlockOnce.Do(runtime.UnlockOSThread)
			return nil
		case <-time.After(3 * time.Second):
			return errors.New("core termination unverified")
		}
	}
	threadOwned = false // stop now owns releasing this thread after reaping.
	ticker := time.NewTicker(30 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			_ = stop()
			return nil, errors.New("core startup timed out")
		case <-done:
			_ = stop()
			return nil, errors.New("core exited before readiness")
		case <-ticker.C:
			conn, err := net.DialTimeout("tcp4", address, 100*time.Millisecond)
			if err == nil {
				_ = conn.Close()
				return stop, nil
			}
		}
	}
}

func probeCoreEnvironment() []string {
	clean := []string{}
	for _, entry := range os.Environ() {
		name, _, _ := strings.Cut(entry, "=")
		// Mihomo takes controller, script hooks and other overrides from these
		// variables even when -d/-f are explicit. Never inherit those effects.
		if !strings.HasPrefix(strings.ToUpper(name), "CLASH_") {
			clean = append(clean, entry)
		}
	}
	return clean
}

func requestProbeFrontend(ctx context.Context, proxyAddress, target string) (int, []byte, string, error) {
	proxy, err := url.Parse(proxyAddress)
	if err != nil {
		return 0, nil, "", errors.New("invalid probe proxy")
	}
	transport := &http.Transport{Proxy: http.ProxyURL(proxy), DisableKeepAlives: true, TLSHandshakeTimeout: 10 * time.Second, ResponseHeaderTimeout: 15 * time.Second}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return 0, nil, "", errors.New("invalid probe target")
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 home-edge-service-probe/1")
	req.Header.Set("Accept-Language", "en-US,en;q=0.9")
	req.Header.Set("Accept", "text/html,application/json")
	response, err := client.Do(req)
	if err != nil {
		return 0, nil, "", errors.New("probe request failed")
	}
	defer response.Body.Close()
	const bodyLimit = 2 * 1024 * 1024
	body, err := io.ReadAll(io.LimitReader(response.Body, bodyLimit+1))
	if err != nil || len(body) > bodyLimit {
		return response.StatusCode, nil, "", errors.New("probe response incomplete")
	}
	return response.StatusCode, body, response.Header.Get("Location"), nil
}
