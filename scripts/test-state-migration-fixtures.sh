#!/bin/sh
# Offline contract tests for stable Merlin state migration.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_base=${TMPDIR:-/tmp}
[ "$tmp_base" = "/" ] || tmp_base=${tmp_base%/}
tmp=$(mktemp -d "$tmp_base/home-edge-state-migration-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
find_cmd=$(command -v find) || exit 1
[ ! -x /usr/bin/find ] || find_cmd=/usr/bin/find
sort_cmd=$(command -v sort) || exit 1
[ ! -x /usr/bin/sort ] || sort_cmd=/usr/bin/sort

fail() {
  echo "state_migration_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

hash_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
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

new_root() {
  root="$tmp/$1"
  mkdir -p "$root/jffs/home-edge-bootstrap" "$root/jffs/scripts"
  printf '%s\n' "$root"
}

migrator="$repo/scripts/migrate-router-state.sh"
[ -f "$migrator" ] || fail "missing router-state migrator"

run_migration() {
  root=$1
  apply=$2
  HOME_EDGE_STATE_FIXTURE_ROOT="$root" \
  HOME_EDGE_STATE_ROOT=/jffs/home-edge-bootstrap-state \
  HOME_EDGE_INSTALL_DIR=/jffs/home-edge-bootstrap \
  HOME_EDGE_SCRIPT_DIR=/jffs/scripts \
  HOME_EDGE_STATE_APPLY="$apply" \
  sh "$migrator"
}

plan_root=$(new_root plan)
printf '%s\n' 'https://credential.invalid/secret-token' >"$plan_root/jffs/home-edge-bootstrap/SUBSCRIPTION.local"
plan_before=$(tree_digest "$plan_root")
run_migration "$plan_root" 0 >"$tmp/plan.out"
plan_after=$(tree_digest "$plan_root")
[ "$plan_before" = "$plan_after" ] || fail "plan mode wrote target state"
grep -Fxq 'state_schema_version=1' "$tmp/plan.out" || fail "plan omitted schema version"
grep -Fxq 'state_migration_state=needed' "$tmp/plan.out" || fail "plan did not report needed"
grep -Fxq 'stable_state_root=/jffs/home-edge-bootstrap-state' "$tmp/plan.out" || fail "plan omitted stable root"
grep -Fxq 'next_action_code=apply_state_migration' "$tmp/plan.out" || fail "plan omitted next action"
! grep -Fq 'credential.invalid' "$tmp/plan.out" || fail "plan leaked subscription content"

apply_root=$(new_root apply)
printf '%s\n' 'https://credential.invalid/apply-token' >"$apply_root/jffs/home-edge-bootstrap/SUBSCRIPTION.local"
printf '%s\n' 'SITE_VALUE=preserved' >"$apply_root/jffs/home-edge-bootstrap/policy.local"
mkdir -p "$apply_root/jffs/home-edge-bootstrap/cache" \
  "$apply_root/jffs/home-edge-bootstrap/backups/subscription" \
  "$apply_root/jffs/home-edge-bootstrap/backups/runtime/ShellCrash.fixture"
printf '%s\n' 'cache: true' >"$apply_root/jffs/home-edge-bootstrap/cache/subscription.yaml"
printf '%s\n' 'backup: true' >"$apply_root/jffs/home-edge-bootstrap/backups/subscription/subscription.1.yaml"
printf '%s\n' 'runtime-backup' >"$apply_root/jffs/home-edge-bootstrap/backups/runtime/ShellCrash.fixture/state"
cp -p "$apply_root/jffs/home-edge-bootstrap/SUBSCRIPTION.local" "$tmp/apply-subscription.before"
cp -p "$apply_root/jffs/home-edge-bootstrap/policy.local" "$tmp/apply-policy.before"
run_migration "$apply_root" 1 >"$tmp/apply.out"
grep -Fxq 'state_migration_state=ready' "$tmp/apply.out" || fail "apply did not report ready"
grep -Fxq 'compatibility_bridge_state=ready' "$tmp/apply.out" || fail "apply did not report bridge ready"
cmp "$tmp/apply-subscription.before" "$apply_root/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local" >/dev/null || fail "subscription bytes changed"
cmp "$tmp/apply-policy.before" "$apply_root/jffs/home-edge-bootstrap-state/policy.local" >/dev/null || fail "policy bytes changed"
cmp "$apply_root/jffs/home-edge-bootstrap/cache/subscription.yaml" "$apply_root/jffs/home-edge-bootstrap-state/cache/subscription.yaml" >/dev/null || fail "cache was not migrated"
cmp "$apply_root/jffs/home-edge-bootstrap/backups/subscription/subscription.1.yaml" "$apply_root/jffs/home-edge-bootstrap-state/backups/subscription/subscription.1.yaml" >/dev/null || fail "subscription backup was not migrated"
cmp "$apply_root/jffs/home-edge-bootstrap/backups/runtime/ShellCrash.fixture/state" "$apply_root/jffs/home-edge-bootstrap-state/backups/runtime/ShellCrash.fixture/state" >/dev/null || fail "runtime backup was not migrated"
grep -Fxq '# home-edge-bootstrap-owned: stable-state-compatibility/v1' "$apply_root/jffs/scripts/home-edge-policy.local" || fail "compatibility bridge marker missing"
grep -Fxq 'state_schema_version=1' "$apply_root/jffs/home-edge-bootstrap-state/lifecycle/state.env" || fail "state metadata missing"
! grep -Fq 'credential.invalid' "$tmp/apply.out" || fail "apply leaked subscription content"

bridge_for_fixture="$tmp/bridge-for-fixture.sh"
sed "s#/jffs#$apply_root/jffs#g" "$apply_root/jffs/scripts/home-edge-policy.local" >"$bridge_for_fixture"
unset SUBSCRIPTION_FILE SUBSCRIPTION_CACHE SUBSCRIPTION_BACKUP_DIR SITE_VALUE || true
. "$bridge_for_fixture"
[ "$SUBSCRIPTION_FILE" = "$apply_root/jffs/home-edge-bootstrap-state/SUBSCRIPTION.local" ] || fail "bridge did not redirect subscription file"
[ "$SUBSCRIPTION_CACHE" = "$apply_root/jffs/home-edge-bootstrap-state/cache/subscription.yaml" ] || fail "bridge did not redirect subscription cache"
[ "$SUBSCRIPTION_BACKUP_DIR" = "$apply_root/jffs/home-edge-bootstrap-state/backups/subscription" ] || fail "bridge did not redirect subscription backups"
[ "$SITE_VALUE" = preserved ] || fail "bridge did not source stable policy"

apply_first=$(tree_digest "$apply_root")
run_migration "$apply_root" 1 >"$tmp/apply-second.out"
apply_second=$(tree_digest "$apply_root")
[ "$apply_first" = "$apply_second" ] || fail "second migration was not idempotent"
grep -Fxq 'state_migration_state=ready' "$tmp/apply-second.out" || fail "idempotent retry was not ready"

duplicate_root=$(new_root duplicate)
printf '%s\n' 'HEAL_CRON_DRY_RUN=1' >"$duplicate_root/jffs/home-edge-bootstrap/policy.local"
cp -p "$duplicate_root/jffs/home-edge-bootstrap/policy.local" "$duplicate_root/jffs/scripts/home-edge-policy.local"
run_migration "$duplicate_root" 1 >"$tmp/duplicate.out"
cmp "$duplicate_root/jffs/home-edge-bootstrap/policy.local" "$duplicate_root/jffs/home-edge-bootstrap-state/policy.local" >/dev/null || fail "identical policy sources did not migrate"

conflict_root=$(new_root conflict)
mkdir -p "$conflict_root/jffs/home-edge-bootstrap-state"
printf '%s\n' 'SITE_VALUE=legacy' >"$conflict_root/jffs/home-edge-bootstrap/policy.local"
printf '%s\n' 'SITE_VALUE=canonical' >"$conflict_root/jffs/home-edge-bootstrap-state/policy.local"
conflict_before=$(tree_digest "$conflict_root")
set +e
run_migration "$conflict_root" 1 >"$tmp/conflict.out" 2>&1
conflict_status=$?
set -e
[ "$conflict_status" -ne 0 ] || fail "divergent policy conflict succeeded"
grep -Fxq 'state_migration_state=conflict' "$tmp/conflict.out" || fail "divergent policy was not classified as conflict"
conflict_after=$(tree_digest "$conflict_root")
[ "$conflict_before" = "$conflict_after" ] || fail "conflict path wrote target state"
! grep -Fq 'SITE_VALUE=' "$tmp/conflict.out" || fail "conflict output leaked policy content"

symlink_root=$(new_root symlink)
printf '%s\n' 'outside-secret' >"$tmp/outside-secret"
if ln -s "$tmp/outside-secret" "$symlink_root/jffs/home-edge-bootstrap/SUBSCRIPTION.local" 2>/dev/null && \
  [ -L "$symlink_root/jffs/home-edge-bootstrap/SUBSCRIPTION.local" ]; then
  symlink_before=$(tree_digest "$symlink_root")
  set +e
  run_migration "$symlink_root" 1 >"$tmp/symlink.out" 2>&1
  symlink_status=$?
  set -e
  [ "$symlink_status" -ne 0 ] || fail "symbolic-link source succeeded"
  grep -Fxq 'state_migration_state=blocked' "$tmp/symlink.out" || fail "symbolic-link source was not blocked"
  symlink_after=$(tree_digest "$symlink_root")
  [ "$symlink_before" = "$symlink_after" ] || fail "blocked symbolic-link path wrote state"
  grep -Fxq 'outside-secret' "$tmp/outside-secret" || fail "outside symlink target changed"
else
  rm -f "$symlink_root/jffs/home-edge-bootstrap/SUBSCRIPTION.local"
fi

echo "state_migration_fixture_tests=ok"
