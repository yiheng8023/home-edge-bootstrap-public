#!/bin/sh
# Validate the public compatibility policy without external access.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
case "$#" in
  0) ;;
  2) [ "$1" = "--repo" ] || { echo 'compatibility_policy_state=failed'; echo 'compatibility_policy_failure=unknown_argument'; exit 2; }; repo=$2 ;;
  *) echo 'compatibility_policy_state=failed'; echo 'compatibility_policy_failure=unexpected_arguments'; exit 2 ;;
esac

policy="$repo/config/compatibility-matrix.json"
[ -f "$policy" ] || { echo 'compatibility_policy_state=failed'; echo 'compatibility_policy_failure=missing_file'; exit 1; }

py=
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 &&
    "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then py=$candidate; break; fi
done
if [ -z "$py" ]; then echo 'compatibility_policy_state=failed'; echo 'compatibility_policy_failure=python3_required'; exit 1; fi

"$py" - "$policy" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    policy = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print("compatibility_policy_state=failed")
    print(f"compatibility_policy_failure=invalid_json:{type(exc).__name__}")
    raise SystemExit(1)

failures = []

if not isinstance(policy, dict):
    print("compatibility_policy_state=failed")
    print("compatibility_policy_failure=invalid_root_type")
    raise SystemExit(1)

def exact_keys(value, expected, label):
    if not isinstance(value, dict) or set(value) != set(expected):
        failures.append(f"invalid_property_set={label}")

root_keys = {
    "schema_version", "format", "authority_boundary", "certification_policy",
    "adapter_maturity_model", "capability_requirements", "support_levels",
    "declared_targets", "field_evidence",
}
exact_keys(policy, root_keys, "root")
if type(policy.get("schema_version")) is not int or policy.get("schema_version") != 1: failures.append("invalid_schema_version")
if type(policy.get("format")) is not str or policy.get("format") != "home-edge-public-compatibility/v1": failures.append("invalid_format")
if type(policy.get("authority_boundary")) is not str or "policy inputs, not observations" not in policy.get("authority_boundary", ""): failures.append("invalid_authority_boundary")
if type(policy.get("certification_policy")) is not str or "fixtures are not field certification" not in policy.get("certification_policy", ""): failures.append("missing_fixture_certification_boundary")
if type(policy.get("field_evidence")) is not list or policy.get("field_evidence") != []: failures.append("field_evidence_must_be_empty")

maturity = policy.get("adapter_maturity_model")
exact_keys(maturity, {"independent_from_target_support", "stages", "current_reference"}, "adapter_maturity_model")
if not isinstance(maturity, dict): maturity = {}
if type(maturity.get("independent_from_target_support")) is not bool or maturity.get("independent_from_target_support") is not True: failures.append("adapter_maturity_support_boundary_missing")
expected_stages = ["external-integration", "experimental-adapter", "community-maintained-adapter", "verified-adapter"]
if type(maturity.get("stages")) is not list or maturity.get("stages") != expected_stages or not all(type(item) is str for item in maturity.get("stages", [])): failures.append("invalid_adapter_maturity_stages")
reference = maturity.get("current_reference")
exact_keys(reference, {"id", "role", "assigned_stage", "claim_boundary"}, "adapter_maturity_model.current_reference")
expected_reference = {
    "id": "merlin", "role": "implemented-reference", "assigned_stage": None,
    "claim_boundary": "Reference status does not assign a verified maturity stage.",
}
if reference != expected_reference: failures.append("invalid_current_reference_boundary")

expected_requirements = [
    {"id": "host-guided-shell", "description": "Windows PowerShell 5.1+ or a POSIX sh host on macOS/Linux with SSH, archive tools, and Python 3 available as python3 or as python pointing to Python 3", "required_for": ["guided-flow", "local-verification"]},
    {"id": "official-asuswrt-merlin-router", "description": "ASUS gateway running official Asuswrt-Merlin with SSH, persistent /jffs storage, and required POSIX utilities", "required_for": ["router-bootstrap", "router-recovery"]},
    {"id": "shellcrash-mihomo-runtime", "description": "ShellCrash/ShellClash with a Mihomo-compatible runtime and a discoverable health or controller surface", "required_for": ["router-bootstrap", "router-recovery"]},
    {"id": "supported-runtime-architecture", "description": "A runtime payload and CPU architecture combination declared by the concrete offline release artifact", "required_for": ["fresh-offline-runtime-install"]},
    {"id": "independent-fallback", "description": "A separately managed soft-router or endpoint path for recovery access", "required_for": ["recommended-safe-apply"]},
]
requirements = policy.get("capability_requirements")
if type(requirements) is not list or requirements != expected_requirements: failures.append("invalid_capability_requirements")
else:
    for index, item in enumerate(requirements): exact_keys(item, {"id", "description", "required_for"}, f"capability_requirements[{index}]")

expected_levels = [
    {"id": "supported", "meaning": "All required capabilities and applicable evidence gates are satisfied for the evaluated target."},
    {"id": "supported_needs_manual", "meaning": "The target is suitable, but a named manual action must be completed before automation proceeds."},
    {"id": "accepted_modified", "meaning": "The operator explicitly accepts a compatible modified baseline and its provenance and support risk."},
    {"id": "unknown", "meaning": "Evidence is insufficient to determine one or more required target capabilities; do not apply."},
    {"id": "unsupported", "meaning": "A required capability is absent or conflicts with the documented boundary; do not apply."},
]
levels = policy.get("support_levels")
if type(levels) is not list or levels != expected_levels: failures.append("invalid_support_levels")
else:
    for index, item in enumerate(levels): exact_keys(item, {"id", "meaning"}, f"support_levels[{index}]")

expected_targets = [
    {
        "path": "router", "adapter_id": "merlin", "adapter_role": "implemented-reference",
        "platform": "ASUS gateway running official Asuswrt-Merlin",
        "runtime": "ShellCrash/ShellClash with a Mihomo-compatible runtime", "support_level": "unknown",
        "classification_basis": "No target-specific field evidence is published; run read-only target capability checks.",
    },
    {
        "path": "soft-router-or-endpoint-fallback", "adapter_id": None, "adapter_role": "independent-fallback",
        "platform": "independently managed soft router or endpoint", "runtime": "managed outside this adapter framework",
        "support_level": "unknown",
        "classification_basis": "The fallback is independently managed and does not provide evidence for the router path.",
    },
]
targets = policy.get("declared_targets")
if type(targets) is not list or targets != expected_targets: failures.append("invalid_declared_targets")
else:
    level_ids = {item["id"] for item in expected_levels}
    for index, item in enumerate(targets):
        exact_keys(item, {"path", "adapter_id", "adapter_role", "platform", "runtime", "support_level", "classification_basis"}, f"declared_targets[{index}]")
        if item["support_level"] not in level_ids: failures.append(f"unknown_target_support_level={item['path']}")

if failures:
    print("compatibility_policy_state=failed")
    for failure in failures: print(f"compatibility_policy_failure={failure}")
    raise SystemExit(1)

print("compatibility_policy_state=ready")
print("compatibility_field_evidence_count=0")
print("compatibility_capability_requirement_count=5")
print("compatibility_support_level_count=5")
print("compatibility_declared_target_count=2")
PY
