#!/bin/sh
# Offline failure-propagation tests for router status helpers.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_parent=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${tmp_parent%/}/home-edge-router-status-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/bin"

fail() {
  echo "router_status_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

for router_source in \
  "$repo/scripts/migrate-router-state.sh" \
  "$repo/scripts/reconcile-self-heal-registration.sh" \
  "$repo/scripts/subscription-runtime-evidence.sh" \
  "$repo/scripts/update-sub.sh" \
  "$repo/scripts/decommission-router-state.sh" \
  "$repo/scripts/verify-deployment-provenance.sh" \
  "$repo/scripts/check-router-status.sh" \
  "$repo/scripts/check-router-status.ps1"
do
  ! grep -Fq 'command -v' "$router_source" ||
    fail "$(basename "$router_source") depends on command -v, which is unavailable on the supported Merlin shell"
done

secure_temp_helper="$repo/scripts/home-edge-secure-temp.sh"
[ -s "$secure_temp_helper" ] || fail "project secure temporary-path helper is missing"
! grep -Fq 'mktemp' "$secure_temp_helper" ||
  fail "project secure temporary-path helper must not delegate to unavailable mktemp"
. "$secure_temp_helper"
secure_file=$(home_edge_secure_temp "$tmp/secure-file.XXXXXX") ||
  fail "project secure temporary-path helper could not allocate a file"
[ -f "$secure_file" ] && [ ! -L "$secure_file" ] || fail "secure temporary file was not created safely"
secure_dir=$(home_edge_secure_temp -d "$tmp/secure-directory.XXXXXX") ||
  fail "project secure temporary-path helper could not allocate a directory"
[ -d "$secure_dir" ] && [ ! -L "$secure_dir" ] || fail "secure temporary directory was not created safely"
file_mode=$(stat -c '%a' "$secure_file" 2>/dev/null || stat -f '%Lp' "$secure_file")
dir_mode=$(stat -c '%a' "$secure_dir" 2>/dev/null || stat -f '%Lp' "$secure_dir")
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*) ;;
  *)
    [ "$file_mode" = 600 ] || fail "secure temporary file mode is $file_mode, expected 600"
    [ "$dir_mode" = 700 ] || fail "secure temporary directory mode is $dir_mode, expected 700"
    ;;
esac
grep -Fq 'umask 077' "$secure_temp_helper" || fail "project secure temporary-path helper omits restrictive creation mode"
grep -Fq 'which base64' "$secure_temp_helper" ||
  fail "project secure temporary-path helper lacks the non-OpenSSL random fallback"
if home_edge_secure_temp "$tmp/missing-template-suffix" >/dev/null 2>&1; then
  fail "project secure temporary-path helper accepted a template without XXXXXX"
fi

for persistent_router_source in \
  "$repo/scripts/migrate-router-state.sh" \
  "$repo/scripts/self-heal.sh" \
  "$repo/scripts/update-sub.sh" \
  "$repo/scripts/subscription-runtime-evidence.sh" \
  "$repo/scripts/enable-live-self-heal-router.sh"
do
  ! grep -Eq '(^|[^[:alnum:]_])mktemp([[:space:]]|$)' "$persistent_router_source" ||
    fail "$(basename "$persistent_router_source") depends on unavailable mktemp"
  grep -Fq 'home_edge_secure_temp' "$persistent_router_source" ||
    fail "$(basename "$persistent_router_source") does not use the project secure temporary-path helper"
done

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
for source in "$repo/scripts/check-router-status.sh" "$repo/scripts/audit-router-baseline.sh"; do
  grep -Fq 'stable_state_root=/jffs/home-edge-bootstrap-state' "$source" || fail "$(basename "$source") omits the stable state root"
  for field in stable_state_schema stable_subscription_state stable_policy_state compatibility_bridge_state; do
    grep -Fq "$field" "$source" || fail "$(basename "$source") omits safe state classification: $field"
  done
  ! grep -Fq 'subscription_file_bytes' "$source" || fail "$(basename "$source") reports secret-bearing subscription size"
  ! grep -Fq 'subscription_cache_bytes' "$source" || fail "$(basename "$source") reports secret-bearing cache size"
done
! grep -Fq 'emit_policy()' "$repo/scripts/check-router-status.sh" || fail "shell status helper still emits policy content"
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
grep -q 'CONTROLLER_SECRET.local' "$tmp/remote-script" || fail "status does not discover the stable controller secret file"
grep -q 'CLASH_SECRET_FILE=' "$tmp/remote-script" || fail "status does not pass controller authentication by file"
grep -q 'route_evidence_identity_state' "$tmp/remote-script" || fail "status does not redact live route identity"
! grep -Fq 'route_evidence_identity=$(route_value route_identity)' "$tmp/remote-script" ||
  fail "status still emits the live route identity"
grep -q '^stable_state_root=/jffs/home-edge-bootstrap-state$' "$tmp/remote-script" || fail "status remote script omits stable state root"
grep -q 'stable_state_schema' "$tmp/remote-script" || fail "status remote script omits stable state schema classification"
grep -q 'compatibility_bridge_state' "$tmp/remote-script" || fail "status remote script omits compatibility bridge classification"
if grep -q 'SUBSCRIPTION.local\|private-marker' "$tmp/success"; then fail "status leaked sensitive provenance content"; fi

cat >"$tmp/failing-self-heal" <<'EOF'
#!/bin/sh
exit 23
EOF
chmod 755 "$tmp/failing-self-heal"
cat >"$tmp/bin/curl" <<'EOF'
#!/bin/sh
for arg in "$@"; do
  [ "$arg" != "-w" ] || writeout=1
done
[ "${writeout:-0}" = 0 ] || printf '000'
exit 7
EOF
chmod 755 "$tmp/bin/curl"
HOME_EDGE_STATUS_SELF_HEAL_SCRIPT="$tmp/failing-self-heal" PATH="$tmp/bin:$PATH" \
  sh "$tmp/remote-script" >"$tmp/observer-failure.out" 2>"$tmp/observer-failure.err" ||
  fail "status remote script should classify an observer failure without aborting"
grep -q '^controller_observation_state=blocked$' "$tmp/observer-failure.out" ||
  fail "observer failure did not produce a blocked controller state"
grep -q '^route_evidence_verification_state=unavailable$' "$tmp/observer-failure.out" ||
  fail "verify failure did not produce an unavailable route state"
grep -q '^route_evidence_classification=unknown$' "$tmp/observer-failure.out" ||
  fail "verify failure did not preserve an explicit unknown classification"
grep -q '^route_evidence_identity_state=missing$' "$tmp/observer-failure.out" ||
  fail "verify failure did not preserve a redacted missing route identity state"

echo "router_status_fixture_tests=ok"
