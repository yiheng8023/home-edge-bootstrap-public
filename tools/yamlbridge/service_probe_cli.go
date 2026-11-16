package main

import (
	"context"
	"errors"
	"os"
	"os/signal"
	"syscall"
	"time"
)

// A one-off operator diagnostic uses the identical bounded backend as automation.
// Its private report is explicit about frontend scope and never contains bodies.
func runServiceProbe(args []string) error {
	if len(args) != 2 {
		return errors.New("usage: yamlbridge service-probe REQUEST NEW_REPORT")
	}
	var req struct {
		Adapter       string `json:"adapter"`
		ProxyURL      string `json:"proxy_url"`
		Profile       string `json:"profile"`
		RuntimeConfig string `json:"runtime_config"`
		CorePath      string `json:"core_path"`
		Node          string `json:"node"`
		Timeout       int    `json:"timeout_sec"`
	}
	raw, err := shRead(args[0], 64*1024)
	if err != nil || shDecode(raw, &req) != nil || !shServiceName(req.Profile) || req.Timeout < 1 || req.Timeout > 30 {
		return errors.New("invalid service-probe request")
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	var result serviceProbeResult
	switch req.Adapter {
	case "http-proxy-observe":
		result, err = serviceProxyObserver(ctx, req.Profile, req.ProxyURL, time.Duration(req.Timeout)*time.Second)
		if err != nil {
			return err
		}
	case "", "mihomo-isolated":
		if req.ProxyURL != "" {
			return errors.New("proxy endpoint requires an explicit observation adapter")
		}
		result, err = serviceProbeWithContext(ctx, req.Profile, req.RuntimeConfig, req.Node, req.CorePath, time.Duration(req.Timeout)*time.Second)
		result.Adapter, result.RouteBinding, result.VerificationScope = "mihomo-isolated", "named_egress", "frontend_only"
	default:
		return errors.New("unsupported service-probe adapter")
	}
	if err != nil {
		result.State = "unknown"
		if result.Reason == "" {
			result.Reason = "probe_unavailable"
		}
	}
	return shWriteJSON(args[1], result, true)
}
