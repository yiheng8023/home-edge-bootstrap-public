#!/bin/sh
# Offline deploy helper tests using fake ssh. Does not contact a router.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_parent=${TMPDIR:-/tmp}
tmp_root=$(mktemp -d "${tmp_parent%/}/home-edge-deploy-test.XXXXXX") || exit 1
fake_bin="$tmp_root/bin"
fixture_bundle="$tmp_root/bundle"
fixture_shellcrash="$tmp_root/shellcrash"
fixture_repo="$tmp_root/repo"
deploy="$fixture_repo/scripts/deploy-merlin.sh"
export DEPLOY_FAKE_SSH_LOG="$tmp_root/default-ssh.log"
export DEPLOY_FAKE_SSH_ARCHIVE="$tmp_root/default-ssh.tgz"
mkdir -p \
  "$fake_bin" \
  "$fixture_bundle" \
  "$fixture_shellcrash/libs" \
  "$fixture_shellcrash/starts" \
  "$fixture_repo/adapters" \
  "$fixture_repo/config" \
  "$fixture_repo/docs" \
  "$fixture_repo/scripts"

# Exercise the current deployment implementation against a deliberately small
# control-plane tree. Full repository/archive coverage belongs to the
# provenance and release fixtures; repeating it for every fake-SSH failure path
# makes this focused fixture needlessly expensive on Git Bash.
cp "$repo/README.md" "$repo/README.zh-CN.md" "$repo/bootstrap.sh" "$fixture_repo/"
for script in deploy-merlin.sh new-deployment-provenance.sh verify-bundle.sh migrate-router-state.sh; do
  cp "$repo/scripts/$script" "$fixture_repo/scripts/$script"
done
printf 'fixture\n' >"$fixture_repo/adapters/.fixture"
printf 'fixture\n' >"$fixture_repo/config/.fixture"
printf 'fixture\n' >"$fixture_repo/docs/.fixture"

# Runtime deployment behavior does not depend on the 40+ MiB production
# Mihomo binary. Keep this fixture deliberately tiny so repeated failure-path
# tests remain bounded on Windows Git Bash.
printf '\177ELFfixture\n' >"$fixture_bundle/mihomo-linux-arm64"
for required in init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh; do
  printf '#!/bin/sh\nexit 0\n' >"$fixture_shellcrash/$required"
done
tar -C "$fixture_shellcrash" -czf "$fixture_bundle/ShellCrash.tar.gz" \
  init.sh start.sh menu.sh libs starts
(
  cd "$fixture_bundle"
  sha256sum mihomo-linux-arm64 ShellCrash.tar.gz >SHA256SUMS
)
export DEPLOY_BUNDLE_DIR="$fixture_bundle"

cleanup() {
  if [ "${KEEP_DEPLOY_FIXTURE_TMP:-0}" = "1" ]; then
    echo "deploy_fixture_tmp=$tmp_root" >&2
    return
  fi
  rm -rf "$tmp_root"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "deploy_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

cat >"$fake_bin/ssh" <<'EOF'
#!/bin/sh
log="${DEPLOY_FAKE_SSH_LOG:-/tmp/home-edge-fake-ssh.log}"
archive="${DEPLOY_FAKE_SSH_ARCHIVE:-/tmp/home-edge-fake-ssh.tgz}"
count=0
if [ -n "${DEPLOY_FAKE_SSH_SEQUENCE_DIR:-}" ]; then
  mkdir -p "$DEPLOY_FAKE_SSH_SEQUENCE_DIR"
  count_file="$DEPLOY_FAKE_SSH_SEQUENCE_DIR/count"
  count=$(cat "$count_file" 2>/dev/null || echo 0)
  count=$((count + 1))
  printf '%s\n' "$count" >"$count_file"
  log="$DEPLOY_FAKE_SSH_SEQUENCE_DIR/command.$count.log"
  archive="$DEPLOY_FAKE_SSH_SEQUENCE_DIR/archive.$count.tgz"
fi
last=""
for arg in "$@"; do
  last="$arg"
done
printf '%s\n' "$last" >"$log"
if [ "${DEPLOY_FAKE_SSH_FAIL_AT:-0}" != "0" ] &&
  [ "${DEPLOY_FAKE_SSH_FAIL_AT:-0}" = "$count" ]; then
  cat >/dev/null
  exit 23
fi
case "$last" in
  *runtime_space_preflight_state*)
    case "${DEPLOY_FAKE_RUNTIME_SPACE_STATE:-ready}" in
      ready)
        echo "runtime_bundle_payload_bytes=44822199"
        echo "runtime_space_required_kib=103928"
        echo "runtime_space_available_kib=524288"
        echo "runtime_space_preflight_state=ready"
        ;;
      insufficient)
        echo "runtime_bundle_payload_bytes=44822199"
        echo "runtime_space_required_kib=103928"
        echo "runtime_space_available_kib=1024"
        echo "runtime_space_preflight_state=insufficient"
        exit 24
        ;;
      unavailable)
        echo "runtime_space_preflight_state=unavailable"
        exit 25
        ;;
      *) exit 26 ;;
    esac
    exit 0
    ;;
  *control_plane_rollback_state=restored*)
    echo "control_plane_rollback_state=restored"
    exit 0
    ;;
esac
cat >"$archive"
[ "${DEPLOY_FAKE_SSH_FAIL:-0}" = "1" ] && exit 23
exit 0
EOF
chmod 755 "$fake_bin/ssh"

if sh "$deploy" >"$tmp_root/deploy-missing.out" 2>"$tmp_root/deploy-missing.err"; then
  fail "missing router should fail"
fi
grep -q 'usage:' "$tmp_root/deploy-missing.err" || fail "missing usage output"

if PATH="$fake_bin:$PATH" REMOTE_DIR=/tmp/not-jffs sh "$deploy" user@router >"$tmp_root/deploy-bad-dir.out" 2>"$tmp_root/deploy-bad-dir.err"; then
  fail "remote dir outside /jffs should fail"
fi
grep -q 'under /jffs' "$tmp_root/deploy-bad-dir.err" || fail "missing /jffs validation message"

if PATH="$fake_bin:$PATH" REMOTE_DIR="/jffs/home edge" sh "$deploy" user@router >"$tmp_root/deploy-bad-char.out" 2>"$tmp_root/deploy-bad-char.err"; then
  fail "remote dir with spaces should fail"
fi
grep -q 'unsupported characters' "$tmp_root/deploy-bad-char.err" || fail "missing character validation message"

plan_log="$tmp_root/plan-command.log"
plan_archive="$tmp_root/plan.tgz"
PATH="$fake_bin:$PATH" DEPLOY_FAKE_SSH_LOG="$plan_log" DEPLOY_FAKE_SSH_ARCHIVE="$plan_archive" \
  sh "$deploy" user@router >"$tmp_root/deploy-plan.out" 2>"$tmp_root/deploy-plan.err"
grep -q '^deploy_state=plan$' "$tmp_root/deploy-plan.out" || fail "plan state missing"
grep -q '^apply_required=1$' "$tmp_root/deploy-plan.out" || fail "plan apply boundary missing"
[ ! -e "$plan_log" ] || fail "plan mode contacted ssh"
[ ! -e "$plan_archive" ] || fail "plan mode streamed an archive"

apply_log="$tmp_root/apply-command.log"
apply_archive="$tmp_root/apply.tgz"
if ! PATH="$fake_bin:$PATH" \
  APPLY=1 \
  DEPLOY_FAKE_SSH_LOG="$apply_log" \
  DEPLOY_FAKE_SSH_ARCHIVE="$apply_archive" \
  sh "$deploy" user@router >"$tmp_root/deploy-apply.out" 2>"$tmp_root/deploy-apply.err"; then
  sed -n '1,80p' "$tmp_root/deploy-apply.err" >&2
  fail "control-plane apply fixture failed"
fi
grep -q "BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh bootstrap.sh" "$apply_log" || fail "apply remote command missing BOOTSTRAP_APPLY"
grep -q "preserve_local_state" "$apply_log" || fail "apply remote command missing local-state preservation"
grep -q "deploy.lock" "$apply_log" || fail "apply remote command missing deployment lock"
grep -q "rollback_deploy" "$apply_log" || fail "apply remote command missing failure rollback"
grep -q "cleanup_first_install_active_state" "$apply_log" || fail "apply remote command does not clean first-install active surfaces on rollback"
grep -q '/jffs/home-edge-bootstrap-state/lifecycle/state.env' "$apply_log" || fail "apply remote command does not verify stable state schema"
grep -Fq 'stable_state_root=/jffs/home-edge-bootstrap-state' "$apply_log" || fail "apply remote command does not verify stable state root metadata"
mkdir -p "$tmp_root/apply-extract"
tar -xzf "$apply_archive" -C "$tmp_root/apply-extract"
[ -s "$tmp_root/apply-extract/DEPLOYMENT-PROVENANCE.env" ] || fail "deployment archive missing provenance metadata"
[ -s "$tmp_root/apply-extract/DEPLOYMENT-CONTENT-SHA256SUMS" ] || fail "deployment archive missing content hashes"
[ -s "$tmp_root/apply-extract/scripts/migrate-router-state.sh" ] || fail "deployment archive missing state migrator"
(cd "$tmp_root/apply-extract" && sha256sum -c DEPLOYMENT-CONTENT-SHA256SUMS >/dev/null) || fail "deployment provenance does not match archived bytes"
grep -Eq '^source_commit=([0-9a-f]{40}|non-git)$' "$tmp_root/apply-extract/DEPLOYMENT-PROVENANCE.env" || fail "deployment archive lacks bounded source identity"
grep -Eq '^content_id=[0-9a-f]{64}$' "$tmp_root/apply-extract/DEPLOYMENT-PROVENANCE.env" || fail "deployment archive lacks content id"
if grep -Fq 'hash=$(hash_file "$path")' "$repo/scripts/new-deployment-provenance.sh"; then
  fail "deployment provenance still forks one shell per staged file"
fi
grep -A1 'home-edge-start-shellcrash\.sh \\$' "$repo/scripts/deploy-merlin.sh" |
  grep -q 'home-edge-configure-service-rules\.sh' ||
  fail "deployment cleanup list does not include the service-rules helper safely"
grep -Fq "remote_script=\$(cat <<'HOME_EDGE_REMOTE_SCRIPT'" "$repo/scripts/deploy-merlin.sh" ||
  fail "deployment remote script is not protected by a quoted heredoc"

runtime_plan="$tmp_root/runtime-plan.out"
PATH="$fake_bin:$PATH" BOOTSTRAP_INSTALL_RUNTIME=1 \
  sh "$deploy" user@router >"$runtime_plan" 2>"$tmp_root/runtime-plan.err"
grep -q '^include_bundle=0$' "$runtime_plan" || fail "runtime plan should not persist the bundle in JFFS"
grep -q '^runtime_bundle_transport=temporary$' "$runtime_plan" || fail "runtime plan does not disclose temporary bundle transport"

runtime_sequence="$tmp_root/runtime-sequence"
PATH="$fake_bin:$PATH" APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=1 \
DEPLOY_FAKE_SSH_SEQUENCE_DIR="$runtime_sequence" \
sh "$deploy" user@router >"$tmp_root/runtime-apply.out" 2>"$tmp_root/runtime-apply.err"
[ "$(cat "$runtime_sequence/count")" -eq 3 ] || fail "runtime deploy should preflight space before separate control-plane and bundle transfers"
grep -q 'LC_ALL=C df -k /tmp' "$runtime_sequence/command.1.log" || fail "runtime deploy did not preflight portable /tmp free space"
grep -q 'runtime_space_preflight_state=ready' "$tmp_root/runtime-apply.out" || fail "runtime deploy did not report a ready space preflight"
grep -q 'BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_RUNTIME_FOLLOWS=1 sh bootstrap.sh' "$runtime_sequence/command.2.log" || fail "control-plane deploy did not declare the following runtime stage"
grep -q 'runtime_follows="1"' "$runtime_sequence/command.2.log" || fail "control-plane deploy did not bind its staged-only state"
grep -q 'deploy_state=staged' "$runtime_sequence/command.2.log" || fail "control-plane deploy lacks a staged state before runtime activation"
grep -q 'runtime_stage="/tmp/home-edge-runtime-bundle.\$\$"' "$runtime_sequence/command.3.log" || fail "runtime deploy did not allocate the temporary bundle directory"
grep -q 'BOOTSTRAP_BUNDLE_DIR="\$runtime_stage"' "$runtime_sequence/command.3.log" || fail "runtime deploy did not bind the temporary bundle directory"
mkdir -p "$tmp_root/runtime-main-extract" "$tmp_root/runtime-bundle-extract"
tar -xzf "$runtime_sequence/archive.2.tgz" -C "$tmp_root/runtime-main-extract"
[ ! -e "$tmp_root/runtime-main-extract/bundle/mihomo-linux-arm64" ] || fail "runtime payload leaked into persistent control-plane archive"
tar -xzf "$runtime_sequence/archive.3.tgz" -C "$tmp_root/runtime-bundle-extract"
[ -s "$tmp_root/runtime-bundle-extract/mihomo-linux-arm64" ] || fail "temporary runtime archive is missing Mihomo"
[ -s "$tmp_root/runtime-bundle-extract/ShellCrash.tar.gz" ] || fail "temporary runtime archive is missing ShellCrash"

runtime_insufficient_sequence="$tmp_root/runtime-insufficient-sequence"
if PATH="$fake_bin:$PATH" APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=1 \
  DEPLOY_FAKE_SSH_SEQUENCE_DIR="$runtime_insufficient_sequence" \
  DEPLOY_FAKE_RUNTIME_SPACE_STATE=insufficient \
  sh "$deploy" user@router >"$tmp_root/runtime-insufficient.out" 2>"$tmp_root/runtime-insufficient.err"; then
  fail "insufficient /tmp space should fail closed"
fi
[ "$(cat "$runtime_insufficient_sequence/count")" -eq 1 ] || fail "space failure should stop before control-plane or runtime bundle transfer"
grep -q '^runtime_space_preflight_state=insufficient$' "$tmp_root/runtime-insufficient.out" || fail "space failure marker missing"
[ ! -e "$runtime_insufficient_sequence/archive.1.tgz" ] || fail "space preflight should not receive a bundle payload"

runtime_failure_sequence="$tmp_root/runtime-failure-sequence"
if PATH="$fake_bin:$PATH" APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=1 \
  DEPLOY_FAKE_SSH_SEQUENCE_DIR="$runtime_failure_sequence" \
  DEPLOY_FAKE_SSH_FAIL_AT=3 \
  sh "$deploy" user@router >"$tmp_root/runtime-failure.out" 2>"$tmp_root/runtime-failure.err"; then
  fail "runtime transfer failure should propagate after rollback"
fi
[ "$(cat "$runtime_failure_sequence/count")" -eq 4 ] ||
  fail "runtime failure should trigger exactly one separate control-plane rollback"
grep -q 'control_plane_rollback_state=restored' "$runtime_failure_sequence/command.4.log" ||
  fail "runtime failure rollback command does not restore the previous control plane"
grep -q 'control_plane_rollback_state=removed' "$runtime_failure_sequence/command.4.log" ||
  fail "runtime failure rollback command does not remove a first-install staged control plane"
grep -q 'cleanup_first_install_active_state' "$runtime_failure_sequence/command.4.log" ||
  fail "runtime failure rollback command does not clean first-install active surfaces"
grep -q 'HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "$remote_dir/bootstrap.sh"' \
  "$runtime_failure_sequence/command.4.log" ||
  fail "runtime failure rollback command does not replay the restored control plane"
rollback_sim="$tmp_root/runtime-rollback-sim"
rollback_sim_script="$rollback_sim/rollback.sh"
rollback_sim_marker="$rollback_sim/bootstrap-replayed"
mkdir -p \
  "$rollback_sim/jffs/home-edge-bootstrap" \
  "$rollback_sim/jffs/home-edge-bootstrap.prev"
cat >"$rollback_sim/jffs/home-edge-bootstrap.prev/bootstrap.sh" <<'EOF'
#!/bin/sh
[ "${HOME_EDGE_WRITE_LOCK_HELD:-0}" = 1 ] || exit 91
: >"$DEPLOY_ROLLBACK_MARKER"
EOF
chmod 755 "$rollback_sim/jffs/home-edge-bootstrap.prev/bootstrap.sh"
sed \
  -e "s#remote_dir=\"/jffs/home-edge-bootstrap\"#remote_dir=\"$rollback_sim/jffs/home-edge-bootstrap\"#" \
  -e "s#lock_dir=\"/tmp/home-edge-bootstrap-write.lock\"#lock_dir=\"$rollback_sim/write.lock\"#" \
  "$runtime_failure_sequence/command.4.log" >"$rollback_sim_script"
DEPLOY_ROLLBACK_MARKER="$rollback_sim_marker" sh "$rollback_sim_script" \
  >"$rollback_sim/out" 2>"$rollback_sim/err" ||
  fail "runtime rollback could not replay the previous bootstrap while holding the global write lock"
[ -f "$rollback_sim_marker" ] ||
  fail "runtime rollback did not propagate the inherited write-lock marker"
[ -f "$rollback_sim/jffs/home-edge-bootstrap/bootstrap.sh" ] ||
  fail "runtime rollback simulation did not restore the previous control plane"
grep -q 'runtime stage failed; restoring the prior staged control plane' "$tmp_root/runtime-failure.err" ||
  fail "runtime failure did not report control-plane rollback"

if PATH="$fake_bin:$PATH" APPLY=1 DEPLOY_FAKE_SSH_FAIL=1 \
  sh "$deploy" user@router >"$tmp_root/deploy-ssh-fail.out" 2>"$tmp_root/deploy-ssh-fail.err"; then
  fail "ssh failure should propagate"
fi

echo "deploy_fixture_tests=ok"
