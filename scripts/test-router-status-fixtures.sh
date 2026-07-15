#!/bin/sh
# Offline failure-propagation tests for router status helpers.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-router-status-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin"

fail() {
  echo "router_status_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

cat >"$tmp/bin/ssh" <<'EOF'
#!/bin/sh
cat >"${ROUTER_STATUS_FAKE_SCRIPT:-/dev/null}"
[ "${ROUTER_STATUS_FAKE_SUCCESS:-0}" != 1 ] || {
  echo 'deployment_provenance_state=match'
  echo 'deployment_source_commit=0123456789012345678901234567890123456789'
  echo 'deployment_source_version=unversioned'
  echo 'deployment_content_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
  exit 0
}
exit 42
EOF
chmod 755 "$tmp/bin/ssh"

set +e
PATH="$tmp/bin:$PATH" NO_LOG=1 LOG_PATH="$tmp/status.log" KNOWN_HOSTS_FILE="$tmp/known_hosts" \
  sh "$repo/scripts/check-router-status.sh" user@router >"$tmp/output" 2>&1
status=$?
set -e

[ "$status" -eq 42 ] || { cat "$tmp/output" >&2; fail "shell status helper should propagate SSH exit 42, got $status"; }
[ ! -e "$tmp/status.log" ] || fail "NO_LOG shell status helper wrote a log"
grep -q '<configured>' "$repo/scripts/check-router-status.sh" || fail "shell status helper lacks sensitive-value masking"
if grep -q '/tmp/home-edge-check-router-status.sh' "$repo/scripts/check-router-status.sh"; then
  fail "shell status helper still uses a fixed remote temp script"
fi

ROUTER_STATUS_FAKE_SUCCESS=1 ROUTER_STATUS_FAKE_SCRIPT="$tmp/remote-script" PATH="$tmp/bin:$PATH" NO_LOG=1 LOG_PATH="$tmp/status.log" KNOWN_HOSTS_FILE="$tmp/known_hosts" \
  sh "$repo/scripts/check-router-status.sh" user@router >"$tmp/success" 2>&1
grep -q '^deployment_provenance_state=match$' "$tmp/success" || fail "provenance state missing from status"
grep -q '^deployment_source_commit=[0-9a-f]\{40\}$' "$tmp/success" || fail "safe source commit missing from status"
grep -q 'verify-deployment-provenance.sh' "$tmp/remote-script" || fail "status does not run the read-only provenance verifier"
grep -q 'HOME_EDGE_EXPECTED_SOURCE_' "$tmp/remote-script" || fail "status does not bind expected local source identity"
grep -q 'runtime_active_config_path' "$tmp/remote-script" || fail "status does not bind subscription evidence to the runtime-observed config path"
grep -q 'runtime_process_identity' "$tmp/remote-script" || fail "status does not bind subscription evidence to the current runtime process identity"
grep -q 'SUBSCRIPTION_RUNTIME_EVIDENCE_MAX_AGE_SEC' "$tmp/remote-script" || fail "status does not enforce bounded subscription evidence freshness"
grep -q 'route_evidence_probe_id' "$tmp/remote-script" || fail "status does not emit fresh machine-readable route evidence"
grep -q 'cache_apply_path_alias' "$tmp/remote-script" || fail "status does not reject cache/apply path aliasing"
grep -q 'controller_dashboard_config_state:-unknown' "$tmp/remote-script" || fail "status does not preserve unknown dashboard discovery"
if grep -q 'SUBSCRIPTION.local\|private-marker' "$tmp/success"; then fail "status leaked sensitive provenance content"; fi

echo "router_status_fixture_tests=ok"
