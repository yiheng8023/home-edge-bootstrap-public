// Package healthpolicy decides whether service observations justify repair.
// It is pure: callers provide facts, time, capabilities and previous memory;
// adapters retain all I/O, ownership checks and execution responsibility.
package healthpolicy

type Mode string

const (
	Observe   Mode = "observe"
	Automatic Mode = "auto"
)

type Signal string

const (
	Unknown           Signal = "unknown"
	Available         Signal = "available"
	RepairableFailure Signal = "repairable_failure"
)

// Scope is exact, not a hierarchy. Frontend evidence does not establish account
// authorization, and account evidence need not prove an interactive frontend.
type Scope string

const (
	ScopeUnknown Scope = "unknown"
	Frontend     Scope = "frontend"
	Account      Scope = "account"
)

type Observation struct {
	Service         string
	Route           string
	Version         string
	Signal          Signal
	Scope           Scope
	EgressBound     bool
	AccountVerified bool
}

type Capabilities struct {
	Observe             bool
	NamedEgressProbe    bool
	GuardedSelection    bool
	ManualHold          bool
	RecoveryPersistence bool
	// This stronger guarantee must be declared separately. A guarded read
	// followed by a write must never claim compare-and-set semantics.
	AtomicCompareAndSet bool
	ProbeScopes         []Scope
}

type Rules struct {
	FailureChecks   int
	CooldownSeconds int64
	AttemptLimit    int
	// Include compensating writes in the reservation, not just the first write.
	WriteReservation int
}

type Memory struct {
	Service     string
	Route       string
	Version     string
	Failures    int
	LastAttempt int64
	ManualHeld  bool
}

type Input struct {
	Mode           Mode
	Manual         bool
	Current        Observation
	Candidate      *Observation
	RequiredScope  Scope
	Capabilities   Capabilities
	Rules          Rules
	Now            int64
	RecentAttempts int
}

type Action string

const (
	ObserveOnly     Action = "observe"
	HoldManual      Action = "hold_manual"
	KeepCurrent     Action = "keep_current"
	AwaitFailures   Action = "await_failures"
	SeekCandidate   Action = "seek_candidate"
	SelectCandidate Action = "select_candidate"
	Hold            Action = "hold"
)

type Guarantee string

const (
	NoSelection     Guarantee = "none"
	GuardedRead     Guarantee = "guarded_read"
	AtomicSelection Guarantee = "atomic_compare_and_set"
)

type Decision struct {
	Action             Action
	Reason             string
	Memory             Memory
	VerifiedScope      Scope
	SelectionGuarantee Guarantee
}

func supports(c Capabilities, scope Scope) bool {
	if scope != Frontend && scope != Account {
		return false
	}
	for _, supported := range c.ProbeScopes {
		if supported == scope {
			return true
		}
	}
	return false
}

func proofReason(o Observation, scope Scope) string {
	if !o.EgressBound {
		return "egress_unbound"
	}
	if o.Scope != scope {
		return "scope_unverified"
	}
	if scope == Account && !o.AccountVerified {
		return "account_unverified"
	}
	return ""
}

// RepairLimitation describes missing execution capability, never authorization
// to repair. Evidence, manual intent, policy limits and ownership still apply.
func (c Capabilities) RepairLimitation(scope Scope) string {
	if !c.Observe {
		return "observation_unavailable"
	}
	if !supports(c, scope) {
		return "unsupported_scope"
	}
	for _, capability := range []struct {
		ready  bool
		reason string
	}{
		{c.NamedEgressProbe, "named_egress_unavailable"},
		{c.GuardedSelection, "guarded_selection_unavailable"},
		{c.ManualHold, "manual_hold_unavailable"},
		{c.RecoveryPersistence, "recovery_persistence_unavailable"},
	} {
		if !capability.ready {
			return capability.reason
		}
	}
	return ""
}

// Decide evaluates one coherent observation against unchanged previous memory.
// The caller may evaluate several candidate facts against that same previous
// memory; it must not feed a decision's next memory back as another observation.
// Selection is permission to plan an effect, not proof that an effect occurred.
func Decide(in Input, previous Memory) Decision {
	next := previous
	decision := Decision{Action: ObserveOnly, Reason: "signal_unknown", Memory: next, VerifiedScope: ScopeUnknown, SelectionGuarantee: NoSelection}
	finish := func(action Action, reason string) Decision {
		decision.Action = action
		decision.Reason = reason
		decision.Memory = next
		return decision
	}
	// Manual intent wins even when the adapter cannot probe or mutate anything.
	if in.Manual {
		next.ManualHeld = true
		return finish(HoldManual, "manual_pinned")
	}
	if previous.Service != in.Current.Service || previous.Route != in.Current.Route || previous.Version != in.Current.Version || previous.ManualHeld {
		next.Failures = 0
	}
	next.Service, next.Route, next.Version = in.Current.Service, in.Current.Route, in.Current.Version
	next.ManualHeld = false
	if next.Failures < 0 {
		next.Failures = 0
		return finish(ObserveOnly, "invalid_memory")
	}
	if !in.Capabilities.Observe {
		next.Failures = 0
		return finish(ObserveOnly, "observation_unavailable")
	}
	if !supports(in.Capabilities, in.RequiredScope) {
		next.Failures = 0
		return finish(ObserveOnly, "unsupported_scope")
	}
	if in.Current.Service == "" || in.Current.Route == "" || in.Current.Version == "" {
		next.Failures = 0
		return finish(ObserveOnly, "identity_unbound")
	}
	if reason := proofReason(in.Current, in.RequiredScope); reason != "" {
		next.Failures = 0
		return finish(ObserveOnly, reason)
	}
	if in.Current.Signal == Available {
		next.Failures = 0
		decision.VerifiedScope = in.RequiredScope
		return finish(KeepCurrent, "current_healthy")
	}
	if in.Current.Signal != RepairableFailure {
		next.Failures = 0
		return finish(ObserveOnly, "signal_unknown")
	}
	if in.Mode == Observe {
		next.Failures = 0
		return finish(ObserveOnly, "automatic_disabled")
	}
	if in.Mode != Automatic {
		next.Failures = 0
		return finish(ObserveOnly, "mode_unknown")
	}
	if reason := in.Capabilities.RepairLimitation(in.RequiredScope); reason != "" {
		next.Failures = 0
		return finish(ObserveOnly, reason)
	}
	if in.Rules.FailureChecks < 1 || in.Rules.CooldownSeconds < 0 || in.Rules.AttemptLimit < 1 || in.Rules.WriteReservation < 1 || in.RecentAttempts < 0 {
		return finish(ObserveOnly, "invalid_rules")
	}
	if next.Failures < in.Rules.FailureChecks {
		next.Failures++
	}
	if next.Failures < in.Rules.FailureChecks {
		return finish(AwaitFailures, "failure_pending")
	}
	if in.Now < 0 || next.LastAttempt < 0 || next.LastAttempt > in.Now {
		return finish(Hold, "clock_unknown")
	}
	if next.LastAttempt > 0 && in.Now-next.LastAttempt < in.Rules.CooldownSeconds {
		return finish(Hold, "cooldown")
	}
	if in.Rules.WriteReservation > in.Rules.AttemptLimit || in.RecentAttempts > in.Rules.AttemptLimit-in.Rules.WriteReservation {
		return finish(Hold, "attempt_budget")
	}
	if in.Candidate == nil {
		return finish(SeekCandidate, "candidate_needed")
	}
	candidate := *in.Candidate
	if candidate.Service != in.Current.Service || candidate.Version != in.Current.Version || candidate.Route == "" || candidate.Route == in.Current.Route {
		return finish(SeekCandidate, "candidate_identity_unbound")
	}
	if reason := proofReason(candidate, in.RequiredScope); reason != "" {
		return finish(SeekCandidate, reason)
	}
	if candidate.Signal != Available {
		return finish(SeekCandidate, "candidate_not_positive")
	}
	decision.SelectionGuarantee = GuardedRead
	if in.Capabilities.AtomicCompareAndSet {
		decision.SelectionGuarantee = AtomicSelection
	}
	return finish(SelectCandidate, "candidate_positive")
}
