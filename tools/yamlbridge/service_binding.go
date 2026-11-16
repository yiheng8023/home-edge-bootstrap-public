package main

// Loaded-definition receipts are concrete adapter evidence. They are created
// only by a controlled successful reload, then invalidated by instance or
// general-setting changes. Instance UUIDs are not parameter hashes.
import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"syscall"
	"time"
)

const loadedBindingKind = "mihomo-inline-loaded-binding/v1"
const loadedBindingVersion = "v1.19.34"

type serviceBindRequest struct {
	SchemaVersion       int    `json:"schema_version"`
	API                 string `json:"api"`
	SecretFile          string `json:"secret_file"`
	RuntimeConfig       string `json:"runtime_config"`
	CorePath            string `json:"core_path"`
	ExpectedRuntimeHash string `json:"expected_runtime_sha256"`
	BeforeGraphFile     string `json:"expected_before_graph_file"`
}
type serviceLoadedBinding struct {
	SchemaVersion   int               `json:"schema_version"`
	Kind            string            `json:"kind"`
	UpstreamVersion string            `json:"upstream_version"`
	RuntimeHash     string            `json:"runtime_sha256"`
	CoreIdentity    string            `json:"core_identity"`
	ConfigsHash     string            `json:"configs_sha256"`
	NodeInstances   map[string]string `json:"node_instances"`
}

func bindingPrivateRead(path string, limit int64) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, errors.New("binding_input_unavailable")
	}
	return shRead(path, limit)
}
func bindingInlineNames(path string) ([]string, error) {
	raw, err := bindingPrivateRead(path, maxBytes)
	if err != nil {
		return nil, err
	}
	decoded, err := convert("decode", raw)
	if err != nil {
		return nil, err
	}
	var doc map[string]any
	if json.Unmarshal(decoded, &doc) != nil {
		return nil, errors.New("binding_source_invalid")
	}
	// Rule providers supply matchers only; their target remains in the static
	// RULE-SET rule. Proxy providers independently replace node instances.
	for _, key := range []string{"proxy-providers"} {
		if value, exists := doc[key]; exists && value != nil {
			m, ok := value.(map[string]any)
			if !ok || len(m) > 0 {
				return nil, errors.New("binding_provider_unsupported")
			}
		}
	}
	proxies, ok := doc["proxies"].([]any)
	if !ok || len(proxies) == 0 || len(proxies) > 10000 {
		return nil, errors.New("binding_inline_source_required")
	}
	names := []string{}
	seen := map[string]bool{}
	for _, value := range proxies {
		proxy, ok := value.(map[string]any)
		if !ok {
			return nil, errors.New("binding_inline_source_invalid")
		}
		name, ok := proxy["name"].(string)
		if !ok || name == "" || len(name) > 1024 || seen[name] {
			return nil, errors.New("binding_inline_source_invalid")
		}
		seen[name] = true
		names = append(names, name)
	}
	return names, nil
}
func bindingUUID(id string) bool {
	if len(id) != 36 || id[8] != '-' || id[13] != '-' || id[18] != '-' || id[23] != '-' || id[14] != '4' || !strings.ContainsRune("89abAB", rune(id[19])) {
		return false
	}
	_, err := hex.DecodeString(strings.ReplaceAll(id, "-", ""))
	return err == nil
}
func bindingGraph(raw []byte) (serviceHealthGraph, error) {
	var v struct {
		Proxies serviceHealthGraph `json:"proxies"`
	}
	if shUniqueJSON(raw, false) != nil || json.Unmarshal(raw, &v) != nil || len(v.Proxies) == 0 || len(v.Proxies) > 10000 {
		return nil, errors.New("binding_graph_invalid")
	}
	return v.Proxies, nil
}
func (c *serviceHealthController) bindingVersion(ctx context.Context) bool {
	raw, err := c.request(ctx, "GET", "/version", nil)
	if err != nil || shUniqueJSON(raw, false) != nil {
		return false
	}
	var v struct {
		Version string `json:"version"`
	}
	return json.Unmarshal(raw, &v) == nil && "v"+strings.TrimPrefix(v.Version, "v") == loadedBindingVersion
}
func (c *serviceHealthController) bindingConfigs(ctx context.Context) (string, error) {
	raw, err := c.request(ctx, "GET", "/configs", nil)
	if err != nil || shUniqueJSON(raw, false) != nil {
		return "", errors.New("binding_configs_unavailable")
	}
	d := json.NewDecoder(bytes.NewReader(raw))
	d.UseNumber()
	var value map[string]any
	if d.Decode(&value) != nil || value == nil || value["mode"] != "rule" {
		return "", errors.New("binding_rule_mode_required")
	}
	canonical, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	digest := sha256.Sum256(canonical)
	return hex.EncodeToString(digest[:]), nil
}

func (c *serviceHealthController) loadedDefinition(ctx context.Context, r serviceHealthRequest, g serviceHealthGraph) string {
	if r.LoadedBindingFile == "" {
		return "loaded_definition_unverified"
	}
	raw, err := bindingPrivateRead(r.LoadedBindingFile, 2*1024*1024)
	if err != nil {
		return "loaded_definition_unverified"
	}
	var binding serviceLoadedBinding
	if decodeServiceLoadedBinding(raw, &binding) != nil || binding.SchemaVersion != 1 || binding.Kind != loadedBindingKind || binding.UpstreamVersion != loadedBindingVersion || binding.CoreIdentity != shCoreIdentity(r.CorePath) {
		return "loaded_definition_unverified"
	}
	hash, err := shConfigHash(r.RuntimeConfig)
	if err != nil || hash != binding.RuntimeHash {
		return "loaded_definition_changed"
	}
	names, err := bindingInlineNames(r.RuntimeConfig)
	if err != nil {
		return "loaded_definition_unverified"
	}
	if len(names) != len(binding.NodeInstances) {
		return "loaded_definition_changed"
	}
	seen := map[string]bool{}
	for _, name := range names {
		id := binding.NodeInstances[name]
		proxy, exists := g[name]
		if !exists || !bindingUUID(id) || proxy.ID != id || seen[id] {
			return "loaded_definition_changed"
		}
		seen[id] = true
	}
	for _, spec := range r.Services {
		if group, exists := g[spec.AutoSelector]; exists {
			for _, name := range group.All {
				if _, bound := binding.NodeInstances[name]; !bound {
					return "loaded_definition_unverified"
				}
			}
		}
	}
	if !c.bindingVersion(ctx) {
		return "loaded_definition_unverified"
	}
	configs, err := c.bindingConfigs(ctx)
	if err != nil || configs != binding.ConfigsHash {
		return "loaded_definition_changed"
	}
	return ""
}

func decodeServiceLoadedBinding(raw []byte, binding *serviceLoadedBinding) error {
	// Schema fields remain ASCII and reject case aliases. Node names are opaque,
	// case-sensitive data keys; Chinese/emoji names are not schema identifiers.
	if shUniqueJSON(raw, false) != nil {
		return errors.New("invalid loaded binding")
	}
	var top map[string]json.RawMessage
	if json.Unmarshal(raw, &top) != nil || top == nil {
		return errors.New("invalid loaded binding")
	}
	nodes := top["node_instances"]
	if nodes == nil {
		return errors.New("missing binding node map")
	}
	top["node_instances"] = json.RawMessage(`{}`)
	schema, err := json.Marshal(top)
	if err != nil || shDecode(schema, binding) != nil {
		return errors.New("invalid loaded binding schema")
	}
	if json.Unmarshal(nodes, &binding.NodeInstances) != nil {
		return errors.New("invalid binding node map")
	}
	return nil
}

func bindServiceRuntime(ctx context.Context, request serviceBindRequest, c *serviceHealthController) (serviceLoadedBinding, error) {
	return inspectOrBindServiceRuntime(ctx, request, c, false)
}

func inspectOrBindServiceRuntime(ctx context.Context, request serviceBindRequest, c *serviceHealthController, checkOnly bool) (serviceLoadedBinding, error) {
	var empty serviceLoadedBinding
	pre := func() (serviceLoadedBinding, error) { return empty, errors.New("binding_precondition_failed") }
	if request.SchemaVersion != 1 || !filepath.IsAbs(request.RuntimeConfig) || !filepath.IsAbs(request.CorePath) || !filepath.IsAbs(request.BeforeGraphFile) || len(request.ExpectedRuntimeHash) != 64 {
		return pre()
	}
	names, err := bindingInlineNames(request.RuntimeConfig)
	if err != nil {
		return pre()
	}
	hash, err := shConfigHash(request.RuntimeConfig)
	if err != nil || hash != request.ExpectedRuntimeHash {
		return pre()
	}
	coreInfo, err := os.Stat(request.CorePath)
	if err != nil || !coreInfo.Mode().IsRegular() {
		return pre()
	}
	core := shCoreIdentity(request.CorePath)
	beforeRaw, err := bindingPrivateRead(request.BeforeGraphFile, 2*1024*1024)
	if err != nil {
		return pre()
	}
	before, err := bindingGraph(beforeRaw)
	if err != nil {
		return pre()
	}
	actual, err := c.graph(ctx)
	if err != nil || !reflect.DeepEqual(actual, before) || !c.bindingVersion(ctx) {
		return pre()
	}
	if _, err = c.bindingConfigs(ctx); err != nil {
		return pre()
	}
	existing := 0
	for _, name := range names {
		if proxy, ok := before[name]; ok {
			if !bindingUUID(proxy.ID) {
				return pre()
			}
			existing++
		}
	}
	if existing == 0 {
		return pre()
	}
	// Repeat the subject/source checks immediately before the one authorized
	// reload; no flag supplied by the caller can stand in for this observation.
	actual, err = c.graph(ctx)
	currentHash, hashErr := shConfigHash(request.RuntimeConfig)
	if err != nil || !reflect.DeepEqual(actual, before) || hashErr != nil || hash != currentHash || core != shCoreIdentity(request.CorePath) {
		return pre()
	}
	if checkOnly {
		return empty, nil
	}
	// ShellCrash can launch with -d /jffs/... and -f /tmp/... . Mihomo rejects
	// an explicit API path outside its safe roots even when that file is its
	// configured startup input. Send only the exact already-hashed bytes through
	// the authenticated loopback API; never widen SAFE_PATHS or repeat a PUT.
	source, err := bindingPrivateRead(request.RuntimeConfig, maxBytes)
	if err != nil || setupDigest("", source).SHA256 != hash {
		return pre()
	}
	payload, _ := json.Marshal(map[string]string{"payload": string(source)})
	if _, err = c.request(ctx, "PUT", "/configs", payload); err != nil {
		return empty, errors.New("binding_reload_unconfirmed")
	}
	postFailure := func() (serviceLoadedBinding, error) { return empty, errors.New("binding_post_reload_unverified") }
	after, err := c.graph(ctx)
	if err != nil || !c.bindingVersion(ctx) {
		return postFailure()
	}
	currentHash, err = shConfigHash(request.RuntimeConfig)
	if err != nil || hash != currentHash || core != shCoreIdentity(request.CorePath) {
		return postFailure()
	}
	configs, err := c.bindingConfigs(ctx)
	if err != nil {
		return postFailure()
	}
	instances := map[string]string{}
	seen := map[string]bool{}
	for _, name := range names {
		proxy, ok := after[name]
		if !ok || !bindingUUID(proxy.ID) || seen[proxy.ID] {
			return postFailure()
		}
		if previous, existed := before[name]; existed && previous.ID == proxy.ID {
			return postFailure()
		}
		seen[proxy.ID] = true
		instances[name] = proxy.ID
	}
	confirm, err := c.graph(ctx)
	if err != nil || !reflect.DeepEqual(confirm, after) {
		return postFailure()
	}
	lastConfigs, err := c.bindingConfigs(ctx)
	if err != nil || lastConfigs != configs {
		return postFailure()
	}
	lastHash, err := shConfigHash(request.RuntimeConfig)
	if err != nil || lastHash != hash || core != shCoreIdentity(request.CorePath) {
		return postFailure()
	}
	return serviceLoadedBinding{SchemaVersion: 1, Kind: loadedBindingKind, UpstreamVersion: loadedBindingVersion, RuntimeHash: hash, CoreIdentity: core, ConfigsHash: configs, NodeInstances: instances}, nil
}

func runServiceBindReload(args []string) error {
	return runServiceBindingCommand(args, false)
}

func runServiceBindCheck(args []string) error {
	return runServiceBindingCommand(args, true)
}

func runServiceBindingCommand(args []string, checkOnly bool) error {
	if len(args) != 2 {
		return errors.New("usage: yamlbridge service-bind-reload REQUEST NEW_BINDING")
	}
	if _, err := os.Lstat(args[1]); !os.IsNotExist(err) {
		return errors.New("binding_output_must_be_new")
	}
	raw, err := bindingPrivateRead(args[0], 65536)
	if err != nil {
		return errors.New("binding_request_invalid")
	}
	var request serviceBindRequest
	if shDecode(raw, &request) != nil {
		return errors.New("binding_request_invalid")
	}
	// Reuse endpoint validation without weakening the concrete adapter's loopback
	// boundary. No request-controlled redirect or ambient proxy is used.
	validation := serviceHealthRequest{SchemaVersion: 1, Mode: "observe", API: request.API, RuntimeConfig: request.RuntimeConfig, CorePath: request.CorePath, Services: []serviceHealthSpec{{Name: "gemini", Selector: "Edge-gemini", AutoSelector: "Edge-gemini-Auto"}}}
	if validation.validate() != nil {
		return errors.New("binding_request_invalid")
	}
	credential := ""
	if request.SecretFile != "" {
		info, err := os.Lstat(request.SecretFile)
		if err != nil || (runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0) {
			return errors.New("binding_credential_invalid")
		}
		raw, err = bindingPrivateRead(request.SecretFile, 4096)
		if err != nil {
			return errors.New("binding_credential_invalid")
		}
		credential = strings.TrimSuffix(strings.TrimSuffix(string(raw), "\n"), "\r")
		if credential == "" {
			return errors.New("binding_credential_invalid")
		}
		for _, c := range credential {
			if c < 32 || c == 127 {
				return errors.New("binding_credential_invalid")
			}
		}
	}
	base, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(base, 2*time.Minute)
	defer cancel()
	transport := &http.Transport{Proxy: nil, DialContext: (&net.Dialer{Timeout: 3 * time.Second}).DialContext, DisableKeepAlives: true}
	defer transport.CloseIdleConnections()
	c := &serviceHealthController{api: validation.API, credential: credential, client: &http.Client{Transport: transport, Timeout: 5 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return errors.New("redirect refused") }}}
	binding, err := inspectOrBindServiceRuntime(ctx, request, c, checkOnly)
	if err != nil {
		return err
	}
	if checkOnly {
		return shWriteJSON(args[1], map[string]any{"schema_version": 1, "binding_preflight": "passed", "runtime_reload_state": "not_requested"}, true)
	}
	if err = shWriteJSONBounded(args[1], binding, true, 2*1024*1024); err != nil {
		return errors.New("binding_output_failed_after_reload")
	}
	return nil
}
