package healthpolicy

import "testing"

func fullInput() Input {
	return Input{Mode: Automatic, RequiredScope: Frontend, Now: 10000,
		Current:      Observation{Service: "service-a", Route: "route-old", Version: "revision-one", Signal: RepairableFailure, Scope: Frontend, EgressBound: true},
		Capabilities: Capabilities{Observe: true, NamedEgressProbe: true, GuardedSelection: true, ManualHold: true, RecoveryPersistence: true, ProbeScopes: []Scope{Frontend}},
		Rules:        Rules{FailureChecks: 3, CooldownSeconds: 1800, AttemptLimit: 2, WriteReservation: 2},
	}
}

func TestTwoAdaptersShareUnchangedPolicy(t *testing.T) {
	// A selector-owning adapter reports opaque route identities and capabilities.
	full := fullInput()
	type ownedSnapshot struct {
		selections map[string]string
		revision   string
	}
	owned := ownedSnapshot{selections: map[string]string{"service-a": "route-old", "service-b": "separate-route"}, revision: "revision-one"}
	full.Current.Route = owned.selections[full.Current.Service]
	full.Current.Version = owned.revision
	candidate := full.Current
	candidate.Route = "route-new"
	candidate.Signal = Available
	full.Candidate = &candidate
	memories := map[string]Memory{}
	for check := 0; check < 3; check++ {
		d := Decide(full, memories[full.Current.Service])
		memories[full.Current.Service] = d.Memory
		if check < 2 && d.Action != AwaitFailures {
			t.Fatal(d)
		}
		if check == 2 && (d.Action != SelectCandidate || d.SelectionGuarantee != GuardedRead) {
			t.Fatal(d)
		}
		working := full
		working.Current.Service = "service-b"
		working.Current.Route = owned.selections[working.Current.Service]
		working.Current.Signal = Available
		working.Candidate = nil
		stable := Decide(working, memories[working.Current.Service])
		memories[working.Current.Service] = stable.Memory
		if stable.Action != KeepCurrent || stable.Memory.Failures != 0 {
			t.Fatal("failed service moved a working service", stable)
		}
	}
	// A proxy-only adapter owns no selection graph. The same policy observes
	// the supported scope but explicitly declines mutation even in automatic mode.
	type endpointSnapshot struct {
		connectionID, transportRevision string
		frontendLoaded                  bool
	}
	endpoint := endpointSnapshot{connectionID: "opaque-endpoint-42", transportRevision: "transport-revision-9"}
	proxyOnly := fullInput()
	// This adapter has a single client-owned endpoint rather than a route tree.
	// Neither its route token nor its transport revision needs the other
	// adapter's structure or naming conventions.
	proxyOnly.Current.Route = endpoint.connectionID
	proxyOnly.Current.Version = endpoint.transportRevision
	proxyOnly.Capabilities = Capabilities{Observe: true, ProbeScopes: []Scope{Frontend}}
	limited := Decide(proxyOnly, Memory{})
	if limited.Action != ObserveOnly || limited.Reason != "named_egress_unavailable" || limited.Memory.Failures != 0 || limited.SelectionGuarantee != NoSelection {
		t.Fatal(limited)
	}
	endpoint.frontendLoaded = true
	if endpoint.frontendLoaded {
		proxyOnly.Current.Signal = Available
	}
	if d := Decide(proxyOnly, Memory{}); d.Action != KeepCurrent || d.VerifiedScope != Frontend || d.SelectionGuarantee != NoSelection {
		t.Fatal(d)
	}
}

func TestManualAndObserveAlwaysPreventSelection(t *testing.T) {
	in := fullInput()
	candidate := in.Current
	candidate.Route = "route-new"
	candidate.Signal = Available
	in.Candidate = &candidate
	prior := Memory{Service: in.Current.Service, Route: in.Current.Route, Version: in.Current.Version, Failures: 2}
	in.Manual = true
	in.Capabilities = Capabilities{}
	held := Decide(in, prior)
	if held.Action != HoldManual || !held.Memory.ManualHeld || held.Memory.Failures != 2 {
		t.Fatal(held)
	}
	in = fullInput()
	resumed := Decide(in, held.Memory)
	if resumed.Action != AwaitFailures || resumed.Memory.Failures != 1 {
		t.Fatal("manual reentry retained old failures", resumed)
	}
	in.Mode = Observe
	in.Candidate = &candidate
	if d := Decide(in, prior); d.Action != ObserveOnly || d.Memory.Failures != 0 {
		t.Fatal(d)
	}
}

func TestUnknownAndIdentityChangesResetFailureHistory(t *testing.T) {
	for _, kind := range []string{"unknown", "route", "version", "service", "unbound"} {
		t.Run(kind, func(t *testing.T) {
			in := fullInput()
			prior := Memory{Service: in.Current.Service, Route: in.Current.Route, Version: in.Current.Version, Failures: 2}
			switch kind {
			case "unknown":
				in.Current.Signal = Unknown
			case "route":
				in.Current.Route = "another"
			case "version":
				in.Current.Version = "revision-two"
			case "service":
				in.Current.Service = "another"
			case "unbound":
				in.Current.EgressBound = false
			}
			d := Decide(in, prior)
			want := 1
			if kind == "unknown" || kind == "unbound" {
				want = 0
			}
			if d.Memory.Failures != want || d.Action == SelectCandidate {
				t.Fatal(d)
			}
		})
	}
}

func TestEligibilityAndPositiveCandidateEvidence(t *testing.T) {
	for _, kind := range []string{"cooldown", "budget", "clock", "missing", "negative", "unbound", "wrong-service", "wrong-version", "positive", "atomic"} {
		t.Run(kind, func(t *testing.T) {
			in := fullInput()
			prior := Memory{Service: in.Current.Service, Route: in.Current.Route, Version: in.Current.Version, Failures: 2}
			candidate := in.Current
			candidate.Route = "route-new"
			candidate.Signal = Available
			in.Candidate = &candidate
			want := SeekCandidate
			reason := ""
			switch kind {
			case "cooldown":
				prior.LastAttempt = in.Now - 1
				want = Hold
				reason = "cooldown"
			case "budget":
				in.RecentAttempts = 1
				want = Hold
				reason = "attempt_budget"
			case "clock":
				prior.LastAttempt = in.Now + 1
				want = Hold
				reason = "clock_unknown"
			case "missing":
				in.Candidate = nil
			case "negative":
				candidate.Signal = RepairableFailure
			case "unbound":
				candidate.EgressBound = false
			case "wrong-service":
				candidate.Service = "service-b"
			case "wrong-version":
				candidate.Version = "stale"
			case "positive":
				want = SelectCandidate
			case "atomic":
				want = SelectCandidate
				in.Capabilities.AtomicCompareAndSet = true
			}
			d := Decide(in, prior)
			if d.Action != want || (reason != "" && d.Reason != reason) {
				t.Fatal(d)
			}
			if kind == "atomic" && d.SelectionGuarantee != AtomicSelection {
				t.Fatal(d)
			}
		})
	}
}

func TestCapabilitiesAndScopeDoNotBecomeAuthorization(t *testing.T) {
	for _, kind := range []string{"observe", "named", "guard", "manual", "recovery", "scope", "account"} {
		t.Run(kind, func(t *testing.T) {
			in := fullInput()
			in.Rules.FailureChecks = 1
			switch kind {
			case "observe":
				in.Capabilities.Observe = false
			case "named":
				in.Capabilities.NamedEgressProbe = false
			case "guard":
				in.Capabilities.GuardedSelection = false
			case "manual":
				in.Capabilities.ManualHold = false
			case "recovery":
				in.Capabilities.RecoveryPersistence = false
			case "scope":
				in.RequiredScope = Account
			case "account":
				in.RequiredScope = Account
				in.Capabilities.ProbeScopes = []Scope{Account}
				in.Current.Scope = Account
				in.Current.Signal = Available
			}
			d := Decide(in, Memory{})
			if d.Action != ObserveOnly || d.Reason == "" || d.Memory.Failures != 0 {
				t.Fatal(d)
			}
		})
	}
	in := fullInput()
	in.RequiredScope = Account
	in.Current.Signal = Available
	if d := Decide(in, Memory{}); d.VerifiedScope != ScopeUnknown || d.Reason != "unsupported_scope" {
		t.Fatal("frontend proof became account proof", d)
	}
}
