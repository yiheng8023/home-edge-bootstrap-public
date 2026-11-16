package main

// The protocol observer needs an HTTP/S proxy, not a particular client/router.
// It cannot attest which named outbound that proxy used and has no mutation API.
import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net"
	"net/url"
	"strconv"
	"time"

	"home-edge-bootstrap/yamlbridge/internal/healthpolicy"
)

var serviceProxyRequest = requestProbeFrontend

func finishProxyObservation(result serviceProbeResult) serviceProbeResult {
	signal := healthpolicy.Unknown
	if result.State == "frontend_available" {
		signal = healthpolicy.Available
	}
	if result.State == "region_denied" || result.State == "transport_failed" {
		signal = healthpolicy.RepairableFailure
	}
	decision := healthpolicy.Decide(healthpolicy.Input{
		Mode:          healthpolicy.Observe,
		Current:       healthpolicy.Observation{Service: result.Profile, Route: result.Node, Version: "http-proxy-observe/v1", Signal: signal, Scope: healthpolicy.Frontend, EgressBound: result.EgressBound},
		RequiredScope: healthpolicy.Frontend,
		Capabilities:  healthpolicy.Capabilities{Observe: true, ProbeScopes: []healthpolicy.Scope{healthpolicy.Frontend}},
	}, healthpolicy.Memory{})
	result.PolicyAction, result.PolicyReason = string(decision.Action), decision.Reason
	return result
}

func serviceProxyObserver(ctx context.Context, profile, endpoint string, timeout time.Duration) (serviceProbeResult, error) {
	result := serviceProbeResult{Profile: profile, State: "unknown", AccountVerified: false,
		Adapter: "http-proxy-observe", RouteBinding: "proxy_endpoint_only", VerificationScope: "frontend_only"}
	target, supported := probeTargets[profile]
	u, err := url.Parse(endpoint)
	if !supported || err != nil || (u.Scheme != "http" && u.Scheme != "https") || u.User != nil || u.Opaque != "" || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return result, errors.New("invalid protocol observer request")
	}
	ip := net.ParseIP(u.Hostname())
	port, portErr := strconv.Atoi(u.Port())
	if ip == nil || (!ip.IsLoopback() && !ip.IsPrivate()) || portErr != nil || port < 1 || port > 65535 || timeout <= 0 || timeout > 30*time.Second {
		return result, errors.New("observer requires an explicit local/private proxy endpoint")
	}
	// Do not output the endpoint, embedded credentials, response body or account
	// information. This opaque identity denotes only this proxy endpoint.
	digest := sha256.Sum256([]byte(u.Scheme + "://" + u.Host))
	result.Node = "proxy-" + hex.EncodeToString(digest[:8])
	bounded, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	status, body, location, requestErr := serviceProxyRequest(bounded, endpoint, target)
	result.HTTPStatus = status
	if ctx.Err() != nil {
		result.Reason = "probe_cancelled"
		return finishProxyObservation(result), nil
	}
	if requestErr != nil {
		result.Reason = "transport_or_body_incomplete"
		if status == 0 {
			result.State = "transport_failed"
			result.Reason = "request_transport_failed"
		}
		return finishProxyObservation(result), nil
	}
	classified := classifyServiceResponse(profile, status, body, location)
	classified.Node, classified.Adapter = result.Node, result.Adapter
	classified.RouteBinding, classified.VerificationScope = result.RouteBinding, result.VerificationScope
	// A standard proxy supplies observation, not a controller, candidate pinning,
	// owned selection or recovery. Never promote this result into named-egress
	// evidence that could authorize an automatic switch.
	classified.EgressBound = false
	classified.AccountVerified = false
	return finishProxyObservation(classified), nil
}
