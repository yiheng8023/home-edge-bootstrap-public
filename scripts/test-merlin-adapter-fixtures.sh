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
fixture_bundle="$tmp/fixture-bundle"
fixture_payload="$tmp/fixture-payload"
fixture_uname_log="$tmp/fixture-uname.log"
mkdir -p \
  "$fixture_kit/adapters/merlin" \
  "$fixture_kit/bin" \
  "$fixture_kit/config" \
  "$fixture_kit/scripts" \
  "$fixture_bundle" \
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
cp "$repo/scripts/home-edge-secure-temp.sh" "$fixture_kit/scripts/home-edge-secure-temp.sh"
cp "$repo/scripts/configure-shellcrash-dns.sh" "$fixture_kit/scripts/configure-shellcrash-dns.sh"
cp "$repo/scripts/prefetch-shellcrash-data.sh" "$fixture_kit/scripts/prefetch-shellcrash-data.sh"
cp "$repo/scripts/start-shellcrash-at-boot.sh" "$fixture_kit/scripts/start-shellcrash-at-boot.sh"
cp "$repo/scripts/configure-shellcrash-service-rules.sh" "$fixture_kit/scripts/configure-shellcrash-service-rules.sh"

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

printf '\177ELFsynthetic-mihomo-fixture\n' >"$fixture_bundle/mihomo-linux-arm64"
chmod 755 "$fixture_bundle/mihomo-linux-arm64"
printf '%s\n' '#!/bin/sh' 'runtime_tmp=/tmp/SC_tmp' >"$fixture_payload/init.sh"
for payload_file in \
  start.sh \
  menu.sh \
  libs/set_config.sh \
  starts/check_core.sh \
  libs/core_tools.sh; do
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$fixture_payload/$payload_file"
done
# Mirror the upstream setconfig hazard: it dereferences the optional third
# argument under set -u. The adapter must never invoke it without an explicit
# config path; its own atomic writer deliberately avoids this API.
cat >"$fixture_payload/libs/set_config.sh" <<'EOF'
#!/bin/sh
set -u
setconfig() {
  key=$1
  value=$2
  cfg=$3
  printf '%s=%s\n' "$key" "$value" >>"$cfg"
}
EOF
tar -czf "$fixture_bundle/ShellCrash.tar.gz" \
  -C "$fixture_payload" \
  init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh
mihomo_sha=$(sha256_file "$fixture_bundle/mihomo-linux-arm64")
shellcrash_sha=$(sha256_file "$fixture_bundle/ShellCrash.tar.gz")
printf '%s  %s\n%s  %s\n' \
  "$mihomo_sha" mihomo-linux-arm64 \
  "$shellcrash_sha" ShellCrash.tar.gz \
  >"$fixture_bundle/SHA256SUMS"
cat >"$fixture_bundle/MANIFEST.json" <<EOF
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

hostdir_root="$tmp/hostdir-normalize"
mkdir -p "$hostdir_root/jffs/scripts" "$hostdir_root/jffs/ShellCrash/configs" "$hostdir_root/jffs/ShellCrash/task"
cat >"$hostdir_root/jffs/ShellCrash/configs/ShellCrash.cfg" <<'EOF'
hostdir="':9999/ui'"
EOF
cat >"$hostdir_root/jffs/ShellCrash/configs/command.env" <<'EOF'
TMPDIR=/tmp/ShellCrash
COMMAND="$TMPDIR/CrashCore -d $BINDIR -f $TMPDIR/config.yaml"
BINDIR=/jffs/ShellCrash
EOF
cat >"$hostdir_root/jffs/ShellCrash/task/bfstart" <<'EOF'
/jffs/ShellCrash/task/task.sh 101 服务启动前启动ShellCrash服务
/jffs/ShellCrash/task/task.sh 106 服务启动前自动保存面板配置
/jffs/ShellCrash/task/task.sh 111 服务启动前自动更新内核
/custom/preserved-task.sh
EOF
cat >"$hostdir_root/jffs/ShellCrash/task/afstart" <<'EOF'
/jffs/ShellCrash/task/task.sh 107 服务启动后自动同步ntp时间
/jffs/ShellCrash/task/task.sh 112 服务启动后自动更新脚本
/jffs/ShellCrash/task/task.sh 113 服务启动后自动更新数据库文件
EOF
if ! BOOTSTRAP_JFFS_DIR="$hostdir_root/jffs" \
BOOTSTRAP_INSTALL_DIR="$hostdir_root/jffs/home-edge-bootstrap" \
BOOTSTRAP_SCRIPT_DIR="$hostdir_root/jffs/scripts" \
BOOTSTRAP_SHELLCRASH_DIR="$hostdir_root/jffs/ShellCrash" \
BOOTSTRAP_STATE_FIXTURE_ROOT="$hostdir_root" \
BOOTSTRAP_APPLY=1 \
BOOTSTRAP_INSTALL_RUNTIME=0 \
BOOTSTRAP_RUNTIME_FOLLOWS=1 \
BOOTSTRAP_RECONCILE_ROOT="$hostdir_root" \
CRU_STATE="$cru_state" \
PATH="$fixture_kit/bin:$fakebin:$PATH" \
HEAL_POLICY_FILE="$fixture_kit/config/policy.env" \
HEAL_LOG="$hostdir_root/self-heal.log" \
HEAL_API_CACHE="$hostdir_root/self-heal.api" \
sh "$fixture_kit/adapters/merlin/bootstrap.sh" >"$tmp/hostdir.out" 2>"$tmp/hostdir.err"; then
  cat "$tmp/hostdir.out" >&2
  cat "$tmp/hostdir.err" >&2
  fail "quoted hostdir normalization fixture failed"
fi
grep -Fxq 'hostdir=:9999/ui' "$hostdir_root/jffs/ShellCrash/configs/ShellCrash.cfg" ||
  fail "adapter did not collapse nested ShellCrash hostdir quotes"
grep -Fq 'normalized quoted ShellCrash hostdir' "$tmp/hostdir.out" ||
  fail "adapter did not report hostdir normalization"
command_env="$hostdir_root/jffs/ShellCrash/configs/command.env"
[ "$(awk -F= '$1 == "TMPDIR" { print NR }' "$command_env")" -lt "$(awk -F= '$1 == "COMMAND" { print NR }' "$command_env")" ] ||
  fail "adapter did not place TMPDIR before COMMAND"
[ "$(awk -F= '$1 == "BINDIR" { print NR }' "$command_env")" -lt "$(awk -F= '$1 == "COMMAND" { print NR }' "$command_env")" ] ||
  fail "adapter did not place BINDIR before COMMAND"
(
  set +u
  unset TMPDIR BINDIR COMMAND
  . "$command_env"
  [ "$COMMAND" = "/tmp/ShellCrash/CrashCore -d /jffs/ShellCrash -f /tmp/ShellCrash/config.yaml" ]
) || fail "adapter command.env ordering repair did not preserve semantic command expansion"
grep -Fq 'normalized ShellCrash command.env dependency order' "$tmp/hostdir.out" ||
  fail "adapter did not report command.env dependency order normalization"
if grep -Eq '/task\.sh[[:space:]]+(101|111|112|113)([[:space:]]|$)' \
  "$hostdir_root/jffs/ShellCrash/task/bfstart" "$hostdir_root/jffs/ShellCrash/task/afstart"; then
  fail "adapter retained recursive or startup-update ShellCrash tasks"
fi
grep -Fq '/jffs/ShellCrash/task/task.sh 106 ' "$hostdir_root/jffs/ShellCrash/task/bfstart" ||
  fail "adapter removed benign pre-start task"
grep -Fq '/custom/preserved-task.sh' "$hostdir_root/jffs/ShellCrash/task/bfstart" ||
  fail "adapter removed unrelated custom pre-start task"
grep -Fq '/jffs/ShellCrash/task/task.sh 107 ' "$hostdir_root/jffs/ShellCrash/task/afstart" ||
  fail "adapter removed benign post-start task"
task_backup_count=0
for task_backup in "$hostdir_root/jffs/home-edge-bootstrap-state/backups/shellcrash-tasks"/*.tasks; do
  [ -f "$task_backup" ] || continue
  task_backup_count=$((task_backup_count + 1))
done
[ "$task_backup_count" -eq 2 ] ||
  fail "adapter did not back up both normalized ShellCrash task surfaces"

command_env_attack="$tmp/command-env-attack"
command_env_sentinel="$tmp/command-env-executed"
cp -a "$hostdir_root" "$command_env_attack"
cat >"$command_env_attack/jffs/ShellCrash/configs/command.env" <<EOF
TMPDIR=/tmp/ShellCrash
BINDIR=/jffs/ShellCrash
COMMAND="\$TMPDIR/CrashCore -d \$BINDIR -f \$TMPDIR/config.yaml"
touch "$command_env_sentinel"
EOF
if BOOTSTRAP_JFFS_DIR="$command_env_attack/jffs" \
  BOOTSTRAP_INSTALL_DIR="$command_env_attack/jffs/home-edge-bootstrap" \
  BOOTSTRAP_SCRIPT_DIR="$command_env_attack/jffs/scripts" \
  BOOTSTRAP_SHELLCRASH_DIR="$command_env_attack/jffs/ShellCrash" \
  BOOTSTRAP_STATE_FIXTURE_ROOT="$command_env_attack" \
  BOOTSTRAP_APPLY=1 \
  BOOTSTRAP_INSTALL_RUNTIME=0 \
  BOOTSTRAP_RUNTIME_FOLLOWS=1 \
  BOOTSTRAP_RECONCILE_ROOT="$command_env_attack" \
  CRU_STATE="$cru_state" \
  PATH="$fixture_kit/bin:$fakebin:$PATH" \
  HEAL_POLICY_FILE="$fixture_kit/config/policy.env" \
  HEAL_LOG="$command_env_attack/self-heal.log" \
  HEAL_API_CACHE="$command_env_attack/self-heal.api" \
  sh "$fixture_kit/adapters/merlin/bootstrap.sh" >"$tmp/command-env-attack.out" 2>"$tmp/command-env-attack.err"; then
  fail "adapter accepted an executable command.env statement"
fi
[ ! -e "$command_env_sentinel" ] ||
  fail "adapter executed an unsupported command.env statement"
grep -Fq 'command.env contains unsupported statements' "$tmp/command-env-attack.err" ||
  fail "adapter rejected command.env injection for the wrong reason"

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
BOOTSTRAP_BUNDLE_DIR="$fixture_bundle" \
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
[ -s "$core/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz" ] ||
  fail "protected Mihomo core source was not staged"
cmp -s \
  "$core/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz" \
  "$core/jffs/ShellCrash/CrashCore.gz" ||
  fail "ShellCrash core differs from protected core source"
[ -f "$core/jffs/home-edge-bootstrap-state/lifecycle/state.env" ] || fail "stable state schema was not created"
grep -Fxq 'state_migration_state=ready' "$tmp/core.out" || fail "adapter did not report ready state migration"
[ -x "$core/jffs/scripts/home-edge-reconcile-self-heal.sh" ] || fail "lifecycle reconciler was not deployed"
[ ! -e "$HOME_EDGE_WRITE_LOCK_DIR" ] || fail "bootstrap did not release its inherited global write lock"
[ -x "$core/jffs/scripts/home-edge-subscription-runtime-evidence.sh" ] || fail "subscription runtime evidence helper was not deployed"
[ -x "$core/jffs/scripts/home-edge-configure-dns.sh" ] || fail "ShellCrash DNS configuration helper was not deployed"
[ -x "$core/jffs/scripts/home-edge-prefetch-shellcrash-data.sh" ] || fail "ShellCrash data prefetch helper was not deployed"
[ -x "$core/jffs/scripts/home-edge-start-shellcrash.sh" ] || fail "ShellCrash boot starter was not deployed"
[ -x "$core/jffs/scripts/home-edge-configure-service-rules.sh" ] || fail "ShellCrash service-rule profile helper was not deployed"
grep -Fq '# BEGIN home-edge-bootstrap self-heal lifecycle' "$core/jffs/scripts/services-start" || fail "persistent lifecycle hook was not installed"
grep -Fq '/jffs/scripts/home-edge-start-shellcrash.sh' "$core/jffs/scripts/services-start" ||
  fail "persistent lifecycle hook does not start ShellCrash conservatively"
[ "$(grep -c '#home_edge_selfheal#' "$cru_state")" -eq 1 ] || fail "adapter did not leave exactly one self-heal cron job"
cron_wrapper="$core/jffs/scripts/home-edge-self-heal-cron.sh"
grep -Fq '/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local' "$cron_wrapper" ||
  fail "self-heal cron wrapper does not gate on stable subscription state"
grep -Fq '/jffs/ShellCrash/yamls/config.yaml' "$cron_wrapper" ||
  fail "self-heal cron wrapper does not recognize a runtime-managed YAML profile"
grep -Fq '/jffs/ShellCrash/jsons/config.json' "$cron_wrapper" ||
  fail "self-heal cron wrapper does not recognize a runtime-managed JSON profile"
grep -Fq '/jffs/home-edge-bootstrap-state/CONTROLLER_SECRET.local' "$cron_wrapper" ||
  fail "self-heal cron wrapper does not discover the stable controller secret file"
grep -Fq 'CLASH_SECRET_FILE=' "$cron_wrapper" ||
  fail "self-heal cron wrapper does not pass controller authentication by file"
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
