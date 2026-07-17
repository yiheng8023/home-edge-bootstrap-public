#!/bin/sh
# Offline behavior tests for the Merlin adapter.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "/tmp/home-edge-merlin-adapter-test.XXXXXX") || exit 1
cleanup() { case "$tmp" in /tmp/home-edge-merlin-adapter-test.*) rm -rf "$tmp" ;; esac; }
trap cleanup EXIT HUP INT TERM
export HOME_EDGE_WRITE_LOCK_DIR="$tmp/bootstrap.lock"

fail() {
  echo "merlin_adapter_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail "sha256sum or shasum is required for synthetic bundle fixtures"
  fi
}

if grep -Eq 'sed[[:space:]]+-i([[:space:]]|$)' "$repo/adapters/merlin/bootstrap.sh"; then
  fail "Merlin adapter must not use GNU-only sed -i syntax"
fi

wrong="$tmp/wrong-arch"
mkdir -p "$wrong/jffs"
if BOOTSTRAP_JFFS_DIR="$wrong/jffs" \
  BOOTSTRAP_INSTALL_DIR="$wrong/jffs/home-edge-bootstrap" \
  BOOTSTRAP_SCRIPT_DIR="$wrong/jffs/scripts" \
  BOOTSTRAP_SHELLCRASH_DIR="$wrong/jffs/ShellCrash" \
  BOOTSTRAP_APPLY=1 \
  BOOTSTRAP_INSTALL_RUNTIME=1 \
  BOOTSTRAP_ARCH_OVERRIDE=x86_64 \
  BOOTSTRAP_BUNDLE_HOST_VERIFIED=1 \
  sh "$repo/adapters/merlin/bootstrap.sh" >"$tmp/wrong.out" 2>"$tmp/wrong.err"; then
  fail "arm64 runtime install should reject x86_64 before writing"
fi
grep -q 'requires aarch64/arm64' "$tmp/wrong.err" || fail "wrong architecture message missing"
[ ! -e "$wrong/jffs/scripts/home-edge-policy.env" ] || fail "adapter wrote policy before architecture preflight"

mismatch="$tmp/script-dir-mismatch"
mkdir -p "$mismatch/jffs" "$mismatch/jffs/custom-scripts" "$mismatch/jffs/ShellCrash"
if BOOTSTRAP_JFFS_DIR="$mismatch/jffs" \
  BOOTSTRAP_INSTALL_DIR="$mismatch/jffs/home-edge-bootstrap" \
  BOOTSTRAP_SCRIPT_DIR="$mismatch/jffs/custom-scripts" \
  BOOTSTRAP_SHELLCRASH_DIR="$mismatch/jffs/ShellCrash" \
  sh "$repo/adapters/merlin/bootstrap.sh" >"$tmp/mismatch.out" 2>"$tmp/mismatch.err"; then
  fail "noncanonical BOOTSTRAP_SCRIPT_DIR should fail preflight"
fi
grep -q 'BOOTSTRAP_SCRIPT_DIR must equal BOOTSTRAP_JFFS_DIR/scripts' "$tmp/mismatch.err" || fail "script directory mismatch message missing"

# Build a small, valid offline kit for the replacement test. Public source
# projections intentionally omit release payloads, so this fixture must not
# depend on the repository's bundle/ directory being populated.
fixture_kit="$tmp/fixture-kit"
fixture_payload="$tmp/fixture-payload"
fixture_uname_log="$tmp/fixture-uname.log"
mkdir -p \
  "$fixture_kit/adapters/merlin" \
  "$fixture_kit/bin" \
  "$fixture_kit/bundle" \
  "$fixture_kit/config" \
  "$fixture_kit/scripts" \
  "$fixture_payload/libs" \
  "$fixture_payload/starts"
cp "$repo/adapters/merlin/bootstrap.sh" "$fixture_kit/adapters/merlin/bootstrap.sh"
cp "$repo/config/policy.env" "$fixture_kit/config/policy.env"
cp "$repo/scripts/self-heal.sh" "$fixture_kit/scripts/self-heal.sh"
cp "$repo/scripts/update-sub.sh" "$fixture_kit/scripts/update-sub.sh"
cp "$repo/scripts/subscription-runtime-evidence.sh" "$fixture_kit/scripts/subscription-runtime-evidence.sh"
cp "$repo/scripts/reconcile-self-heal-registration.sh" "$fixture_kit/scripts/reconcile-self-heal-registration.sh"
cp "$repo/scripts/verify-bundle.sh" "$fixture_kit/scripts/verify-bundle.sh"
cp "$repo/scripts/migrate-router-state.sh" "$fixture_kit/scripts/migrate-router-state.sh"

cat >"$fixture_kit/bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "${1:-}" >>"${FIXTURE_UNAME_LOG:?}"
case "${1:-}" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' x86_64 ;;
  *) exit 64 ;;
esac
EOF
chmod 755 "$fixture_kit/bin/uname"

printf '\177ELFsynthetic-mihomo-fixture\n' >"$fixture_kit/bundle/mihomo-linux-arm64"
chmod 755 "$fixture_kit/bundle/mihomo-linux-arm64"
printf '%s\n' '#!/bin/sh' 'runtime_tmp=/tmp/SC_tmp' >"$fixture_payload/init.sh"
for payload_file in \
  start.sh \
  menu.sh \
  libs/set_config.sh \
  starts/check_core.sh \
  libs/core_tools.sh; do
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$fixture_payload/$payload_file"
done
tar -czf "$fixture_kit/bundle/ShellCrash.tar.gz" \
  -C "$fixture_payload" \
  init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh
mihomo_sha=$(sha256_file "$fixture_kit/bundle/mihomo-linux-arm64")
shellcrash_sha=$(sha256_file "$fixture_kit/bundle/ShellCrash.tar.gz")
printf '%s  %s\n%s  %s\n' \
  "$mihomo_sha" mihomo-linux-arm64 \
  "$shellcrash_sha" ShellCrash.tar.gz \
  >"$fixture_kit/bundle/SHA256SUMS"
cat >"$fixture_kit/bundle/MANIFEST.json" <<EOF
{
  "schema": 1,
  "fixture": true,
  "payloads": [
    {"path": "mihomo-linux-arm64", "sha256": "$mihomo_sha"},
    {"path": "ShellCrash.tar.gz", "sha256": "$shellcrash_sha"}
  ]
}
EOF

core="$tmp/core-replace"
mkdir -p "$core/jffs/scripts" "$core/jffs/ShellCrash"
fakebin="$tmp/fakebin"
cru_state="$tmp/cru.state"
mkdir -p "$fakebin"
: >"$cru_state"
cat >"$fakebin/cru" <<'EOF'
#!/bin/sh
set -eu
state=${CRU_STATE:?}
case "${1:-}" in
  l) cat "$state" ;;
  d)
    next="$state.next.$$"
    grep -Fv "#${2:?}#" "$state" >"$next" || true
    mv "$next" "$state"
    ;;
  a) printf '%s #%s#\n' "${3:?}" "${2:?}" >>"$state" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$fakebin/cru"
printf 'custom-nat-start\n' >"$core/jffs/scripts/nat-start"
printf 'old-core\n' >"$core/jffs/ShellCrash/CrashCore.gz"
mkdir -p "$core/jffs/home-edge-bootstrap/backups/runtime/ShellCrash.20000101000000.1" "$core/jffs/home-edge-bootstrap/backups/runtime/ShellCrash.20000101000001.1"
printf 'old-a\n' >"$core/jffs/home-edge-bootstrap/backups/runtime/CrashCore.20000101000000.1.gz"
printf 'old-b\n' >"$core/jffs/home-edge-bootstrap/backups/runtime/CrashCore.20000101000001.1.gz"
printf 'old-a\n' >"$core/jffs/home-edge-bootstrap/backups/runtime/nat-start.20000101000000.1"
printf 'old-b\n' >"$core/jffs/home-edge-bootstrap/backups/runtime/nat-start.20000101000001.1"
sleep 1
if ! BOOTSTRAP_JFFS_DIR="$core/jffs" \
BOOTSTRAP_INSTALL_DIR="$core/jffs/home-edge-bootstrap" \
BOOTSTRAP_SCRIPT_DIR="$core/jffs/scripts" \
BOOTSTRAP_SHELLCRASH_DIR="$core/jffs/ShellCrash" \
BOOTSTRAP_STATE_FIXTURE_ROOT="$core" \
BOOTSTRAP_APPLY=1 \
BOOTSTRAP_INSTALL_RUNTIME=1 \
BOOTSTRAP_RUNTIME_MAX_BACKUPS=1 \
BOOTSTRAP_REPLACE_RUNTIME=1 \
BOOTSTRAP_RUNTIME_INIT_FIXTURE=1 \
BOOTSTRAP_ARCH_OVERRIDE=aarch64 \
BOOTSTRAP_BUNDLE_HOST_VERIFIED=1 \
BOOTSTRAP_RECONCILE_ROOT="$core" \
CRU_STATE="$cru_state" \
FIXTURE_UNAME_LOG="$fixture_uname_log" \
PATH="$fixture_kit/bin:$fakebin:$PATH" \
HEAL_POLICY_FILE="$fixture_kit/config/policy.env" \
HEAL_LOG="$core/self-heal.log" \
HEAL_API_CACHE="$core/self-heal.api" \
sh "$fixture_kit/adapters/merlin/bootstrap.sh" >"$tmp/core.out" 2>"$tmp/core.err"; then
  cat "$tmp/core.out" >&2
  cat "$tmp/core.err" >&2
  fail "runtime replacement fixture failed"
fi

grep -qx -- '-s' "$fixture_uname_log" || fail "synthetic verifier uname -s override was not used"
grep -qx -- '-m' "$fixture_uname_log" || fail "synthetic verifier uname -m override was not used"
grep -Fq 'not running on Linux arm64 (Linux/x86_64); skipped Mihomo execution check' "$tmp/core.err" || \
  fail "synthetic payload execution was not skipped"

[ -s "$core/jffs/ShellCrash/CrashCore.gz" ] || fail "new core was not staged"
[ -f "$core/jffs/home-edge-bootstrap-state/lifecycle/state.env" ] || fail "stable state schema was not created"
grep -Fxq 'state_migration_state=ready' "$tmp/core.out" || fail "adapter did not report ready state migration"
[ -x "$core/jffs/scripts/home-edge-reconcile-self-heal.sh" ] || fail "lifecycle reconciler was not deployed"
[ ! -e "$HOME_EDGE_WRITE_LOCK_DIR" ] || fail "bootstrap did not release its inherited global write lock"
[ -x "$core/jffs/scripts/home-edge-subscription-runtime-evidence.sh" ] || fail "subscription runtime evidence helper was not deployed"
grep -Fq '# BEGIN home-edge-bootstrap self-heal lifecycle' "$core/jffs/scripts/services-start" || fail "persistent lifecycle hook was not installed"
[ "$(grep -c '#home_edge_selfheal#' "$cru_state")" -eq 1 ] || fail "adapter did not leave exactly one self-heal cron job"
backup=""
for candidate in "$core/jffs/home-edge-bootstrap-state/backups/runtime"/ShellCrash.*/CrashCore.gz; do
  [ -f "$candidate" ] || continue
  if grep -q 'old-core' "$candidate"; then
    backup=$candidate
    break
  fi
done
[ -n "$backup" ] || fail "old core backup missing"
grep -l 'custom-nat-start' "$core/jffs/home-edge-bootstrap-state/backups/runtime"/nat-start.* >/dev/null 2>&1 || fail "custom script directory nat-start backup missing"
grep -Fq '/tmp/home-edge-shellcrash.' "$core/jffs/ShellCrash/init.home-edge.sh" || fail "ShellCrash init temp path was not isolated"
grep -q 'old-core' "$backup" || fail "old core backup content mismatch"
[ ! -e "$core/jffs/ShellCrash/CrashCore.gz.tmp."* ] || fail "temporary core residue remains"

for pattern in 'ShellCrash.*' 'CrashCore.*' 'nat-start.*'; do
  retained=0
  for candidate in "$core/jffs/home-edge-bootstrap-state/backups/runtime"/$pattern; do
    [ -e "$candidate" ] || continue
    retained=$((retained + 1))
  done
  [ "$retained" -le 1 ] || fail "runtime backup retention exceeded for $pattern"
done

HOME_EDGE_STATE_ROOT=/jffs/home-edge-bootstrap-state sh -c '
  . "$1"
  printf "%s\n" \
    "SUBSCRIPTION_FILE=$SUBSCRIPTION_FILE" \
    "SUBSCRIPTION_CACHE=$SUBSCRIPTION_CACHE" \
    "SUBSCRIPTION_BACKUP_DIR=$SUBSCRIPTION_BACKUP_DIR"
' sh "$repo/config/policy.env" >"$tmp/policy-values.out"
grep -Fxq 'SUBSCRIPTION_FILE=/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local' "$tmp/policy-values.out" || fail "subscription file default is not stable"
grep -Fxq 'SUBSCRIPTION_CACHE=/jffs/home-edge-bootstrap-state/cache/subscription.yaml' "$tmp/policy-values.out" || fail "subscription cache default is not stable"
grep -Fxq 'SUBSCRIPTION_BACKUP_DIR=/jffs/home-edge-bootstrap-state/backups/subscription' "$tmp/policy-values.out" || fail "subscription backup default is not stable"
echo "merlin_adapter_fixture_tests=ok"
