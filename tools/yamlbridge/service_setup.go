package main

// Service setup is an offline derivation. Activation and rollback belong to the
// caller; no input file, controller, selector cache or provider is modified here.
import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"unicode/utf8"

	"go.yaml.in/yaml/v3"
)

type setupService struct {
	Name        string `json:"name"`
	InitialNode string `json:"initial_node"`
	Mode        string `json:"mode"`
}
type serviceSetupRequest struct {
	SchemaVersion int            `json:"schema_version"`
	RuntimeConfig string         `json:"runtime_config"`
	GroupsOverlay string         `json:"groups_overlay,omitempty"`
	RulesOverlay  string         `json:"rules_overlay,omitempty"`
	Services      []setupService `json:"services"`
}

// Exact Gemini hosts deliberately do not claim all of Google. The shared auth
// host affects Google sign-in, a documented scope consequence of this profile.
var setupDomains = map[string][]string{
	"gemini":    {"DOMAIN,gemini.google.com", "DOMAIN,bard.google.com", "DOMAIN,aistudio.google.com", "DOMAIN,generativelanguage.googleapis.com", "DOMAIN,accounts.google.com", "DOMAIN,gemini.gstatic.com"},
	"openai":    {"DOMAIN-SUFFIX,chatgpt.com", "DOMAIN-SUFFIX,openai.com", "DOMAIN-SUFFIX,oaistatic.com", "DOMAIN-SUFFIX,oaiusercontent.com", "DOMAIN-SUFFIX,auth0.openai.com"},
	"anthropic": {"DOMAIN-SUFFIX,claude.ai", "DOMAIN-SUFFIX,anthropic.com", "DOMAIN-SUFFIX,claude.com"},
}

func setupGroupName(service string) string   { return "Edge-" + service }
func setupGroupMarker(service string) string { return "home-edge-service:v1:" + service }
func setupRuleMarker(service string) string  { return "home-edge-service-rule:v1:" + service }
func setupRules(service string) []string {
	r := make([]string, 0, len(setupDomains[service]))
	for _, domain := range setupDomains[service] {
		r = append(r, domain+","+setupGroupName(service))
	}
	return r
}
func setupHasLine(comment, line string) bool {
	for _, c := range strings.Split(comment, "\n") {
		if strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(c), "#")) == line {
			return true
		}
	}
	return false
}
func setupScalar(value string) *yaml.Node {
	return &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: value}
}
func setupNode(v any) *yaml.Node { var n yaml.Node; _ = n.Encode(v); return &n }
func setupValue(n *yaml.Node, key string) *yaml.Node {
	for i := 0; i+1 < len(n.Content); i += 2 {
		if n.Content[i].Value == key {
			return n.Content[i+1]
		}
	}
	return nil
}
func setupSet(n *yaml.Node, key string, value *yaml.Node) {
	for i := 0; i+1 < len(n.Content); i += 2 {
		if n.Content[i].Value == key {
			n.Content[i+1] = value
			return
		}
	}
	n.Content = append(n.Content, setupScalar(key), value)
}
func setupYAML(raw []byte, kind yaml.Kind) (*yaml.Node, error) {
	if len(raw) > maxBytes {
		return nil, errors.New("oversized setup input")
	}
	d := yaml.NewDecoder(bytes.NewReader(raw))
	var doc, extra yaml.Node
	if d.Decode(&doc) != nil || len(doc.Content) != 1 {
		return nil, errors.New("invalid setup YAML")
	}
	if d.Decode(&extra) != io.EOF {
		return nil, errors.New("multiple setup YAML documents")
	}
	var v any
	if doc.Decode(&v) != nil {
		return nil, errors.New("invalid or duplicate setup YAML fields")
	}
	if _, err := normalize(v, 0); err != nil {
		return nil, errors.New("unsupported setup YAML structure")
	}
	if doc.Content[0].Kind != kind {
		return nil, errors.New("unexpected setup YAML root")
	}
	return doc.Content[0], nil
}
func setupSequence(n *yaml.Node, key string) (*yaml.Node, error) {
	v := setupValue(n, key)
	if v == nil {
		v = &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
		setupSet(n, key, v)
	}
	if v.Kind != yaml.SequenceNode {
		return nil, errors.New("expected setup sequence")
	}
	return v, nil
}
func setupValidText(s string, limit int) bool {
	return len(s) > 0 && len(s) <= limit && utf8.ValidString(s) && !strings.ContainsAny(s, "\r\n\x00")
}
func validateSetupRequest(req serviceSetupRequest) error {
	if req.SchemaVersion != 1 || !setupValidText(req.RuntimeConfig, 4096) || len(req.GroupsOverlay) > 4096 || len(req.RulesOverlay) > 4096 || len(req.Services) < 1 || len(req.Services) > 3 {
		return errors.New("invalid setup request fields")
	}
	for _, s := range []string{req.GroupsOverlay, req.RulesOverlay} {
		if s != "" && !setupValidText(s, 4096) {
			return errors.New("invalid setup input path")
		}
	}
	seen := map[string]bool{}
	for _, s := range req.Services {
		if _, ok := setupDomains[s.Name]; !ok || seen[s.Name] || !setupValidText(s.InitialNode, 512) || (s.Mode != "auto" && s.Mode != "manual") {
			return errors.New("invalid or duplicate setup service")
		}
		seen[s.Name] = true
	}
	return nil
}

func setupManagedGroups(seq *yaml.Node, selected map[string]bool, nodes map[string]string) ([]*yaml.Node, error) {
	kept := []*yaml.Node{}
	seen := map[string]bool{}
	owned := map[string]int{}
	initials := map[string]string{}
	for _, n := range seq.Content {
		if n.Kind != yaml.MappingNode {
			return nil, errors.New("invalid proxy group")
		}
		name := setupValue(n, "name")
		if name == nil || name.Kind != yaml.ScalarNode || name.Tag != "!!str" || name.Value == "" || seen[name.Value] {
			return nil, errors.New("ambiguous proxy groups")
		}
		seen[name.Value] = true
		owner := ""
		for service := range setupDomains {
			base := setupGroupName(service)
			if name.Value == base || name.Value == base+"-Auto" {
				owner = service
			}
		}
		if owner != "" {
			if !setupHasLine(n.HeadComment, setupGroupMarker(owner)) {
				return nil, errors.New("reserved service group collision")
			}
			typeNode, all, proxies := setupValue(n, "type"), setupValue(n, "include-all"), setupValue(n, "proxies")
			if len(n.Content) != 8 || typeNode == nil || typeNode.Value != "select" || all == nil || all.Tag != "!!bool" || all.Value != "true" || proxies == nil || proxies.Kind != yaml.SequenceNode {
				return nil, errors.New("ambiguous managed service group")
			}
			for _, p := range proxies.Content {
				if p.Kind != yaml.ScalarNode || p.Tag != "!!str" {
					return nil, errors.New("ambiguous managed service child")
				}
			}
			initial := ""
			if name.Value == setupGroupName(owner)+"-Auto" {
				if len(proxies.Content) != 1 {
					return nil, errors.New("ambiguous managed service group")
				}
				initial = proxies.Content[0].Value
			} else {
				if len(proxies.Content) != 2 || (proxies.Content[0].Value != setupGroupName(owner)+"-Auto" && proxies.Content[1].Value != setupGroupName(owner)+"-Auto") {
					return nil, errors.New("ambiguous managed service group")
				}
				initial = proxies.Content[0].Value
				if initial == setupGroupName(owner)+"-Auto" {
					initial = proxies.Content[1].Value
				}
			}
			if nodes[initial] == "" || (initials[owner] != "" && initials[owner] != initial) {
				return nil, errors.New("managed service initial child mismatch")
			}
			initials[owner] = initial
			owned[owner]++
			if selected[owner] {
				continue
			}
		}
		kept = append(kept, n)
	}
	for _, count := range owned {
		if count != 2 {
			return nil, errors.New("incomplete managed service groups")
		}
	}
	return kept, nil
}
func setupNewGroups(s setupService) []*yaml.Node {
	base := setupGroupName(s.Name)
	order := []string{base + "-Auto", s.InitialNode}
	if s.Mode == "manual" {
		order = []string{s.InitialNode, base + "-Auto"}
	}
	outer := setupNode(map[string]any{"name": base, "type": "select", "proxies": order, "include-all": true})
	auto := setupNode(map[string]any{"name": base + "-Auto", "type": "select", "proxies": []string{s.InitialNode}, "include-all": true})
	outer.HeadComment = setupGroupMarker(s.Name)
	auto.HeadComment = setupGroupMarker(s.Name)
	return []*yaml.Node{outer, auto}
}
func setupRuntimeRules(seq *yaml.Node, services []setupService, selected map[string]bool) error {
	kept := []*yaml.Node{}
	for _, n := range seq.Content {
		if n.Kind != yaml.ScalarNode || n.Tag != "!!str" {
			return errors.New("invalid runtime rule")
		}
		owner := ""
		for service := range setupDomains {
			if setupHasLine(n.HeadComment, setupRuleMarker(service)) {
				owner = service
			}
		}
		if owner != "" {
			valid := false
			for _, r := range setupRules(owner) {
				if n.Value == r {
					valid = true
				}
			}
			if !valid {
				return errors.New("ambiguous managed runtime rule")
			}
			if selected[owner] {
				continue
			}
		}
		kept = append(kept, n)
	}
	seq.Content = nil
	for _, s := range services {
		for _, r := range setupRules(s.Name) {
			n := setupScalar(r)
			n.HeadComment = setupRuleMarker(s.Name)
			seq.Content = append(seq.Content, n)
		}
	}
	seq.Content = append(seq.Content, kept...)
	return nil
}
func setupOverlayRules(raw []byte, services []setupService, selected map[string]bool) ([]byte, error) {
	if len(raw) > maxBytes || !utf8.Valid(raw) || bytes.IndexByte(raw, 0) >= 0 {
		return nil, errors.New("invalid rules overlay")
	}
	lines := strings.Split(strings.ReplaceAll(string(raw), "\r\n", "\n"), "\n")
	kept := []string{}
	owner := ""
	block := []string{}
	seen := map[string]bool{}
	// ShellCrash's native overlay is a YAML sequence. Preserve legacy flat-line
	// overlays when present; an empty overlay starts in the native sequence form.
	sequenceStyle := true
	for _, line := range lines {
		trim := strings.TrimSpace(line)
		if trim != "" && !strings.HasPrefix(trim, "#") {
			sequenceStyle = strings.HasPrefix(trim, "- ")
			break
		}
	}
	ruleText := func(line string) string {
		return strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "- "))
	}
	for _, line := range lines {
		trim := strings.TrimSpace(line)
		if strings.HasPrefix(trim, "# BEGIN home-edge-service:v1:") {
			service := strings.TrimPrefix(trim, "# BEGIN home-edge-service:v1:")
			if _, ok := setupDomains[service]; !ok || owner != "" || seen[service] {
				return nil, errors.New("ambiguous managed rule block")
			}
			owner = service
			block = []string{line}
			seen[service] = true
			continue
		}
		if strings.HasPrefix(trim, "# END home-edge-service:v1:") {
			if owner == "" || trim != "# END "+setupGroupMarker(owner) {
				return nil, errors.New("unbalanced managed rule block")
			}
			expected := setupRules(owner)
			if len(block) != len(expected)+1 {
				return nil, errors.New("modified managed rule block")
			}
			for i, r := range expected {
				if ruleText(block[i+1]) != r {
					return nil, errors.New("modified managed rule block")
				}
			}
			if !selected[owner] {
				kept = append(kept, block...)
				kept = append(kept, line)
			}
			owner = ""
			block = nil
			continue
		}
		if owner != "" {
			block = append(block, line)
			continue
		}
		if trim != "" && !strings.HasPrefix(trim, "#") && (!strings.Contains(ruleText(trim), ",") || strings.HasPrefix(ruleText(trim), "-") || strings.ContainsAny(trim, "\r\t")) {
			return nil, errors.New("unsupported rules overlay format")
		}
		kept = append(kept, line)
	}
	if owner != "" {
		return nil, errors.New("unterminated managed rule block")
	}
	var b strings.Builder
	for _, s := range services {
		b.WriteString("# BEGIN " + setupGroupMarker(s.Name) + "\n")
		for _, r := range setupRules(s.Name) {
			if sequenceStyle {
				b.WriteString("  - ")
			}
			b.WriteString(r + "\n")
		}
		b.WriteString("# END " + setupGroupMarker(s.Name) + "\n")
	}
	b.WriteString(strings.Join(kept, "\n"))
	return []byte(b.String()), nil
}

// ShellCrash removes comments when synthesizing runtime.yaml. A reserved name
// alone is not ownership: the complete, marked persistent overlay must match
// the runtime group's semantic shape before its missing marker is restored in
// this private derivation. The original input files remain untouched.
func setupAuthorizeRuntime(runtimeGroups, overlayGroups, runtimeRules *yaml.Node, rulesRaw []byte) error {
	proof := map[string]*yaml.Node{}
	for _, group := range overlayGroups.Content {
		name := setupValue(group, "name")
		if name == nil {
			continue
		}
		for service := range setupDomains {
			base := setupGroupName(service)
			if (name.Value == base || name.Value == base+"-Auto") && setupHasLine(group.HeadComment, setupGroupMarker(service)) {
				proof[name.Value] = group
			}
		}
	}
	for _, group := range runtimeGroups.Content {
		name := setupValue(group, "name")
		if name == nil {
			continue
		}
		for service := range setupDomains {
			base := setupGroupName(service)
			if name.Value != base && name.Value != base+"-Auto" {
				continue
			}
			other := proof[name.Value]
			var actual, expected any
			if other == nil || group.Decode(&actual) != nil || other.Decode(&expected) != nil || !reflect.DeepEqual(actual, expected) {
				return errors.New("runtime service ownership not proven by overlay")
			}
			if !setupHasLine(group.HeadComment, setupGroupMarker(service)) {
				group.HeadComment = setupGroupMarker(service)
			}
		}
	}
	ruleProof := map[string]bool{}
	for _, line := range strings.Split(string(rulesRaw), "\n") {
		trim := strings.TrimSpace(line)
		for service := range setupDomains {
			if trim == "# BEGIN "+setupGroupMarker(service) {
				ruleProof[service] = true
			}
		}
	}
	seen := map[string]bool{}
	for _, rule := range runtimeRules.Content {
		for service := range setupDomains {
			for _, exact := range setupRules(service) {
				if rule.Value != exact {
					continue
				}
				if !ruleProof[service] || proof[setupGroupName(service)] == nil || seen[exact] {
					return errors.New("runtime service rule ownership not proven by overlay")
				}
				seen[exact] = true
				if !setupHasLine(rule.HeadComment, setupRuleMarker(service)) {
					rule.HeadComment = setupRuleMarker(service)
				}
			}
		}
	}
	return nil
}

func buildServiceSetup(req serviceSetupRequest, runtimeRaw, groupsRaw, rulesRaw []byte) (map[string][]byte, error) {
	if err := validateSetupRequest(req); err != nil {
		return nil, err
	}
	runtime, err := setupYAML(runtimeRaw, yaml.MappingNode)
	if err != nil {
		return nil, err
	}
	groups := &yaml.Node{Kind: yaml.SequenceNode, Tag: "!!seq"}
	if len(bytes.TrimSpace(groupsRaw)) > 0 {
		commentsOnly := true
		for _, line := range strings.Split(string(groupsRaw), "\n") {
			trim := strings.TrimSpace(line)
			if trim != "" && !strings.HasPrefix(trim, "#") {
				commentsOnly = false
				break
			}
		}
		if commentsOnly {
			if len(groupsRaw) > maxBytes || !utf8.Valid(groupsRaw) || bytes.IndexByte(groupsRaw, 0) >= 0 {
				return nil, errors.New("invalid groups overlay")
			}
			groups.HeadComment = strings.TrimSpace(string(groupsRaw))
		} else {
			groups, err = setupYAML(groupsRaw, yaml.SequenceNode)
			if err != nil {
				return nil, err
			}
		}
	}
	selected := map[string]bool{}
	for _, s := range req.Services {
		selected[s.Name] = true
	}
	runtimeGroups, err := setupSequence(runtime, "proxy-groups")
	if err != nil {
		return nil, err
	}
	// An initial selection must resolve to an explicit concrete outbound, never a
	// shared selector. Provider cache discovery needs caller-owned evidence.
	nodes := map[string]string{}
	proxies := setupValue(runtime, "proxies")
	if proxies == nil || proxies.Kind != yaml.SequenceNode {
		return nil, errors.New("concrete proxy inventory unavailable")
	}
	for _, n := range proxies.Content {
		if n.Kind != yaml.MappingNode {
			return nil, errors.New("invalid concrete proxy inventory")
		}
		name, kind := setupValue(n, "name"), setupValue(n, "type")
		if name == nil || kind == nil || name.Tag != "!!str" || kind.Tag != "!!str" || name.Value == "" || kind.Value == "" || nodes[name.Value] != "" {
			return nil, errors.New("ambiguous concrete proxy inventory")
		}
		for service := range setupDomains {
			base := setupGroupName(service)
			if name.Value == base || name.Value == base+"-Auto" {
				return nil, errors.New("reserved concrete proxy collision")
			}
		}
		nodes[name.Value] = kind.Value
	}
	for _, s := range req.Services {
		switch nodes[s.InitialNode] {
		case "http", "socks5", "ss", "ssr", "vmess", "vless", "trojan", "hysteria", "hysteria2", "tuic", "snell", "anytls", "wireguard", "ssh":
		default:
			return nil, errors.New("exact concrete initial node unavailable")
		}
	}
	rules, err := setupSequence(runtime, "rules")
	if err != nil {
		return nil, err
	}
	// Validate persistent ownership before using it as runtime evidence.
	if _, err := setupManagedGroups(groups, selected, nodes); err != nil {
		return nil, err
	}
	rulesOut, err := setupOverlayRules(rulesRaw, req.Services, selected)
	if err != nil {
		return nil, err
	}
	if err := setupAuthorizeRuntime(runtimeGroups, groups, rules, rulesRaw); err != nil {
		return nil, err
	}
	for _, seq := range []*yaml.Node{runtimeGroups, groups} {
		// Clash names share one outbound namespace across proxies and groups.
		for _, group := range seq.Content {
			if name := setupValue(group, "name"); name != nil && nodes[name.Value] != "" {
				return nil, errors.New("proxy and group name collision")
			}
		}
		kept, err := setupManagedGroups(seq, selected, nodes)
		if err != nil {
			return nil, err
		}
		seq.Content = kept
		for _, s := range req.Services {
			seq.Content = append(seq.Content, setupNewGroups(s)...)
		}
	}
	if err = setupRuntimeRules(rules, req.Services, selected); err != nil {
		return nil, err
	}
	runtimeOut, err := yaml.Marshal(runtime)
	if err != nil {
		return nil, errors.New("cannot encode runtime setup")
	}
	groupsOut, err := yaml.Marshal(groups)
	if err != nil {
		return nil, errors.New("cannot encode group setup")
	}
	return map[string][]byte{"runtime.yaml": runtimeOut, "groups.yaml": groupsOut, "rules.yaml": rulesOut}, nil
}

type setupFileDigest struct {
	Path   string `json:"path"`
	SHA256 string `json:"sha256"`
	Bytes  int    `json:"bytes"`
}

func setupDigest(path string, raw []byte) setupFileDigest {
	sum := sha256.Sum256(raw)
	return setupFileDigest{path, hex.EncodeToString(sum[:]), len(raw)}
}
func setupRead(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > maxBytes {
		return nil, errors.New("setup input unavailable or unsupported")
	}
	f, err := os.Open(path)
	if err != nil {
		return nil, errors.New("setup input unavailable")
	}
	defer f.Close()
	raw, err := io.ReadAll(io.LimitReader(f, maxBytes+1))
	if err != nil || len(raw) > maxBytes {
		return nil, errors.New("cannot read setup input")
	}
	return raw, nil
}
func runServiceSetup(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: yamlbridge service-setup REQUEST_FILE NEW_OUTPUT_DIR")
	}
	requestRaw, err := setupRead(args[0])
	if err != nil {
		return err
	}
	// encoding/json otherwise accepts duplicate object keys using the last value.
	if _, err := setupYAML(requestRaw, yaml.MappingNode); err != nil {
		return errors.New("invalid or duplicate setup request fields")
	}
	d := json.NewDecoder(bytes.NewReader(requestRaw))
	d.DisallowUnknownFields()
	var req serviceSetupRequest
	if d.Decode(&req) != nil {
		return errors.New("invalid setup request JSON")
	}
	var extra any
	if d.Decode(&extra) != io.EOF {
		return errors.New("multiple setup requests")
	}
	if err = validateSetupRequest(req); err != nil {
		return err
	}
	inputs := []setupFileDigest{setupDigest(args[0], requestRaw)}
	data := [][]byte{}
	for _, path := range []string{req.RuntimeConfig, req.GroupsOverlay, req.RulesOverlay} {
		var raw []byte
		if path != "" {
			raw, err = setupRead(path)
			if err != nil {
				return err
			}
			inputs = append(inputs, setupDigest(path, raw))
		}
		data = append(data, raw)
	}
	outputs, err := buildServiceSetup(req, data[0], data[1], data[2])
	if err != nil {
		return err
	}
	outputDigests := []setupFileDigest{}
	for _, name := range []string{"runtime.yaml", "groups.yaml", "rules.yaml"} {
		outputDigests = append(outputDigests, setupDigest(name, outputs[name]))
	}
	manifest := struct {
		SchemaVersion int               `json:"schema_version"`
		Kind          string            `json:"kind"`
		Inputs        []setupFileDigest `json:"inputs"`
		Outputs       []setupFileDigest `json:"outputs"`
		Services      []setupService    `json:"services"`
		ScopeNotes    []string          `json:"scope_notes"`
	}{1, "home-edge-service-setup", inputs, outputDigests, req.Services, []string{"Offline candidate only; activation and selected-cache reconciliation require caller verification.", "Gemini exact accounts.google.com rule also routes shared Google sign-in.", "Auto groups are controller-managed selectors; this setup does not claim service availability."}}
	outputs["manifest.json"], err = json.MarshalIndent(manifest, "", "  ")
	if err != nil {
		return errors.New("cannot encode setup manifest")
	}
	// Mkdir is exclusive: an existing directory, file or link is never reused.
	if os.Mkdir(args[1], 0700) != nil {
		return errors.New("setup output must be a new private directory")
	}
	for _, name := range []string{"runtime.yaml", "groups.yaml", "rules.yaml", "manifest.json"} {
		f, err := os.OpenFile(filepath.Join(args[1], name), os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if err != nil {
			return errors.New("cannot create private setup output")
		}
		_, writeErr := f.Write(outputs[name])
		closeErr := f.Close()
		if writeErr != nil || closeErr != nil {
			return errors.New("cannot write private setup output")
		}
	}
	return nil
}
