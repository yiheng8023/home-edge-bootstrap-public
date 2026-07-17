#!/bin/sh
# Offline lifecycle-registration tests for the Merlin adapter.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sut="$repo/scripts/reconcile-self-heal-registration.sh"
tmp=$(mktemp -d "/tmp/home-edge-lifecycle-registration-test.XXXXXX") || exit 1
cleanup() { case "$tmp" in /tmp/home-edge-lifecycle-registration-test.*) rm -rf "$tmp" ;; esac; }
trap cleanup EXIT HUP INT TERM
export HOME_EDGE_WRITE_LOCK_DIR="$tmp/reconcile.lock"

fail() {
  echo "lifecycle_registration_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

[ -s "$sut" ] || fail "missing lifecycle registration reconciler"
REAL_STAT=$(command -v stat) || fail "stat command unavailable"
REAL_CHMOD=$(command -v chmod) || fail "chmod command unavailable"
export REAL_STAT REAL_CHMOD

root="$tmp/root"
fakebin="$tmp/fakebin"
state="$tmp/cru.state"
mkdir -p "$root/jffs/scripts" "$root/jffs/home-edge-bootstrap-state" "$fakebin"
: >"$state"

cat >"$fakebin/cru" <<'EOF'
#!/bin/sh
set -eu
state=${CRU_STATE:?}
case "${1:-}" in
  l)
    cat "$state"
    ;;
  d)
    name=${2:?}
    next="$state.next.$$"
    grep -Fv "#$name#" "$state" >"$next" || true
    mv "$next" "$state"
    ;;
  a)
    name=${2:?}
    job=${3:?}
    if [ -n "${CRU_FAIL_ADD_ONCE_FILE:-}" ] && [ ! -e "$CRU_FAIL_ADD_ONCE_FILE" ]; then
      : >"$CRU_FAIL_ADD_ONCE_FILE"
      exit 9
    fi
    if [ -n "${CRU_CORRUPT_ADD_ONCE_FILE:-}" ] && [ ! -e "$CRU_CORRUPT_ADD_ONCE_FILE" ]; then
      : >"$CRU_CORRUPT_ADD_ONCE_FILE"
      printf '%s extra #%s#\n' "$job" "$name" >>"$state"
      exit 0
    fi
    printf '%s #%s#\n' "$job" "$name" >>"$state"
    ;;
  *)
    echo "unsupported cru operation" >&2
    exit 2
    ;;
esac
EOF
chmod 755 "$fakebin/cru"

cat >"$root/jffs/scripts/home-edge-policy.env" <<'EOF'
HEAL_CRON_DRY_RUN=1
HEAL_CRON_SCHEDULE='*/5 * * * *'
EOF
cat >"$root/jffs/scripts/home-edge-self-heal-cron.sh" <<'EOF'
#!/bin/sh
exit 0
EOF
cat >"$root/jffs/scripts/services-start" <<'EOF'
#!/bin/sh
echo preserved-user-start
EOF
chmod 755 "$root/jffs/scripts/home-edge-self-heal-cron.sh" "$root/jffs/scripts/services-start"
cp "$sut" "$root/jffs/scripts/home-edge-reconcile-self-heal.sh"
chmod 755 "$root/jffs/scripts/home-edge-reconcile-self-heal.sh"

run_reconciler() {
  HOME_EDGE_RECONCILE_ROOT="$root" HOME_EDGE_WRITE_LOCK_DIR="${HOME_EDGE_WRITE_LOCK_DIR:-$tmp/reconcile.lock}" CRU_STATE="$state" PATH="$fakebin:$PATH" \
    sh "$sut" "$@"
}

output=$(run_reconciler --install)
printf '%s\n' "$output" | grep -q '^self_heal_registration_state=ready$' || fail "install did not report ready registration"
printf '%s\n' "$output" | grep -q '^self_heal_boot_hook_state=ready$' || fail "install did not report ready boot hook"
printf '%s\n' "$output" | grep -q '^self_heal_policy_mode=dry_run$' || fail "install did not preserve dry-run policy"
grep -q '^echo preserved-user-start$' "$root/jffs/scripts/services-start" || fail "existing services-start content was not preserved"
[ "$(grep -c '^# BEGIN home-edge-bootstrap self-heal lifecycle$' "$root/jffs/scripts/services-start")" -eq 1 ] || fail "managed hook begin marker count is not one"
[ "$(grep -c '^# END home-edge-bootstrap self-heal lifecycle$' "$root/jffs/scripts/services-start")" -eq 1 ] || fail "managed hook end marker count is not one"
[ "$(grep -c '#home_edge_selfheal#' "$state")" -eq 1 ] || fail "initial reconciliation did not create exactly one cron job"

lock_dir="$tmp/global-write.lock"
mkdir "$lock_dir"
printf '%s\n' "$$" >"$lock_dir/pid"
date +%s >"$lock_dir/started_at"
printf '%s\n' competing-writer >"$lock_dir/operation"
if HOME_EDGE_WRITE_LOCK_DIR="$lock_dir" run_reconciler --reconcile >/dev/null 2>&1; then
  fail "standalone reconciler ignored the global write lock"
fi
HOME_EDGE_WRITE_LOCK_DIR="$lock_dir" HOME_EDGE_WRITE_LOCK_HELD=1 run_reconciler --reconcile >/dev/null || fail "reconciler did not inherit global write lock"
[ "$(grep -c '#home_edge_selfheal#' "$state")" -eq 1 ] || fail "lock inheritance duplicated cron registration"
grep -q '^echo preserved-user-start$' "$root/jffs/scripts/services-start" || fail "lock inheritance lost unrelated hook content"
grep -Fq '*/5 * * * * sh /jffs/scripts/home-edge-self-heal-cron.sh #home_edge_selfheal#' "$state" || fail "cron job does not match policy"
[ "$(stat -c '%a' "$root/jffs/scripts/services-start" 2>/dev/null || stat -f '%Lp' "$root/jffs/scripts/services-start")" = "755" ] || fail "initial executable mode is unexpected"

run_reconciler --install >/dev/null
[ "$(grep -c '^# BEGIN home-edge-bootstrap self-heal lifecycle$' "$root/jffs/scripts/services-start")" -eq 1 ] || fail "reinstall duplicated the managed hook"
[ "$(grep -c '#home_edge_selfheal#' "$state")" -eq 1 ] || fail "reinstall duplicated the cron job"

printf '%s\n' \
  '*/2 * * * * sh /wrong-wrapper.sh #home_edge_selfheal#' \
  '*/7 * * * * sh /another-wrapper.sh #home_edge_selfheal#' >>"$state"
run_reconciler --reconcile >/dev/null

cp "$state" "$tmp/prior-registration.add-failure"
if CRU_FAIL_ADD_ONCE_FILE="$tmp/fail-add.once" run_reconciler --reconcile >"$tmp/fail-add.out" 2>"$tmp/fail-add.err"; then
  fail "cron add failure should return nonzero after rollback"
fi
cmp -s "$state" "$tmp/prior-registration.add-failure" || fail "cron add failure did not restore the exact prior registration"

cp "$state" "$tmp/prior-registration.verify-failure"
if CRU_CORRUPT_ADD_ONCE_FILE="$tmp/corrupt-add.once" run_reconciler --reconcile >"$tmp/corrupt-add.out" 2>"$tmp/corrupt-add.err"; then
  fail "cron verification failure should return nonzero after rollback"
fi
cmp -s "$state" "$tmp/prior-registration.verify-failure" || fail "cron verification failure did not restore the exact prior registration"
[ "$(grep -c '#home_edge_selfheal#' "$state")" -eq 1 ] || fail "duplicate registration was not reduced to one job"
grep -Fq '*/5 * * * * sh /jffs/scripts/home-edge-self-heal-cron.sh #home_edge_selfheal#' "$state" || fail "drifted registration was not repaired"

cat >"$root/jffs/home-edge-bootstrap-state/policy.local" <<'EOF'
HEAL_CRON_DRY_RUN=0
EOF
: >"$state"
boot_output=$(HOME_EDGE_RECONCILE_ROOT="$root" CRU_STATE="$state" PATH="$fakebin:$PATH" sh "$root/jffs/scripts/services-start")
printf '%s\n' "$boot_output" | grep -q '^preserved-user-start$' || fail "boot hook stopped existing services-start behavior"
printf '%s\n' "$boot_output" | grep -q '^self_heal_policy_mode=live$' || fail "boot reconciliation did not preserve live policy"
[ "$(grep -c '#home_edge_selfheal#' "$state")" -eq 1 ] || fail "boot reconciliation did not restore exactly one cron job"

cat >"$root/jffs/scripts/services-start" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 700 "$root/jffs/scripts/services-start"
mode_log="$tmp/mode.log"
cat >"$fakebin/stat" <<'EOF'
#!/bin/sh
case "$*" in
  *services-start*) printf '%s\n' 700 ;;
  *) exec "${REAL_STAT:?}" "$@" ;;
esac
EOF
cat >"$fakebin/chmod" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${MODE_LOG:?}"
exec "${REAL_CHMOD:?}" "$@"
EOF
chmod 755 "$fakebin/stat" "$fakebin/chmod"
export MODE_LOG="$mode_log"
run_reconciler --install >/dev/null
: >"$state"
HOME_EDGE_RECONCILE_ROOT="$root" CRU_STATE="$state" PATH="$fakebin:$PATH" sh "$root/jffs/scripts/services-start"
[ "$(grep -c '#home_edge_selfheal#' "$state")" -eq 1 ] || fail "managed hook did not execute before preserved terminal content"
grep -Eq '^700 .*services-start\.tmp\.[0-9]+$' "$mode_log" || fail "existing restrictive services-start mode was not restored"
if grep -Eq '^7[1-7][1-7] .*services-start\.tmp\.[0-9]+$' "$mode_log"; then
  fail "existing restrictive services-start mode was widened"
fi

canonical_hook="$root/jffs/scripts/services-start"
sed 's/  HOME_EDGE_RECONCILE_ROOT=/  # HOME_EDGE_RECONCILE_ROOT=/' "$canonical_hook" >"$tmp/commented-hook"
mv "$tmp/commented-hook" "$canonical_hook"
chmod 700 "$canonical_hook"
status_output=$(run_reconciler --status)
printf '%s\n' "$status_output" | grep -q '^self_heal_boot_hook_state=drifted$' || fail "commented canonical hook was not reported drifted"
run_reconciler --install >/dev/null

canonical_block="$tmp/canonical.block"
awk '/^# BEGIN home-edge-bootstrap self-heal lifecycle$/ { capture=1 } capture { print } /^# END home-edge-bootstrap self-heal lifecycle$/ && capture { exit }' "$canonical_hook" >"$canonical_block"
cat >"$tmp/relocated-hook" <<'EOF'
#!/bin/sh
exit 0
EOF
cat "$canonical_block" >>"$tmp/relocated-hook"
mv "$tmp/relocated-hook" "$canonical_hook"
chmod 700 "$canonical_hook"
status_output=$(run_reconciler --status)
printf '%s\n' "$status_output" | grep -q '^self_heal_boot_hook_state=drifted$' || fail "canonical hook below terminal content was not reported drifted"
run_reconciler --install >/dev/null

sed 's/ --boot/ --boot extra/' "$canonical_hook" >"$tmp/extended-hook"
mv "$tmp/extended-hook" "$canonical_hook"
chmod 700 "$canonical_hook"
status_output=$(run_reconciler --status)
printf '%s\n' "$status_output" | grep -q '^self_heal_boot_hook_state=drifted$' || fail "extended canonical hook was not reported drifted"
run_reconciler --install >/dev/null
printf '%s\n' '*/5 * * * * sh /jffs/scripts/home-edge-self-heal-cron.sh extra #home_edge_selfheal#' >"$state"
status_output=$(run_reconciler --status)
printf '%s\n' "$status_output" | grep -q '^self_heal_registration_state=drifted$' || fail "extended cron command was not reported drifted"
run_reconciler --reconcile >/dev/null

cp "$root/jffs/scripts/services-start" "$tmp/services-start.good"
cat >>"$root/jffs/scripts/services-start" <<'EOF'
# BEGIN home-edge-bootstrap self-heal lifecycle
EOF
if run_reconciler --install >"$tmp/malformed.out" 2>"$tmp/malformed.err"; then
  fail "malformed managed hook should be rejected"
fi
grep -q 'unbalanced managed lifecycle markers' "$tmp/malformed.err" || fail "malformed hook rejection message missing"
{ head -n -1 "$root/jffs/scripts/services-start" 2>/dev/null || sed '$d' "$root/jffs/scripts/services-start"; } >"$tmp/services-start.after-malformed"
cmp -s "$tmp/services-start.good" "$tmp/services-start.after-malformed" || fail "malformed hook rejection overwrote user content"

cat >"$root/jffs/scripts/services-start" <<'EOF'
#!/bin/sh
echo preserved-before-reversed-markers
# END home-edge-bootstrap self-heal lifecycle
echo preserved-between-reversed-markers
# BEGIN home-edge-bootstrap self-heal lifecycle
echo preserved-after-reversed-markers
EOF
cp "$root/jffs/scripts/services-start" "$tmp/services-start.reversed"
if run_reconciler --install >"$tmp/reversed.out" 2>"$tmp/reversed.err"; then
  fail "reversed managed hook markers should be rejected"
fi
grep -q 'invalid managed lifecycle marker order' "$tmp/reversed.err" || fail "reversed marker rejection message missing"
cmp -s "$root/jffs/scripts/services-start" "$tmp/services-start.reversed" || fail "reversed marker rejection overwrote user content"

echo "lifecycle_registration_fixture_tests=ok"
