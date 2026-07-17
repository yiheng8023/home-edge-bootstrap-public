#!/bin/sh
# Offline transaction tests for safe Merlin project decommission.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_base=${TMPDIR:-/tmp}
[ "$tmp_base" = / ] || tmp_base=${tmp_base%/}
tmp=$(mktemp -d "$tmp_base/home-edge-decommission-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
find_cmd=$(command -v find) || exit 1
[ ! -x /usr/bin/find ] || find_cmd=/usr/bin/find
sort_cmd=$(command -v sort) || exit 1
[ ! -x /usr/bin/sort ] || sort_cmd=/usr/bin/sort
real_rm=$(command -v rm) || exit 1

fail() {
  echo "decommission_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
  else shasum -a 256 | awk '{print $1}'
  fi
}
hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}
tree_digest() {
  root=$1
  (
    CDPATH= cd "$root"
    "$find_cmd" . -mindepth 1 -print | tr -d '\r' | LC_ALL=C "$sort_cmd" | while IFS= read -r rel; do
      if [ -L "$rel" ]; then
        printf 'l %s %s\n' "$rel" "$(readlink "$rel")"
      elif [ -f "$rel" ]; then
        mode=$(stat -c '%a' "$rel" 2>/dev/null || stat -f '%Lp' "$rel")
        printf 'f %s %s %s\n' "$rel" "$mode" "$(hash_file "$rel")"
      elif [ -d "$rel" ]; then
        mode=$(stat -c '%a' "$rel" 2>/dev/null || stat -f '%Lp' "$rel")
        printf 'd %s %s\n' "$rel" "$mode"
      else
        printf 'o %s\n' "$rel"
      fi
    done
  ) | hash_stdin
}

source_root="$tmp/source"
mkdir -p "$source_root"
git -C "$source_root" init -q
git -C "$source_root" config user.email fixture@example.invalid
git -C "$source_root" config user.name fixture
git -C "$source_root" config core.autocrlf false
printf '%s\n' fixture >"$source_root/source.txt"
git -C "$source_root" add source.txt
git -C "$source_root" commit -qm baseline

write_bridge() {
  cat >"$1" <<'EOF'
# home-edge-bootstrap-owned: stable-state-compatibility/v1
SUBSCRIPTION_FILE=/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local
SUBSCRIPTION_CACHE=/jffs/home-edge-bootstrap-state/cache/subscription.yaml
SUBSCRIPTION_BACKUP_DIR=/jffs/home-edge-bootstrap-state/backups/subscription
[ ! -r /jffs/home-edge-bootstrap-state/policy.local ] || . /jffs/home-edge-bootstrap-state/policy.local
EOF
}

setup_target() {
  root="$tmp/$1"
  install="$root/jffs/home-edge-bootstrap"
  scripts="$root/jffs/scripts"
  state="$root/jffs/home-edge-bootstrap-state"
  mkdir -p "$install/config" "$install/scripts" "$scripts" \
    "$state/cache" "$state/backups/runtime" "$state/backups/subscription" "$state/lifecycle" \
    "$root/jffs/ShellCrash" "$root/jffs/home-edge-bootstrap.prev" \
    "$root/jffs/home-edge-bootstrap.rollback.1" "$root/jffs/home-edge-bootstrap.failed.2" \
    "$root/jffs/home-edge-bootstrap.tmp.3" "$root/jffs/home-edge-bootstrap.rollback.1-user" \
    "$root/jffs/home-edge-bootstrap-user" "$root/tmp" "$root/bin"

  printf '%s\n' 'external-runtime' >"$root/jffs/ShellCrash/CrashCore"
  printf '%s\n' 'unrelated-kit-like-data' >"$root/jffs/home-edge-bootstrap-user/keep.txt"
  printf '%s\n' 'near-match-unrelated-data' >"$root/jffs/home-edge-bootstrap.rollback.1-user/keep.txt"
  printf '%s\n' 'https://credential.invalid/private' >"$state/SUBSCRIPTION.local"
  printf '%s\n' 'HEAL_CRON_DRY_RUN=0' >"$state/policy.local"
  printf '%s\n' 'regenerable-cache' >"$state/cache/subscription.yaml"
  printf '%s\n' 'runtime-backup' >"$state/backups/runtime/CrashCore.fixture.gz"
  printf '%s\n' 'subscription-backup' >"$state/backups/subscription/subscription.fixture.yaml"
  cat >"$state/lifecycle/state.env" <<'EOF'
state_schema_version=1
adapter=merlin
stable_state_root=/jffs/home-edge-bootstrap-state
EOF

  printf '%s\n' 'HEAL_CRON_DRY_RUN=1' >"$install/config/policy.env"
  for name in self-heal.sh update-sub.sh subscription-runtime-evidence.sh verify-bundle.sh reconcile-self-heal-registration.sh; do
    printf '%s\n' '#!/bin/sh' "echo $name" >"$install/scripts/$name"
  done
  cp "$repo/scripts/migrate-router-state.sh" "$install/scripts/migrate-router-state.sh"
  cp "$repo/scripts/verify-deployment-provenance.sh" "$install/scripts/verify-deployment-provenance.sh"
  sh "$repo/scripts/new-deployment-provenance.sh" "$install" "$source_root"

  cp "$install/config/policy.env" "$scripts/home-edge-policy.env"
  cp "$install/scripts/self-heal.sh" "$scripts/home-edge-self-heal.sh"
  cp "$install/scripts/update-sub.sh" "$scripts/home-edge-update-sub.sh"
  cp "$install/scripts/subscription-runtime-evidence.sh" "$scripts/home-edge-subscription-runtime-evidence.sh"
  cp "$install/scripts/verify-bundle.sh" "$scripts/home-edge-verify-bundle.sh"
  cp "$install/scripts/reconcile-self-heal-registration.sh" "$scripts/home-edge-reconcile-self-heal.sh"
  printf '%s\n' '#!/bin/sh' 'exit 0' >"$scripts/home-edge-self-heal-cron.sh"
  chmod 755 "$scripts"/home-edge-*.sh
  write_bridge "$scripts/home-edge-policy.local"
  cat >"$scripts/services-start" <<'EOF'
#!/bin/sh
echo preserved-before
# BEGIN home-edge-bootstrap self-heal lifecycle
if [ -x /jffs/scripts/home-edge-reconcile-self-heal.sh ]; then
  HOME_EDGE_WRITE_LOCK_HELD=1 sh /jffs/scripts/home-edge-reconcile-self-heal.sh --reconcile || true
fi
# END home-edge-bootstrap self-heal lifecycle
echo preserved-after
EOF
  chmod 755 "$scripts/services-start"

  printf '%s\n' '*/5 * * * * sh /jffs/scripts/home-edge-self-heal-cron.sh #home_edge_selfheal#' >"$root/tmp/cru.state"
  cat >"$root/bin/cru" <<'EOF'
#!/bin/sh
set -eu
state=${DECOMMISSION_CRU_STATE:?}
case "${1:-}" in
  l) cat "$state" ;;
  d)
    name=${2:?}
    next="$state.next.$$"
    grep -Fv "#$name#" "$state" >"$next" || true
    mv "$next" "$state"
    ;;
  *) exit 2 ;;
esac
EOF
  chmod 755 "$root/bin/cru"
  printf '%s\n' "$root"
}

sut="$repo/scripts/decommission-router-state.sh"
run_decommission() {
  root=$1
  apply=$2
  confirmation=${3:-}
  HOME_EDGE_DECOMMISSION_ROOT="$root" \
  HOME_EDGE_STATE_MIGRATOR="$repo/scripts/migrate-router-state.sh" \
  DECOMMISSION_CRU_STATE="$root/tmp/cru.state" \
  DECOMMISSION_APPLY="$apply" \
  DECOMMISSION_CONFIRMATION="$confirmation" \
  PATH="$root/bin:$PATH" \
  sh "$sut"
}

[ -f "$sut" ] || fail "missing router-side decommission transaction"

plan_root=$(setup_target plan)
plan_before=$(tree_digest "$plan_root")
run_decommission "$plan_root" 0 >"$tmp/plan.out"
plan_after=$(tree_digest "$plan_root")
[ "$plan_before" = "$plan_after" ] || fail "decommission plan wrote state"
grep -Fxq 'decommission_state=plan_ready' "$tmp/plan.out" || fail "plan state missing"
grep -Fxq 'state_migration_state=ready' "$tmp/plan.out" || fail "plan omitted ready migration"
grep -Fxq 'project_registration_state=present' "$tmp/plan.out" || fail "plan omitted project registration state"
grep -Fxq 'retained_state_root=/jffs/home-edge-bootstrap-state' "$tmp/plan.out" || fail "plan omitted retained root"
! grep -Fq 'credential.invalid' "$tmp/plan.out" || fail "plan leaked subscription content"

confirm_root=$(setup_target confirmation)
confirm_before=$(tree_digest "$confirm_root")
if run_decommission "$confirm_root" 1 WRONG >"$tmp/confirm.out" 2>&1; then
  fail "wrong confirmation succeeded"
fi
[ "$(tree_digest "$confirm_root")" = "$confirm_before" ] || fail "wrong confirmation wrote state"
grep -Fxq 'decommission_state=blocked' "$tmp/confirm.out" || fail "wrong confirmation did not report blocked"

apply_root=$(setup_target apply)
cp "$apply_root/jffs/scripts/services-start" "$tmp/services.before"
printf '%s\n' '#!/bin/sh' 'echo preserved-before' 'echo preserved-after' >"$tmp/services.expected"
chmod 755 "$tmp/services.expected"
cp "$apply_root/jffs/ShellCrash/CrashCore" "$tmp/shellcrash.before"
cp "$apply_root/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local" "$tmp/subscription.before"
cp "$apply_root/jffs/home-edge-bootstrap-state/policy.local" "$tmp/policy.before"
run_decommission "$apply_root" 1 DECOMMISSION >"$tmp/apply.out"
grep -Fxq 'decommission_state=ready' "$tmp/apply.out" || fail "apply did not report ready"
cmp "$tmp/services.expected" "$apply_root/jffs/scripts/services-start" >/dev/null || fail "unmanaged services-start bytes changed"
cmp "$tmp/shellcrash.before" "$apply_root/jffs/ShellCrash/CrashCore" >/dev/null || fail "external runtime changed"
cmp "$tmp/subscription.before" "$apply_root/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local" >/dev/null || fail "subscription state changed"
cmp "$tmp/policy.before" "$apply_root/jffs/home-edge-bootstrap-state/policy.local" >/dev/null || fail "policy state changed"
[ -d "$apply_root/jffs/home-edge-bootstrap-state/backups/runtime" ] || fail "runtime recovery backup was removed"
[ ! -e "$apply_root/jffs/home-edge-bootstrap-state/cache" ] || fail "default regenerable cache remained"
[ -f "$apply_root/jffs/home-edge-bootstrap-user/keep.txt" ] || fail "unrelated kit-like directory changed"
[ -f "$apply_root/jffs/home-edge-bootstrap.rollback.1-user/keep.txt" ] || fail "near-match rollback directory changed"
[ ! -e "$apply_root/jffs/home-edge-bootstrap" ] || fail "current kit remained"
[ ! -e "$apply_root/jffs/home-edge-bootstrap.prev" ] || fail "previous kit remained"
[ ! -e "$apply_root/jffs/home-edge-bootstrap.rollback.1" ] || fail "rollback kit remained"
[ ! -e "$apply_root/jffs/home-edge-bootstrap.failed.2" ] || fail "failed kit remained"
[ ! -e "$apply_root/jffs/home-edge-bootstrap.tmp.3" ] || fail "temporary kit remained"
for helper in home-edge-policy.env home-edge-policy.local home-edge-self-heal.sh home-edge-update-sub.sh home-edge-subscription-runtime-evidence.sh home-edge-verify-bundle.sh home-edge-reconcile-self-heal.sh home-edge-self-heal-cron.sh; do
  [ ! -e "$apply_root/jffs/scripts/$helper" ] || fail "fixed helper remained: $helper"
done
[ ! -s "$apply_root/tmp/cru.state" ] || fail "cron registration remained"

rerun_before=$(tree_digest "$apply_root")
run_decommission "$apply_root" 1 DECOMMISSION >"$tmp/rerun.out"
rerun_after=$(tree_digest "$apply_root")
[ "$rerun_before" = "$rerun_after" ] || fail "idempotent rerun wrote state"
grep -Fxq 'decommission_state=already_decommissioned' "$tmp/rerun.out" || fail "rerun did not report already decommissioned"

duplicate_root=$(setup_target duplicate-marker)
cat >>"$duplicate_root/jffs/scripts/services-start" <<'EOF'
# BEGIN home-edge-bootstrap self-heal lifecycle
# END home-edge-bootstrap self-heal lifecycle
EOF
duplicate_before=$(tree_digest "$duplicate_root")
if run_decommission "$duplicate_root" 1 DECOMMISSION >"$tmp/duplicate.out" 2>&1; then fail "duplicate marker apply succeeded"; fi
[ "$(tree_digest "$duplicate_root")" = "$duplicate_before" ] || fail "duplicate marker blocker wrote state"
grep -Fxq 'decommission_state=blocked' "$tmp/duplicate.out" || fail "duplicate marker was not blocked"

malformed_root=$(setup_target malformed-marker)
grep -Fv '# END home-edge-bootstrap self-heal lifecycle' "$malformed_root/jffs/scripts/services-start" >"$malformed_root/jffs/scripts/services-start.tmp"
mv "$malformed_root/jffs/scripts/services-start.tmp" "$malformed_root/jffs/scripts/services-start"
malformed_before=$(tree_digest "$malformed_root")
if run_decommission "$malformed_root" 1 DECOMMISSION >"$tmp/malformed.out" 2>&1; then fail "malformed marker apply succeeded"; fi
[ "$(tree_digest "$malformed_root")" = "$malformed_before" ] || fail "malformed marker blocker wrote state"
grep -Fxq 'decommission_state=blocked' "$tmp/malformed.out" || fail "malformed marker was not blocked"

cron_root=$(setup_target ambiguous-cron)
printf '%s\n' '*/7 * * * * sh /jffs/scripts/home-edge-self-heal-cron.sh #home_edge_selfheal#' >>"$cron_root/tmp/cru.state"
cron_before=$(tree_digest "$cron_root")
if run_decommission "$cron_root" 1 DECOMMISSION >"$tmp/cron.out" 2>&1; then fail "ambiguous cron apply succeeded"; fi
[ "$(tree_digest "$cron_root")" = "$cron_before" ] || fail "ambiguous cron blocker wrote state"
grep -Fxq 'decommission_state=blocked' "$tmp/cron.out" || fail "ambiguous cron was not blocked"

drift_root=$(setup_target provenance-drift)
printf '%s\n' '# drift' >>"$drift_root/jffs/scripts/home-edge-self-heal.sh"
drift_before=$(tree_digest "$drift_root")
if run_decommission "$drift_root" 1 DECOMMISSION >"$tmp/drift.out" 2>&1; then fail "provenance drift apply succeeded"; fi
[ "$(tree_digest "$drift_root")" = "$drift_before" ] || fail "provenance blocker wrote state"
grep -Fxq 'decommission_state=blocked' "$tmp/drift.out" || fail "provenance drift was not blocked"

conflict_root=$(setup_target migration-conflict)
printf '%s\n' 'HEAL_CRON_DRY_RUN=1' >"$conflict_root/jffs/home-edge-bootstrap/policy.local"
conflict_before=$(tree_digest "$conflict_root")
if run_decommission "$conflict_root" 1 DECOMMISSION >"$tmp/conflict.out" 2>&1; then fail "migration conflict apply succeeded"; fi
[ "$(tree_digest "$conflict_root")" = "$conflict_before" ] || fail "migration conflict blocker wrote state"
grep -Fxq 'decommission_state=conflict' "$tmp/conflict.out" || fail "migration conflict did not report conflict"

symlink_root=$(setup_target symlink)
rm -f "$symlink_root/jffs/scripts/home-edge-self-heal.sh"
ln -s /tmp/not-owned "$symlink_root/jffs/scripts/home-edge-self-heal.sh" 2>/dev/null || true
if [ -L "$symlink_root/jffs/scripts/home-edge-self-heal.sh" ]; then
  symlink_before=$(tree_digest "$symlink_root")
  if run_decommission "$symlink_root" 1 DECOMMISSION >"$tmp/symlink.out" 2>&1; then fail "symlink apply succeeded"; fi
  [ "$(tree_digest "$symlink_root")" = "$symlink_before" ] || fail "symlink blocker wrote state"
  grep -Fxq 'decommission_state=blocked' "$tmp/symlink.out" || fail "symlink was not blocked"
fi

lock_root=$(setup_target active-lock)
mkdir -p "$lock_root/tmp/home-edge-bootstrap-write.lock"
printf '%s\n' "$$" >"$lock_root/tmp/home-edge-bootstrap-write.lock/pid"
date +%s >"$lock_root/tmp/home-edge-bootstrap-write.lock/started_at"
printf '%s\n' competing-operation >"$lock_root/tmp/home-edge-bootstrap-write.lock/operation"
lock_before=$(tree_digest "$lock_root")
if run_decommission "$lock_root" 1 DECOMMISSION >"$tmp/lock.out" 2>&1; then fail "active lock apply succeeded"; fi
[ "$(tree_digest "$lock_root")" = "$lock_before" ] || fail "active lock blocker wrote state"
grep -Fxq 'decommission_state=blocked' "$tmp/lock.out" || fail "active lock was not blocked"

partial_root=$(setup_target partial)
cat >"$partial_root/bin/rm" <<EOF
#!/bin/sh
case "\$*" in *home-edge-self-heal.sh*) exit 9 ;; esac
exec "$real_rm" "\$@"
EOF
chmod 755 "$partial_root/bin/rm"
if run_decommission "$partial_root" 1 DECOMMISSION >"$tmp/partial.out" 2>&1; then fail "induced helper failure succeeded"; fi
grep -Fxq 'decommission_state=partial' "$tmp/partial.out" || fail "post-mutation failure did not report partial"
grep -Fxq 'failed_action=remove_fixed_helpers' "$tmp/partial.out" || fail "partial state omitted failed action"

echo "decommission_fixture_tests=ok"
