#!/bin/sh
# Offline deploy helper tests using fake ssh. Does not contact a router.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-deploy-test.XXXXXX") || exit 1
fake_bin="$tmp_root/bin"
export DEPLOY_FAKE_SSH_LOG="$tmp_root/default-ssh.log"
export DEPLOY_FAKE_SSH_ARCHIVE="$tmp_root/default-ssh.tgz"
mkdir -p "$fake_bin"

cleanup() {
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
last=""
for arg in "$@"; do
  last="$arg"
done
cat >"$archive"
printf '%s\n' "$last" >"$log"
[ "${DEPLOY_FAKE_SSH_FAIL:-0}" = "1" ] && exit 23
exit 0
EOF
chmod 755 "$fake_bin/ssh"

if sh "$repo/scripts/deploy-merlin.sh" >"$tmp_root/deploy-missing.out" 2>"$tmp_root/deploy-missing.err"; then
  fail "missing router should fail"
fi
grep -q 'usage:' "$tmp_root/deploy-missing.err" || fail "missing usage output"

if PATH="$fake_bin:$PATH" REMOTE_DIR=/tmp/not-jffs sh "$repo/scripts/deploy-merlin.sh" user@router >"$tmp_root/deploy-bad-dir.out" 2>"$tmp_root/deploy-bad-dir.err"; then
  fail "remote dir outside /jffs should fail"
fi
grep -q 'under /jffs' "$tmp_root/deploy-bad-dir.err" || fail "missing /jffs validation message"

if PATH="$fake_bin:$PATH" REMOTE_DIR="/jffs/home edge" sh "$repo/scripts/deploy-merlin.sh" user@router >"$tmp_root/deploy-bad-char.out" 2>"$tmp_root/deploy-bad-char.err"; then
  fail "remote dir with spaces should fail"
fi
grep -q 'unsupported characters' "$tmp_root/deploy-bad-char.err" || fail "missing character validation message"

plan_log="$tmp_root/plan-command.log"
plan_archive="$tmp_root/plan.tgz"
PATH="$fake_bin:$PATH" DEPLOY_FAKE_SSH_LOG="$plan_log" DEPLOY_FAKE_SSH_ARCHIVE="$plan_archive" \
  sh "$repo/scripts/deploy-merlin.sh" user@router >"$tmp_root/deploy-plan.out" 2>"$tmp_root/deploy-plan.err"
grep -q '^deploy_state=plan$' "$tmp_root/deploy-plan.out" || fail "plan state missing"
grep -q '^apply_required=1$' "$tmp_root/deploy-plan.out" || fail "plan apply boundary missing"
[ ! -e "$plan_log" ] || fail "plan mode contacted ssh"
[ ! -e "$plan_archive" ] || fail "plan mode streamed an archive"

apply_log="$tmp_root/apply-command.log"
apply_archive="$tmp_root/apply.tgz"
PATH="$fake_bin:$PATH" \
APPLY=1 \
DEPLOY_FAKE_SSH_LOG="$apply_log" \
DEPLOY_FAKE_SSH_ARCHIVE="$apply_archive" \
sh "$repo/scripts/deploy-merlin.sh" user@router >"$tmp_root/deploy-apply.out" 2>"$tmp_root/deploy-apply.err"
grep -q "BOOTSTRAP_APPLY=1 sh bootstrap.sh" "$apply_log" || fail "apply remote command missing BOOTSTRAP_APPLY"
grep -q "preserve_local_state" "$apply_log" || fail "apply remote command missing local-state preservation"
grep -q "deploy.lock" "$apply_log" || fail "apply remote command missing deployment lock"
grep -q "rollback_deploy" "$apply_log" || fail "apply remote command missing failure rollback"
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

if PATH="$fake_bin:$PATH" APPLY=1 DEPLOY_FAKE_SSH_FAIL=1 \
  sh "$repo/scripts/deploy-merlin.sh" user@router >"$tmp_root/deploy-ssh-fail.out" 2>"$tmp_root/deploy-ssh-fail.err"; then
  fail "ssh failure should propagate"
fi

echo "deploy_fixture_tests=ok"
