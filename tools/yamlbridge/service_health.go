package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"reflect"
	"runtime"
	"sort"
	"strings"
	"syscall"
	"time"

	"home-edge-bootstrap/yamlbridge/internal/healthpolicy"
)

// The backend must probe an isolated, concrete outbound. It must never select a
// production group while testing. Tests replace this seam, not the HTTP client.
var serviceHealthProbe = serviceProbeWithContext
var serviceHealthNow = time.Now

type serviceHealthSpec struct {
	Name         string `json:"name"`
	Selector     string `json:"selector"`
	AutoSelector string `json:"auto_selector"`
}

type serviceHealthRequest struct {
	SchemaVersion     int                 `json:"schema_version"`
	Mode              string              `json:"mode"`
	API               string              `json:"api"`
	SecretFile        string              `json:"secret_file"`
	RuntimeConfig     string              `json:"runtime_config"`
	CorePath          string              `json:"core_path"`
	StateDir          string              `json:"state_dir"`
	LoadedBindingFile string              `json:"loaded_binding_file,omitempty"`
	FailChecks        int                 `json:"fail_checks"`
	CooldownSec       int                 `json:"cooldown_sec"`
	MaxAttempts       int                 `json:"max_attempts_per_hour"`
	MaxCandidates     int                 `json:"max_candidates"`
	ProbeTimeout      int                 `json:"probe_timeout_sec"`
	Services          []serviceHealthSpec `json:"services"`
}

type serviceHealthEntry struct {
	Name            string `json:"name"`
	State           string `json:"state"`
	ProbeState      string `json:"probe_state,omitempty"`
	ProbeReason     string `json:"probe_reason,omitempty"`
	PolicyReason    string `json:"policy_reason,omitempty"`
	Failures        int    `json:"failures,omitempty"`
	AccountVerified bool   `json:"account_verified"`
	Pending         bool   `json:"pending,omitempty"`
}

type serviceHealthReport struct {
	SchemaVersion     int                  `json:"schema_version"`
	ObservedAt        int64                `json:"observed_at"`
	Mode              string               `json:"mode"`
	VerificationScope string               `json:"verification_scope"`
	Services          []serviceHealthEntry `json:"services"`
}

type serviceHealthRecord struct {
	Fingerprint     string                `json:"fingerprint"`
	Failures        int                   `json:"failures"`
	LastAttempt     int64                 `json:"last_attempt"`
	ManualHeld      bool                  `json:"manual_held,omitempty"`
	Pending         *serviceHealthPending `json:"pending,omitempty"`
	CandidateOffset int                   `json:"candidate_offset,omitempty"`
}

type serviceHealthPending struct {
	From               string `json:"from"`
	To                 string `json:"to"`
	ConfigHash         string `json:"config_hash"`
	CoreIdentity       string `json:"core_identity"`
	BeforeGraph        string `json:"before_graph"`
	AfterGraph         string `json:"after_graph"`
	StartedAt          int64  `json:"started_at"`
	RollbackReservedAt int64  `json:"rollback_reserved_at"`
}

type serviceHealthState struct {
	SchemaVersion int                            `json:"schema_version"`
	Attempts      []int64                        `json:"attempts"`
	Services      map[string]serviceHealthRecord `json:"services"`
}

type serviceHealthProxy struct {
	ID   string   `json:"id,omitempty"`
	Type string   `json:"type"`
	Now  string   `json:"now,omitempty"`
	All  []string `json:"all,omitempty"`
}
type serviceHealthGraph map[string]serviceHealthProxy

type serviceHealthController struct {
	api          string
	credential   string
	client       *http.Client
	lockOwned    func() bool
	coreIdentity string
}

func (c *serviceHealthController) saveState(path string, state *serviceHealthState) error {
	if c.lockOwned == nil || !c.lockOwned() {
		return errors.New("state lock ownership changed")
	}
	return shWriteJSON(path, state, false)
}

func shRead(path string, limit int64) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, errors.New("cannot read private input")
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > limit {
		return nil, errors.New("invalid private input")
	}
	b, err := io.ReadAll(io.LimitReader(f, limit+1))
	if err != nil || int64(len(b)) > limit {
		return nil, errors.New("invalid private input")
	}
	return b, nil
}

func shDecode(raw []byte, target any) error {
	if shUniqueJSON(raw, true) != nil {
		return errors.New("invalid service-health JSON")
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.DisallowUnknownFields()
	if d.Decode(target) != nil {
		return errors.New("invalid service-health JSON")
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return errors.New("invalid service-health JSON")
	}
	return nil
}

// encoding/json otherwise accepts the last duplicate key. Reject ambiguous
// request/state objects, including differently cased aliases of struct fields.
func shUniqueJSON(raw []byte, fold bool) error {
	d := json.NewDecoder(bytes.NewReader(raw))
	var value func(int) error
	value = func(depth int) error {
		if depth > 64 {
			return errors.New("excessive JSON nesting")
		}
		token, err := d.Token()
		if err != nil {
			return err
		}
		delim, compound := token.(json.Delim)
		if !compound {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]bool{}
			for d.More() {
				key, err := d.Token()
				if err != nil {
					return err
				}
				name, ok := key.(string)
				if !ok {
					return errors.New("invalid JSON key")
				}
				if fold {
					// The request/state schema has ASCII keys only. This also
					// excludes Unicode case-fold aliases accepted by encoding/json.
					for _, r := range name {
						if r > 127 {
							return errors.New("invalid JSON schema key")
						}
					}
					name = strings.ToLower(name)
				}
				if seen[name] {
					return errors.New("duplicate JSON key")
				}
				seen[name] = true
				if err := value(depth + 1); err != nil {
					return err
				}
			}
		case '[':
			for d.More() {
				if err := value(depth + 1); err != nil {
					return err
				}
			}
		default:
			return errors.New("invalid JSON delimiter")
		}
		end, err := d.Token()
		if err != nil {
			return err
		}
		if (delim == '{' && end != json.Delim('}')) || (delim == '[' && end != json.Delim(']')) {
			return errors.New("invalid JSON delimiter")
		}
		return nil
	}
	if err := value(0); err != nil {
		return err
	}
	if _, err := d.Token(); err != io.EOF {
		return errors.New("extra JSON value")
	}
	return nil
}

func (r *serviceHealthRequest) validate() error {
	if r.SchemaVersion != 1 || (r.Mode != "observe" && r.Mode != "auto") || len(r.Services) == 0 || len(r.Services) > 3 {
		return errors.New("invalid service-health request")
	}
	u, err := url.Parse(r.API)
	if err != nil || u.Scheme != "http" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return errors.New("controller must use loopback HTTP")
	}
	ip := net.ParseIP(u.Hostname())
	if ip == nil || !ip.IsLoopback() || u.Port() == "" {
		return errors.New("controller must use loopback HTTP")
	}
	r.API = strings.TrimRight(r.API, "/")
	if r.FailChecks == 0 {
		r.FailChecks = 3
	}
	if r.CooldownSec == 0 {
		r.CooldownSec = 1800
	}
	if r.MaxAttempts == 0 {
		r.MaxAttempts = 2
	}
	if r.MaxCandidates == 0 {
		r.MaxCandidates = 3
	}
	if r.ProbeTimeout == 0 {
		r.ProbeTimeout = 15
	}
	if r.FailChecks < 1 || r.FailChecks > 20 || r.CooldownSec < 1 || r.CooldownSec > 86400 || r.MaxAttempts < 1 || r.MaxAttempts > 20 || r.MaxCandidates < 1 || r.MaxCandidates > 3 || r.ProbeTimeout < 1 || r.ProbeTimeout > 30 {
		return errors.New("invalid service-health limits")
	}
	if r.RuntimeConfig == "" || r.CorePath == "" || (r.Mode == "auto" && !filepath.IsAbs(r.StateDir)) {
		return errors.New("missing service-health paths")
	}
	if r.LoadedBindingFile != "" && !filepath.IsAbs(r.LoadedBindingFile) {
		return errors.New("invalid loaded binding path")
	}
	seen := map[string]bool{}
	for _, s := range r.Services {
		if !shServiceName(s.Name) || seen[s.Name] || s.Selector != "Edge-"+s.Name || s.AutoSelector != "Edge-"+s.Name+"-Auto" {
			return errors.New("invalid registered service selector")
		}
		seen[s.Name] = true
	}
	return nil
}

func shServiceName(name string) bool {
	return name == "gemini" || name == "openai" || name == "anthropic"
}
func shSelectable(p serviceHealthProxy) bool {
	return strings.EqualFold(p.Type, "selector") || strings.EqualFold(p.Type, "select")
}
func shContains(all []string, item string) bool {
	for _, v := range all {
		if v == item {
			return true
		}
	}
	return false
}
func shConcrete(g serviceHealthGraph, node string) bool {
	if len(node) == 0 || len(node) > 1024 {
		return false
	}
	p, ok := g[node]
	if !ok || len(p.All) != 0 || p.Now != "" || p.Type == "" {
		return false
	}
	switch strings.ToLower(p.Type) {
	case "direct", "reject", "pass", "passrule", "selector", "select", "urltest", "fallback", "loadbalance", "relay":
		return false
	}
	return node != "DIRECT" && node != "REJECT"
}

func shResolveLeaf(g serviceHealthGraph, node string) string {
	seen := map[string]bool{}
	for depth := 0; depth < 32; depth++ {
		if seen[node] {
			return ""
		}
		seen[node] = true
		if shConcrete(g, node) {
			return node
		}
		p, ok := g[node]
		if !ok || p.Now == "" || !shContains(p.All, p.Now) {
			return ""
		}
		node = p.Now
	}
	return ""
}

// Ownership is structural as well as nominal: the Auto group has exactly one
// incoming group reference, from its registered outer selector. Candidate groups
// are forbidden so changing one service cannot move another service's outbound.
func shOwned(g serviceHealthGraph, s serviceHealthSpec) bool {
	outer, ok := g[s.Selector]
	if !ok || !shSelectable(outer) || !shContains(outer.All, s.AutoSelector) {
		return false
	}
	auto, ok := g[s.AutoSelector]
	if !ok || !shSelectable(auto) || len(auto.All) == 0 || !shContains(auto.All, auto.Now) {
		return false
	}
	refs := 0
	for name, p := range g {
		if name == "GLOBAL" {
			if p.Now == s.AutoSelector {
				return false
			}
			continue
		}
		for _, child := range p.All {
			if child == s.AutoSelector {
				if name != s.Selector {
					return false
				}
				refs++
			}
		}
	}
	if refs != 1 {
		return false
	}
	for _, node := range auto.All {
		// include-all can repeat an explicitly seeded concrete node. A repeated
		// name still resolves to the same uniquely named live instance.
		if !shConcrete(g, node) {
			return false
		}
	}
	return true
}

func (c *serviceHealthController) request(ctx context.Context, method, path string, payload []byte) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, method, c.api+path, bytes.NewReader(payload))
	if err != nil {
		return nil, errors.New("controller request failed")
	}
	if c.credential != "" {
		req.Header.Set("Authorization", "Bearer "+c.credential)
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.client.Do(req)
	if err != nil {
		return nil, errors.New("controller request failed")
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024+1))
	if err != nil || len(b) > 2*1024*1024 || resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, errors.New("controller request failed")
	}
	return b, nil
}

func (c *serviceHealthController) graph(ctx context.Context) (serviceHealthGraph, error) {
	b, err := c.request(ctx, "GET", "/proxies", nil)
	if err != nil {
		return nil, err
	}
	var response struct {
		Proxies serviceHealthGraph `json:"proxies"`
	}
	if shUniqueJSON(b, false) != nil || json.Unmarshal(b, &response) != nil || len(response.Proxies) == 0 || len(response.Proxies) > 10000 {
		return nil, errors.New("invalid controller graph")
	}
	return response.Proxies, nil
}

func (c *serviceHealthController) ruleMode(ctx context.Context) bool {
	b, err := c.request(ctx, "GET", "/configs", nil)
	if err != nil || shUniqueJSON(b, false) != nil {
		return false
	}
	var config struct {
		Mode string `json:"mode"`
	}
	return json.Unmarshal(b, &config) == nil && config.Mode == "rule"
}

func shConfigHash(path string) (string, error) {
	b, err := shRead(path, maxBytes)
	if err != nil {
		return "", err
	}
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:]), nil
}

// Only the Auto group definition and its intended outer membership may name
// the private group. Check all source fields: graph.All does not reveal listener,
// sub-rule, dialer-proxy or provider override references.
func shRulesExclusive(path, auto string) (string, bool) {
	raw, err := shRead(path, maxBytes)
	if err != nil {
		return "", false
	}
	h := sha256.Sum256(raw)
	hash := hex.EncodeToString(h[:])
	decoded, err := convert("decode", raw)
	if err != nil {
		return "", false
	}
	var config map[string]any
	if json.Unmarshal(decoded, &config) != nil {
		return "", false
	}
	var walk func(any) bool
	walk = func(value any) bool {
		switch v := value.(type) {
		case string:
			if strings.Contains(v, auto) {
				return false
			}
		case []any:
			for _, child := range v {
				if !walk(child) {
					return false
				}
			}
		case map[string]any:
			for key, child := range v {
				if strings.Contains(key, auto) || !walk(child) {
					return false
				}
			}
		}
		return true
	}
	groups, ok := config["proxy-groups"].([]any)
	if !ok {
		return "", false
	}
	definitions, outerDefinitions, references := 0, 0, 0
	outer := strings.TrimSuffix(auto, "-Auto")
	for key, value := range config {
		if key != "proxy-groups" && !walk(value) {
			return "", false
		}
	}
	for _, value := range groups {
		group, ok := value.(map[string]any)
		if !ok {
			return "", false
		}
		name, _ := group["name"].(string)
		if name == auto {
			definitions++
		}
		if name == outer {
			outerDefinitions++
		}
		for key, field := range group {
			if key == "name" && name == auto {
				continue
			}
			if key == "proxies" && name == outer {
				members, ok := field.([]any)
				if !ok {
					return "", false
				}
				for _, member := range members {
					if node, ok := member.(string); ok && node == auto {
						references++
						continue
					}
					if !walk(member) {
						return "", false
					}
				}
			} else if !walk(field) {
				return "", false
			}
		}
	}
	if definitions != 1 || outerDefinitions != 1 || references != 1 {
		return "", false
	}
	return hash, true
}

func shChainHash(g serviceHealthGraph, s serviceHealthSpec, config, core string) string {
	// Registered Auto groups contain only concrete entries. Include both selected
	// edges and membership so prior failures cannot authorize a changed policy.
	b, _ := json.Marshal([]any{config, core, s, g[s.Selector], g[s.AutoSelector], g[g[s.AutoSelector].Now].ID})
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func shCoreIdentity(path string) string {
	parts := []any{filepath.Clean(path)}
	if info, err := os.Stat(path); err == nil {
		parts = append(parts, info.Size(), info.ModTime().UnixNano(), info.Mode().String())
	}
	if strings.HasPrefix(path, "/proc/") && strings.HasSuffix(path, "/exe") {
		if raw, err := shRead(strings.TrimSuffix(path, "/exe")+"/stat", 8192); err == nil {
			if end := strings.LastIndex(string(raw), ")"); end >= 0 {
				fields := strings.Fields(string(raw)[end+1:])
				if len(fields) > 19 {
					parts = append(parts, fields[19])
				}
			}
		}
	}
	b, _ := json.Marshal(parts)
	hash := sha256.Sum256(b)
	return hex.EncodeToString(hash[:])
}

func shGraphHash(g serviceHealthGraph) string {
	b, _ := json.Marshal(g)
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
func shWithSelection(g serviceHealthGraph, group, node string) serviceHealthGraph {
	copy := make(serviceHealthGraph, len(g))
	for k, v := range g {
		copy[k] = v
	}
	p := copy[group]
	p.Now = node
	copy[group] = p
	return copy
}
func shHasRepairTime(ctx context.Context, r serviceHealthRequest) bool {
	deadline, ok := ctx.Deadline()
	return ok && time.Until(deadline) >= time.Duration(r.ProbeTimeout)*time.Second+90*time.Second
}

func shHasRollbackTime(ctx context.Context) bool {
	deadline, ok := ctx.Deadline()
	return ok && time.Until(deadline) >= 45*time.Second
}

func shReleaseReservation(state *serviceHealthState, at int64) {
	for i := len(state.Attempts) - 1; i >= 0; i-- {
		if state.Attempts[i] == at {
			state.Attempts = append(state.Attempts[:i], state.Attempts[i+1:]...)
			return
		}
	}
}

func shSafeDir(path string) error {
	if !filepath.IsAbs(path) || filepath.Clean(path) == string(filepath.Separator) {
		return errors.New("invalid state directory")
	}
	for current := filepath.Clean(path); ; current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err == nil && (!info.IsDir() || info.Mode()&os.ModeSymlink != 0) {
			return errors.New("unsafe state directory")
		}
		if err != nil && !os.IsNotExist(err) {
			return errors.New("unsafe state directory")
		}
		if parent := filepath.Dir(current); parent == current {
			break
		}
	}
	if os.MkdirAll(path, 0700) != nil {
		return errors.New("cannot prepare private state")
	}
	return nil
}

func shWriteJSON(path string, value any, newOnly bool) error {
	return shWriteJSONBounded(path, value, newOnly, 65536)
}

func shWriteJSONBounded(path string, value any, newOnly bool, limit int) error {
	b, err := json.Marshal(value)
	if err != nil || len(b) > limit {
		return errors.New("invalid service-health output")
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".service-health-*")
	if err != nil {
		return errors.New("cannot stage service-health output")
	}
	tmp := f.Name()
	defer os.Remove(tmp)
	if f.Chmod(0600) != nil {
		f.Close()
		return errors.New("cannot secure service-health output")
	}
	_, writeErr := f.Write(append(b, '\n'))
	syncErr := f.Sync()
	closeErr := f.Close()
	if writeErr != nil || syncErr != nil || closeErr != nil {
		return errors.New("cannot write service-health output")
	}
	if newOnly {
		if os.Link(tmp, path) != nil {
			return errors.New("report must be a new private file")
		}
		return nil
	}
	if info, err := os.Lstat(path); err == nil && (!info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0) {
		return errors.New("unsafe state file")
	}
	if os.Rename(tmp, path) != nil {
		return errors.New("cannot commit private state")
	}
	return nil
}

func shLoadState(path string, now int64) (serviceHealthState, error) {
	s := serviceHealthState{SchemaVersion: 1, Services: map[string]serviceHealthRecord{}}
	if info, err := os.Lstat(path); os.IsNotExist(err) {
		return s, nil
	} else if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return s, errors.New("unsafe service-health state")
	}
	b, err := shRead(path, 65536)
	if err != nil {
		return s, err
	}
	if shDecode(b, &s) != nil || s.SchemaVersion != 1 || len(s.Attempts) > 64 || len(s.Services) > 3 || s.Services == nil {
		return s, errors.New("invalid service-health state")
	}
	for name, r := range s.Services {
		if !shServiceName(name) || r.Failures < 0 || r.Failures > 20 || r.LastAttempt < 0 || r.LastAttempt > now || r.CandidateOffset < 0 || r.CandidateOffset > 10000 {
			return s, errors.New("invalid or future service-health state")
		}
		if p := r.Pending; p != nil {
			if p.From == "" || p.To == "" || len(p.From) > 1024 || len(p.To) > 1024 || p.From == p.To || len(p.ConfigHash) != 64 || len(p.CoreIdentity) != 64 || len(p.BeforeGraph) != 64 || len(p.AfterGraph) != 64 || p.StartedAt < 0 || p.StartedAt > now || p.RollbackReservedAt < 0 || p.RollbackReservedAt > now {
				return s, errors.New("invalid pending service-health state")
			}
		}
	}
	kept := []int64{}
	for _, t := range s.Attempts {
		if t < 0 || t > now {
			return s, errors.New("invalid or future service-health attempts")
		}
		if t > now-3600 {
			kept = append(kept, t)
		}
	}
	s.Attempts = kept
	return s, nil
}

func shProbe(ctx context.Context, r serviceHealthRequest, s serviceHealthSpec, node string) (string, bool, string) {
	if ctx.Err() != nil {
		return "unknown", false, "probe_cancelled"
	}
	timeout := time.Duration(r.ProbeTimeout) * time.Second
	if deadline, ok := ctx.Deadline(); ok && time.Until(deadline) < timeout {
		return "unknown", false, "probe_deadline"
	}
	p, err := serviceHealthProbe(ctx, s.Name, r.RuntimeConfig, node, r.CorePath, timeout)
	if err != nil || ctx.Err() != nil || !p.EgressBound || p.Profile != s.Name || p.Node != node {
		return "unknown", false, "unbound_or_invalid_probe"
	}
	// Never treat rate limits, credentials or challenges as repair evidence, even
	// if a backend accidentally supplies a contradictory coarse state.
	if p.HTTPStatus == 429 || p.HTTPStatus == 401 || p.HTTPStatus == 407 {
		return "unknown", false, "authentication_or_rate_limit"
	}
	reason := p.Reason
	if len(reason) > 80 {
		reason = "unrecognized_response"
	}
	for _, character := range reason {
		if !((character >= 'a' && character <= 'z') || (character >= '0' && character <= '9') || character == '_') {
			reason = "unrecognized_response"
			break
		}
	}
	switch p.State {
	case "frontend_available", "region_denied", "transport_failed":
		return p.State, p.AccountVerified, reason
	default:
		return "unknown", false, reason
	}
}

func (c *serviceHealthController) fresh(ctx context.Context, r serviceHealthRequest, expected serviceHealthGraph, hash string) bool {
	if c.coreIdentity != "" && c.coreIdentity != shCoreIdentity(r.CorePath) {
		return false
	}
	if r.Mode == "auto" && (c.lockOwned == nil || !c.lockOwned()) {
		return false
	}
	current, err := c.graph(ctx)
	if err != nil || !reflect.DeepEqual(current, expected) {
		return false
	}
	currentHash, err := shConfigHash(r.RuntimeConfig)
	return err == nil && hash == currentHash && (r.Mode != "auto" || c.loadedDefinition(ctx, r, current) == "")
}

func (c *serviceHealthController) put(ctx context.Context, group, node string) error {
	if c.lockOwned == nil || !c.lockOwned() {
		return errors.New("writer ownership changed")
	}
	b, _ := json.Marshal(map[string]string{"name": node})
	_, err := c.request(ctx, "PUT", "/proxies/"+url.PathEscape(group), b)
	return err
}

// This concrete adapter declares only the operations it actually implements.
// Fresh guarded reads are deliberately not advertised as atomic compare-and-set.
var serviceHealthPolicyCapabilities = func() healthpolicy.Capabilities {
	return healthpolicy.Capabilities{Observe: true, NamedEgressProbe: true, GuardedSelection: true, ManualHold: true, RecoveryPersistence: true, ProbeScopes: []healthpolicy.Scope{healthpolicy.Frontend}}
}

func shPolicyObservation(service, route, version, probe string) healthpolicy.Observation {
	signal := healthpolicy.Unknown
	switch probe {
	case "frontend_available":
		signal = healthpolicy.Available
	case "region_denied", "transport_failed":
		signal = healthpolicy.RepairableFailure
	}
	return healthpolicy.Observation{Service: service, Route: route, Version: version, Signal: signal, Scope: healthpolicy.Frontend, EgressBound: probe != "unknown"}
}

func shPolicyMemory(record serviceHealthRecord, service, route string) healthpolicy.Memory {
	return healthpolicy.Memory{Service: service, Route: route, Version: record.Fingerprint, Failures: record.Failures, LastAttempt: record.LastAttempt, ManualHeld: record.ManualHeld}
}

func shPolicyInput(r serviceHealthRequest, s serviceHealthSpec, route, version, probe string, manual bool, attempts int) healthpolicy.Input {
	return healthpolicy.Input{Mode: healthpolicy.Mode(r.Mode), Manual: manual, Current: shPolicyObservation(s.Name, route, version, probe), RequiredScope: healthpolicy.Frontend, Capabilities: serviceHealthPolicyCapabilities(), Rules: healthpolicy.Rules{FailureChecks: r.FailChecks, CooldownSeconds: int64(r.CooldownSec), AttemptLimit: r.MaxAttempts, WriteReservation: 2}, Now: serviceHealthNow().Unix(), RecentAttempts: attempts}
}

func shReconcilePending(ctx context.Context, r serviceHealthRequest, c *serviceHealthController, state *serviceHealthState, path string, s serviceHealthSpec, g serviceHealthGraph, hash string) serviceHealthEntry {
	entry := serviceHealthEntry{Name: s.Name, State: "pending_unresolved", Pending: true}
	if limitation := serviceHealthPolicyCapabilities().RepairLimitation(healthpolicy.Frontend); limitation != "" {
		entry.PolicyReason = limitation
		return entry
	}
	record := state.Services[s.Name]
	p := record.Pending
	if p == nil {
		return entry
	}
	if p.ConfigHash != hash || p.CoreIdentity != c.coreIdentity {
		entry.State = "pending_incompatible"
		return entry
	}
	if record.ManualHeld {
		entry.State = "pending_superseded"
		return entry
	}
	graphHash := shGraphHash(g)
	if graphHash != p.BeforeGraph && graphHash != p.AfterGraph {
		entry.State = "pending_superseded"
		return entry
	}
	if !c.fresh(ctx, r, g, hash) {
		return entry
	}
	clear := func(status string) {
		record.Pending = nil
		record.Failures = 0
		record.CandidateOffset = 0
		record.Fingerprint = shChainHash(g, s, hash, c.coreIdentity)
		state.Services[s.Name] = record
		entry.Pending = false
		entry.State = status
		if c.saveState(path, state) != nil {
			entry.State = "state_unavailable"
			entry.Pending = true
		}
	}
	if graphHash == p.BeforeGraph {
		shReleaseReservation(state, p.RollbackReservedAt)
		clear("pending_not_applied")
		return entry
	}
	if g[s.AutoSelector].Now != p.To || !shContains(g[s.AutoSelector].All, p.From) {
		entry.State = "pending_superseded"
		return entry
	}
	probe, account, reason := shProbe(ctx, r, s, p.To)
	entry.ProbeState = probe
	entry.ProbeReason = reason
	entry.AccountVerified = account
	if !c.fresh(ctx, r, g, hash) {
		return entry
	}
	if probe == "frontend_available" {
		shReleaseReservation(state, p.RollbackReservedAt)
		clear("pending_verified")
		return entry
	}
	if probe != "region_denied" && probe != "transport_failed" {
		return entry
	}
	if !shHasRepairTime(ctx, r) {
		entry.State = "pending_deadline_held"
		return entry
	}
	now := serviceHealthNow().Unix()
	if p.RollbackReservedAt <= now-3600 {
		if len(state.Attempts) >= r.MaxAttempts {
			entry.State = "pending_attempt_budget"
			return entry
		}
		state.Attempts = append(state.Attempts, now)
		p.RollbackReservedAt = now
		record.Pending = p
		state.Services[s.Name] = record
		if c.saveState(path, state) != nil {
			entry.State = "state_unavailable"
			return entry
		}
	}
	before := shWithSelection(g, s.AutoSelector, p.From)
	if shGraphHash(before) != p.BeforeGraph || !c.fresh(ctx, r, g, hash) || !shHasRollbackTime(ctx) {
		return entry
	}
	err := c.put(ctx, s.AutoSelector, p.From)
	if c.fresh(ctx, r, before, hash) {
		g = before
		clear("pending_rolled_back")
	} else if err != nil {
		entry.State = "pending_rollback_unresolved"
	}
	return entry
}

func shProcess(ctx context.Context, r serviceHealthRequest, c *serviceHealthController, state *serviceHealthState, statePath string, s serviceHealthSpec) serviceHealthEntry {
	entry := serviceHealthEntry{Name: s.Name, State: "unknown"}
	if c.coreIdentity == "" {
		c.coreIdentity = shCoreIdentity(r.CorePath)
	}
	entry.Pending = state.Services[s.Name].Pending != nil
	g, err := c.graph(ctx)
	if err != nil {
		return entry
	}
	outer, exists := g[s.Selector]
	if !exists || !shSelectable(outer) {
		entry.State = "registration_invalid"
		return entry
	}
	if outer.Now != s.AutoSelector {
		entry.State = "manual_held"
		manualHash, hashErr := shConfigHash(r.RuntimeConfig)
		manualLeaf := shResolveLeaf(g, s.Selector)
		if manualLeaf != "" {
			entry.ProbeState, entry.AccountVerified, entry.ProbeReason = shProbe(ctx, r, s, manualLeaf)
		} else {
			entry.ProbeState = "unknown"
		}
		manualRequest := r
		manualRequest.Mode = "observe"
		if hashErr != nil || !c.fresh(ctx, manualRequest, g, manualHash) {
			entry.ProbeState = "unknown"
			entry.AccountVerified = false
		}
		record := state.Services[s.Name]
		manualDecision := healthpolicy.Decide(shPolicyInput(r, s, manualLeaf, shChainHash(g, s, manualHash, c.coreIdentity), entry.ProbeState, true, len(state.Attempts)), shPolicyMemory(record, s.Name, manualLeaf))
		entry.PolicyReason = manualDecision.Reason
		if r.Mode == "auto" {
			// Record the mode boundary without incrementing or changing failover
			// counters while the user's manual choice is held.
			record.ManualHeld = manualDecision.Memory.ManualHeld
			record.CandidateOffset = 0
			state.Services[s.Name] = record
			if c.saveState(statePath, state) != nil {
				entry.State = "state_unavailable"
			}
		}
		return entry
	}
	hash, exclusive := shRulesExclusive(r.RuntimeConfig, s.AutoSelector)
	if !shOwned(g, s) || !exclusive {
		entry.State = "ownership_unverified"
		return entry
	}
	if r.Mode == "auto" && !c.ruleMode(ctx) {
		entry.State = "mode_held"
		return entry
	}
	if r.Mode == "auto" {
		if reason := c.loadedDefinition(ctx, r, g); reason != "" {
			entry.State = "observe_only"
			entry.ProbeState = "unknown"
			entry.ProbeReason = reason
			entry.PolicyReason = reason
			return entry
		}
	}
	if r.Mode == "auto" && state.Services[s.Name].Pending != nil {
		return shReconcilePending(ctx, r, c, state, statePath, s, g, hash)
	}
	current := g[s.AutoSelector].Now
	probe, account, reason := shProbe(ctx, r, s, current)
	if !c.fresh(ctx, r, g, hash) {
		entry.State = "selection_changed"
		return entry
	}
	entry.ProbeState, entry.AccountVerified = probe, account
	entry.ProbeReason = reason
	record := state.Services[s.Name]
	fingerprint := shChainHash(g, s, hash, c.coreIdentity)
	previousPolicyMemory := shPolicyMemory(record, s.Name, current)
	policyInput := shPolicyInput(r, s, current, fingerprint, probe, false, len(state.Attempts))
	policyDecision := healthpolicy.Decide(policyInput, previousPolicyMemory)
	entry.PolicyReason = policyDecision.Reason
	if r.Mode == "observe" {
		if policyDecision.Action == healthpolicy.KeepCurrent {
			entry.State = "healthy"
		} else {
			entry.State = "observed"
		}
		return entry
	}
	now := serviceHealthNow().Unix()
	if record.Fingerprint != fingerprint || record.ManualHeld {
		record.CandidateOffset = 0
	}
	record.Fingerprint = policyDecision.Memory.Version
	record.Failures = policyDecision.Memory.Failures
	record.ManualHeld = policyDecision.Memory.ManualHeld
	record.LastAttempt = policyDecision.Memory.LastAttempt
	if policyDecision.Action == healthpolicy.KeepCurrent {
		record.CandidateOffset = 0
	}
	state.Services[s.Name] = record
	if c.saveState(statePath, state) != nil {
		entry.State = "state_unavailable"
		return entry
	}
	entry.Failures = record.Failures
	if policyDecision.Action == healthpolicy.KeepCurrent {
		entry.State = "healthy"
		return entry
	}
	if policyDecision.Action == healthpolicy.ObserveOnly {
		return entry
	}
	if policyDecision.Action == healthpolicy.AwaitFailures {
		entry.State = "failure_pending"
		return entry
	}
	if policyDecision.Action == healthpolicy.Hold {
		entry.State = policyDecision.Reason
		return entry
	}
	candidates := []string{}
	seenCandidates := map[string]bool{}
	for _, node := range g[s.AutoSelector].All {
		if node != current && !seenCandidates[node] {
			candidates = append(candidates, node)
			seenCandidates[node] = true
		}
	}
	sort.Strings(candidates)
	if len(candidates) == 0 {
		entry.State = "no_verified_candidate"
		return entry
	}
	start := record.CandidateOffset % len(candidates)
	tested := 0
	for i := 0; i < len(candidates) && tested < r.MaxCandidates; i++ {
		candidate := candidates[(start+i)%len(candidates)]
		tested++
		result, _, _ := shProbe(ctx, r, s, candidate)
		candidateObservation := shPolicyObservation(s.Name, candidate, fingerprint, result)
		candidateInput := policyInput
		candidateInput.Candidate = &candidateObservation
		candidateDecision := healthpolicy.Decide(candidateInput, previousPolicyMemory)
		if candidateDecision.Action != healthpolicy.SelectCandidate {
			continue
		}
		if !c.fresh(ctx, r, g, hash) {
			entry.State = "selection_changed"
			return entry
		}
		if !shHasRepairTime(ctx, r) {
			entry.State = "deadline_held"
			return entry
		}
		record.LastAttempt = now
		record.Failures = 0
		record.CandidateOffset = (start + tested) % len(candidates)
		expected := shWithSelection(g, s.AutoSelector, candidate)
		record.Pending = &serviceHealthPending{From: current, To: candidate, ConfigHash: hash, CoreIdentity: c.coreIdentity, BeforeGraph: shGraphHash(g), AfterGraph: shGraphHash(expected), StartedAt: now, RollbackReservedAt: now}
		entry.Pending = true
		state.Services[s.Name] = record
		state.Attempts = append(state.Attempts, now, now)
		if c.saveState(statePath, state) != nil {
			entry.State = "state_unavailable"
			return entry
		}
		// Re-read after state persistence as well, immediately before the PUT.
		if !c.fresh(ctx, r, g, hash) || !shHasRepairTime(ctx, r) {
			entry.State = "selection_changed"
			return entry
		}
		putErr := c.put(ctx, s.AutoSelector, candidate)
		if c.fresh(ctx, r, expected, hash) {
			post, verified, postReason := shProbe(ctx, r, s, candidate)
			if post == "frontend_available" && c.fresh(ctx, r, expected, hash) {
				entry.State = "repaired"
				entry.ProbeState = post
				entry.ProbeReason = postReason
				entry.AccountVerified = verified
				shReleaseReservation(state, now)
				record.Pending = nil
				record.CandidateOffset = 0
				entry.Pending = false
				record.Fingerprint = shChainHash(expected, s, hash, c.coreIdentity)
				state.Services[s.Name] = record
				if c.saveState(statePath, state) != nil {
					entry.State = "repaired_state_unavailable"
				}
				return entry
			}
			if c.fresh(ctx, r, expected, hash) && shHasRollbackTime(ctx) {
				rollbackErr := c.put(ctx, s.AutoSelector, current)
				if rollbackErr == nil && c.fresh(ctx, r, g, hash) {
					entry.State = "rolled_back"
					record.Pending = nil
					entry.Pending = false
					state.Services[s.Name] = record
					if c.saveState(statePath, state) != nil {
						entry.State = "state_unavailable"
						entry.Pending = true
					}
				} else {
					entry.State = "rollback_unresolved"
				}
				return entry
			}
		}
		// PUT timeout/failure can still have applied. A fresh unchanged graph proves
		// no repair, but any other state is left alone to preserve later choices.
		if putErr != nil && c.fresh(ctx, r, g, hash) {
			entry.State = "switch_failed"
			shReleaseReservation(state, now)
			record.Pending = nil
			entry.Pending = false
			state.Services[s.Name] = record
			if c.saveState(statePath, state) != nil {
				entry.State = "state_unavailable"
				entry.Pending = true
			}
		} else {
			entry.State = "selection_changed_or_unresolved"
		}
		return entry
	}
	entry.State = "no_verified_candidate"
	record.CandidateOffset = (start + tested) % len(candidates)
	state.Services[s.Name] = record
	if c.saveState(statePath, state) != nil {
		entry.State = "state_unavailable"
	}
	return entry
}

func runServiceHealth(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: yamlbridge service-health REQUEST_JSON NEW_REPORT_JSON")
	}
	if _, err := os.Lstat(args[1]); !os.IsNotExist(err) {
		return errors.New("report must be a new private file")
	}
	b, err := shRead(args[0], 65536)
	if err != nil {
		return err
	}
	var r serviceHealthRequest
	if shDecode(b, &r) != nil {
		return errors.New("invalid service-health request")
	}
	if err := r.validate(); err != nil {
		return err
	}
	credential := ""
	if r.SecretFile != "" {
		info, err := os.Lstat(r.SecretFile)
		if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
			return errors.New("invalid controller secret file")
		}
		if runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0 {
			return errors.New("controller secret file must be private")
		}
		raw, err := shRead(r.SecretFile, 4096)
		if err != nil {
			return err
		}
		credential = strings.TrimSuffix(strings.TrimSuffix(string(raw), "\n"), "\r")
		if credential == "" || strings.ContainsAny(credential, "\r\n") {
			return errors.New("invalid controller secret file")
		}
		for _, v := range credential {
			if v < 32 || v == 127 {
				return errors.New("invalid controller secret file")
			}
		}
	}
	signals, stopSignals := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stopSignals()
	ctx, cancel := context.WithTimeout(signals, 10*time.Minute)
	defer cancel()
	transport := &http.Transport{Proxy: nil, DialContext: (&net.Dialer{Timeout: 3 * time.Second}).DialContext, DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	c := &serviceHealthController{api: r.API, credential: credential, client: &http.Client{Transport: transport, Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("controller redirect refused") }}}
	state := serviceHealthState{SchemaVersion: 1, Services: map[string]serviceHealthRecord{}}
	statePath := ""
	report := serviceHealthReport{SchemaVersion: 1, ObservedAt: serviceHealthNow().Unix(), Mode: r.Mode, VerificationScope: "frontend_only", Services: []serviceHealthEntry{}}
	stateFailure := func(status string) error {
		for _, s := range r.Services {
			report.Services = append(report.Services, serviceHealthEntry{Name: s.Name, State: status})
		}
		return shWriteJSON(args[1], report, true)
	}
	if r.Mode == "auto" {
		if err := shSafeDir(r.StateDir); err != nil {
			return stateFailure("state_unavailable")
		}
		var releaseLease func()
		c.lockOwned, releaseLease, err = acquireServiceHealthLock(r.StateDir)
		if err != nil {
			return stateFailure("state_locked")
		}
		defer releaseLease()
		globalOwned, guardErr := captureServiceGlobalGuard()
		if guardErr != nil {
			return stateFailure("global_writer_ownership_unverified")
		}
		if globalOwned != nil {
			engineOwned := c.lockOwned
			c.lockOwned = func() bool { return engineOwned() && globalOwned() }
		}
		statePath = filepath.Join(r.StateDir, "service-health.json")
		state, err = shLoadState(statePath, serviceHealthNow().Unix())
		if err != nil {
			return stateFailure("state_unavailable")
		}
	}
	for _, s := range r.Services {
		report.Services = append(report.Services, shProcess(ctx, r, c, &state, statePath, s))
	}
	return shWriteJSON(args[1], report, true)
}
