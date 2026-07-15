#!/bin/sh
# Offline behavior tests for update-sub.sh using fake provider responses.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_root=$(mktemp -d "/tmp/home-edge-sub-test.XXXXXX") || exit 1
export SUBSCRIPTION_LOCK_DIR="$tmp_root/write.lock"
case "$tmp_root" in *//*) echo "subscription_fixture_tests=failed" >&2; echo "temporary root was not normalized: $tmp_root" >&2; exit 1 ;; esac
fake_bin="$tmp_root/bin"
mkdir -p "$fake_bin"

cleanup() {
  case "$tmp_root" in /tmp/home-edge-sub-test.*) rm -rf "$tmp_root" ;; esac
}
trap cleanup EXIT HUP INT TERM

cat >"$fake_bin/curl" <<'EOF'
#!/bin/sh
out=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      shift
      out="${1:-}"
      ;;
    -x|--proxy)
      shift
      ;;
    http://*|https://*)
      url="$1"
      ;;
  esac
  shift || break
done

[ -n "$out" ] || exit 2
case "${SUBSCRIPTION_FIXTURE:-yaml}" in
  raw)
    printf '%s\n' 'dm1lc3M6Ly9leGFtcGxlLXJhdy1zdWJzY3JpcHRpb24tdGhhdC1pcy1sb25nLWVub3VnaC10by1iZS1yZWplY3RlZC1ieS10aGUtdmFsaWRhdG9yCg==' >"$out"
    ;;
  html)
    printf '%s\n' '<html><body>access denied</body></html>' >"$out"
    ;;
  *)
    {
      printf 'mixed-port: 7890\n'
      printf 'proxies:\n'
      printf '  - name: United States - New York\n'
      printf '    type: http\n'
      printf 'rules:\n'
      printf '  - MATCH,United States - New York\n'
      printf '# source=%s\n' "$url"
    } >"$out"
    ;;
esac
EOF
chmod 755 "$fake_bin/curl"

cat >"$fake_bin/jq" <<'EOF'
#!/bin/sh
filter=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -*)
      ;;
    *)
      filter="$1"
      ;;
  esac
  shift || break
done
input=$(cat)
case "$filter" in
  *@uri*)
    printf '%s' "$input" | sed 's/%/%25/g;s/ /%20/g;s/:/%3A/g;s#/#%2F#g;s/?/%3F/g;s/&/%26/g;s/=/%3D/g'
    ;;
  *)
    printf '%s' "$input"
    ;;
esac
EOF
chmod 755 "$fake_bin/jq"

cat >"$fake_bin/mihomo" <<'EOF'
#!/bin/sh
[ "${SUBSCRIPTION_SEMANTIC_FIXTURE:-valid}" != "invalid" ]
EOF
chmod 755 "$fake_bin/mihomo"
export SUBSCRIPTION_MIHOMO_BIN="$fake_bin/mihomo"

cat >"$fake_bin/reload-once-fail" <<'EOF'
#!/bin/sh
state="$1"
if [ ! -e "$state" ]; then
  : >"$state"
  exit 1
fi
exit 0
EOF
chmod 755 "$fake_bin/reload-once-fail"

fail() {
  echo "subscription_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

write_url() {
  file="$1"
  printf '%s\n' 'https://provider.example/subscription-token-redacted' >"$file"
}

run_update() {
  name="$1"
  shift
  case_dir="$tmp_root/$name"
  mkdir -p "$case_dir/cache" "$case_dir/backups"
  sub_file="$case_dir/SUBSCRIPTION.local"
  cache_file="$case_dir/cache/subscription.yaml"
  backup_dir="$case_dir/backups"
  log_file="$case_dir/update-sub.log"
  write_url "$sub_file"

  PATH="$fake_bin:$PATH" \
  SUBSCRIPTION_FILE="$sub_file" \
  SUBSCRIPTION_CACHE="$cache_file" \
  SUBSCRIPTION_BACKUP_DIR="$backup_dir" \
  SUBSCRIPTION_LOG="$log_file" \
  "$@" sh "$repo/scripts/update-sub.sh"
}

output=$(run_update direct_yaml env SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_DRY_RUN=1)
printf '%s\n' "$output" | grep -q 'subscription_dry_run=ok' || fail "direct YAML dry-run did not pass"
printf '%s\n' "$output" | grep -q 'subscription_cache=unchanged' || fail "dry-run should not update cache"
printf '%s\n' "$output" | grep -q 'provider.example' && fail "subscription URL leaked to stdout"

if run_update invalid_semantics env SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_SEMANTIC_FIXTURE=invalid SUBSCRIPTION_DRY_RUN=1 >"$tmp_root/invalid-semantics.out" 2>"$tmp_root/invalid-semantics.err"; then
  fail "Mihomo semantic rejection should fail the refresh"
fi
grep -q 'Mihomo rejected' "$tmp_root/invalid-semantics.err" || fail "semantic rejection message missing"

if run_update invalid_bool env SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_DRY_RUN=true >"$tmp_root/invalid-bool.out" 2>"$tmp_root/invalid-bool.err"; then
  fail "invalid SUBSCRIPTION_DRY_RUN must fail closed"
fi
grep -q 'invalid boolean' "$tmp_root/invalid-bool.err" || fail "invalid boolean rejection message missing"

if run_update raw_reject env SUBSCRIPTION_FIXTURE=raw SUBSCRIPTION_DRY_RUN=1 >/tmp/home-edge-sub-raw.out 2>/tmp/home-edge-sub-raw.err; then
  fail "raw/base64 subscription should be rejected"
fi
grep -q 'raw/base64 provider feed' /tmp/home-edge-sub-raw.err || fail "raw rejection message missing"

if run_update remote_converter_block env SUBSCRIPTION_DRY_RUN=1 SUBSCRIPTION_CONVERTER_BASE_URL=https://converter.example/sub >/tmp/home-edge-sub-remote.out 2>/tmp/home-edge-sub-remote.err; then
  fail "remote converter should be blocked by default"
fi
grep -q 'remote subscription converter blocked' /tmp/home-edge-sub-remote.err || fail "remote converter block message missing"

output=$(run_update local_converter env SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_DRY_RUN=1 SUBSCRIPTION_CONVERTER_BASE_URL=http://192.168.50.2:25500/sub SUBSCRIPTION_CONVERTER_TARGET=clash)
printf '%s\n' "$output" | grep -q 'subscription_dry_run=ok' || fail "local converter dry-run did not pass"

for deceptive_converter in \
  http://127.evil.example/sub \
  http://localhost.evil.example/sub \
  http://192.168.evil.example/sub \
  http://10.evil.example/sub
do
  if run_update deceptive_converter env SUBSCRIPTION_DRY_RUN=1 SUBSCRIPTION_CONVERTER_BASE_URL="$deceptive_converter" >/tmp/home-edge-sub-deceptive.out 2>/tmp/home-edge-sub-deceptive.err; then
    fail "deceptive private-looking converter host should be blocked: $deceptive_converter"
  fi
  grep -q 'remote subscription converter blocked' /tmp/home-edge-sub-deceptive.err || fail "deceptive converter block message missing"
done

output=$(run_update explicit_tool_paths env SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_DRY_RUN=1 CURL_BIN="$fake_bin/curl" JQ_BIN="$fake_bin/jq")
printf '%s\n' "$output" | grep -q 'subscription_dry_run=ok' || fail "explicit CURL_BIN/JQ_BIN dry-run did not pass"

output=$(run_update fetch_proxy env SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_DRY_RUN=1 SUBSCRIPTION_FETCH_PROXY=http://127.0.0.1:7890)
printf '%s\n' "$output" | grep -q 'subscription_dry_run=ok' || fail "fetch proxy dry-run did not pass"
printf '%s\n' "$output" | grep -q 'provider.example' && fail "subscription URL leaked to stdout with fetch proxy"

apply_dir="$tmp_root/apply"
mkdir -p "$apply_dir/cache" "$apply_dir/backups"
write_url "$apply_dir/SUBSCRIPTION.local"
printf 'mixed-port: 1\n' >"$apply_dir/cache/subscription.yaml"
PATH="$fake_bin:$PATH" \
SUBSCRIPTION_FIXTURE=yaml \
SUBSCRIPTION_FILE="$apply_dir/SUBSCRIPTION.local" \
SUBSCRIPTION_CACHE="$apply_dir/cache/subscription.yaml" \
SUBSCRIPTION_BACKUP_DIR="$apply_dir/backups" \
SUBSCRIPTION_LOG="$apply_dir/update-sub.log" \
SUBSCRIPTION_DRY_RUN=0 \
sh "$repo/scripts/update-sub.sh" >/tmp/home-edge-sub-apply.out
grep -q 'subscription_cache=updated' /tmp/home-edge-sub-apply.out || fail "apply did not update cache"
grep -q 'United States - New York' "$apply_dir/cache/subscription.yaml" || fail "cache does not contain new YAML"
ls "$apply_dir"/backups/subscription.*.yaml >/dev/null 2>&1 || fail "old cache backup missing"

if [ -L /tmp ] || [ "${HOME_EDGE_FIXTURE_TMP_SYMLINK:-0}" = 1 ]; then
  # The router contract rejects a symlinked /tmp, and this fixture must not
  # substitute a host /jffs path. Dedicated boundary fixtures cover rejection.
  echo "subscription_live_apply_fixtures=skipped_platform_tmp_symlink"
else
live_dir="$tmp_root/live"
mkdir -p "$live_dir/cache" "$live_dir/backups"
write_url "$live_dir/SUBSCRIPTION.local"
printf 'mixed-port: 1\nold-live: true\n' >"$live_dir/live.yaml"
runtime_evidence="$live_dir/runtime.evidence"
runtime_evidence_helper="$repo/scripts/subscription-runtime-evidence.sh"
PATH="$fake_bin:$PATH" \
SUBSCRIPTION_FIXTURE=yaml \
SUBSCRIPTION_FILE="$live_dir/SUBSCRIPTION.local" \
SUBSCRIPTION_CACHE="$live_dir/cache/subscription.yaml" \
SUBSCRIPTION_BACKUP_DIR="$live_dir/backups" \
SUBSCRIPTION_LOG="$live_dir/update-sub.log" \
SUBSCRIPTION_DRY_RUN=0 \
SUBSCRIPTION_APPLY_PATH="$live_dir/live.yaml" \
SUBSCRIPTION_RUNTIME_EVIDENCE="$runtime_evidence" \
SUBSCRIPTION_RUNTIME_EVIDENCE_HELPER="$runtime_evidence_helper" \
SUBSCRIPTION_RUNTIME_PROCESS_IDENTITY='mihomo:41:9000' \
SUBSCRIPTION_RUNTIME_PROCESS_START_EPOCH=1 \
SUBSCRIPTION_APPLY_ROOT="$live_dir" \
SUBSCRIPTION_RELOAD_CMD=true \
sh "$repo/scripts/update-sub.sh" >/tmp/home-edge-sub-live.out
grep -q 'subscription_apply=updated' /tmp/home-edge-sub-live.out || fail "live apply did not report update"
grep -q 'subscription_reload=ok' /tmp/home-edge-sub-live.out || fail "live apply did not run reload"
grep -q 'United States - New York' "$live_dir/live.yaml" || fail "live apply path does not contain new YAML"
grep -q '^runtime_subscription_evidence_state=reload_succeeded$' "$runtime_evidence" || fail "fresh reload evidence state missing"
grep -Fq "runtime_subscription_apply_path=$live_dir/live.yaml" "$runtime_evidence" || fail "fresh reload evidence did not bind apply path"
grep -Eq '^runtime_subscription_cache_sha256=[0-9a-f]{64}$' "$runtime_evidence" || fail "fresh reload evidence did not bind cache digest"

PATH="$fake_bin:$PATH" SUBSCRIPTION_FIXTURE=yaml SUBSCRIPTION_FILE="$live_dir/SUBSCRIPTION.local" \
SUBSCRIPTION_CACHE="$live_dir/cache/subscription.yaml" SUBSCRIPTION_BACKUP_DIR="$live_dir/backups" \
SUBSCRIPTION_LOG="$live_dir/update-sub.log" SUBSCRIPTION_DRY_RUN=0 \
SUBSCRIPTION_APPLY_PATH="$live_dir/live.yaml" SUBSCRIPTION_RUNTIME_EVIDENCE="$runtime_evidence" \
SUBSCRIPTION_RUNTIME_EVIDENCE_HELPER="$runtime_evidence_helper" \
SUBSCRIPTION_APPLY_ROOT="$live_dir" SUBSCRIPTION_RELOAD_CMD= sh "$repo/scripts/update-sub.sh" >/dev/null
[ ! -e "$runtime_evidence" ] || fail "apply without fresh reload retained stale runtime evidence"

alias_dir="$tmp_root/alias"
mkdir -p "$alias_dir/backups"
write_url "$alias_dir/SUBSCRIPTION.local"
if SUBSCRIPTION_FILE="$alias_dir/SUBSCRIPTION.local" SUBSCRIPTION_CACHE="$alias_dir/subscription.yaml" SUBSCRIPTION_BACKUP_DIR="$alias_dir/backups" SUBSCRIPTION_LOG="$alias_dir/update-sub.log" SUBSCRIPTION_DRY_RUN=0 SUBSCRIPTION_APPLY_PATH="$alias_dir/subscription.yaml" SUBSCRIPTION_APPLY_ROOT="$alias_dir" SUBSCRIPTION_RUNTIME_EVIDENCE="$runtime_evidence" SUBSCRIPTION_RUNTIME_EVIDENCE_HELPER="$runtime_evidence_helper" SUBSCRIPTION_RELOAD_CMD=true PATH="$fake_bin:$PATH" sh "$repo/scripts/update-sub.sh" >/dev/null 2>&1; then
  fail "cache-equals-apply-path should be rejected"
fi
ls "$live_dir"/backups/live.*.yaml >/dev/null 2>&1 || fail "live config backup missing"

rollback_dir="$tmp_root/live-rollback"
mkdir -p "$rollback_dir/cache" "$rollback_dir/backups"
write_url "$rollback_dir/SUBSCRIPTION.local"
printf 'mixed-port: 1\nold-live: true\n' >"$rollback_dir/live.yaml"
if PATH="$fake_bin:$PATH" \
  SUBSCRIPTION_FIXTURE=yaml \
  SUBSCRIPTION_FILE="$rollback_dir/SUBSCRIPTION.local" \
  SUBSCRIPTION_CACHE="$rollback_dir/cache/subscription.yaml" \
  SUBSCRIPTION_BACKUP_DIR="$rollback_dir/backups" \
  SUBSCRIPTION_LOG="$rollback_dir/update-sub.log" \
  SUBSCRIPTION_DRY_RUN=0 \
  SUBSCRIPTION_APPLY_PATH="$rollback_dir/live.yaml" \
  SUBSCRIPTION_APPLY_ROOT="$rollback_dir" \
  SUBSCRIPTION_RUNTIME_EVIDENCE="$runtime_evidence" \
  SUBSCRIPTION_RUNTIME_EVIDENCE_HELPER="$runtime_evidence_helper" \
  SUBSCRIPTION_RELOAD_CMD="$fake_bin/reload-once-fail $rollback_dir/reload.state" \
  sh "$repo/scripts/update-sub.sh" >/tmp/home-edge-sub-rollback.out 2>/tmp/home-edge-sub-rollback.err; then
  fail "reload failure should fail the update"
fi
grep -q 'subscription_apply=restored_after_reload_failure' /tmp/home-edge-sub-rollback.out || { cat /tmp/home-edge-sub-rollback.out /tmp/home-edge-sub-rollback.err >&2; fail "reload failure did not report restore"; }
grep -q 'subscription_rollback_reload=ok' /tmp/home-edge-sub-rollback.out || { cat /tmp/home-edge-sub-rollback.out /tmp/home-edge-sub-rollback.err >&2; fail "restored live state was not reloaded"; }
grep -q 'prior live state restored' /tmp/home-edge-sub-rollback.err || { cat /tmp/home-edge-sub-rollback.out /tmp/home-edge-sub-rollback.err >&2; fail "reload failure message missing"; }
grep -q 'old-live: true' "$rollback_dir/live.yaml" || fail "live config was not restored after reload failure"

new_live_dir="$tmp_root/live-rollback-new-file"
mkdir -p "$new_live_dir/cache" "$new_live_dir/backups"
write_url "$new_live_dir/SUBSCRIPTION.local"
if PATH="$fake_bin:$PATH" \
  SUBSCRIPTION_FIXTURE=yaml \
  SUBSCRIPTION_FILE="$new_live_dir/SUBSCRIPTION.local" \
  SUBSCRIPTION_CACHE="$new_live_dir/cache/subscription.yaml" \
  SUBSCRIPTION_BACKUP_DIR="$new_live_dir/backups" \
  SUBSCRIPTION_LOG="$new_live_dir/update-sub.log" \
  SUBSCRIPTION_DRY_RUN=0 \
  SUBSCRIPTION_APPLY_PATH="$new_live_dir/live.yaml" \
  SUBSCRIPTION_APPLY_ROOT="$new_live_dir" \
  SUBSCRIPTION_RUNTIME_EVIDENCE="$runtime_evidence" \
  SUBSCRIPTION_RUNTIME_EVIDENCE_HELPER="$runtime_evidence_helper" \
  SUBSCRIPTION_RELOAD_CMD="$fake_bin/reload-once-fail $new_live_dir/reload.state" \
  sh "$repo/scripts/update-sub.sh" >/tmp/home-edge-sub-rollback-new.out 2>/tmp/home-edge-sub-rollback-new.err; then
  fail "reload failure for a newly created live profile should fail the update"
fi
grep -q 'subscription_apply=removed_after_reload_failure' /tmp/home-edge-sub-rollback-new.out || fail "new live profile failure did not report removal"
[ ! -e "$new_live_dir/live.yaml" ] || fail "failed new live profile was left in place"
fi

echo "subscription_fixture_tests=ok"
