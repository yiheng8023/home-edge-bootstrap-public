#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
sut="$repo/scripts/start-shellcrash-at-boot.sh"
tmp=$(mktemp -d "/tmp/home-edge-shellcrash-boot-test.XXXXXX") || exit 1
cleanup() { case "$tmp" in /tmp/home-edge-shellcrash-boot-test.*) rm -rf "$tmp" ;; esac; }
trap cleanup EXIT HUP INT TERM

fail() {
  echo "shellcrash_boot_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

[ -s "$sut" ] || fail "missing ShellCrash boot starter"
grep -Fq 'HOME_EDGE_SHELLCRASH_BOOT_DELAY:-90' "$sut" ||
  fail "default boot recovery delay must remain behind the native 60-second start"

fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat >"$fakebin/pidof" <<'EOF'
#!/bin/sh
[ "${PIDOF_RUNNING:-0}" = "1" ] || exit 1
printf '%s\n' 4242
EOF
chmod 755 "$fakebin/pidof"

make_root() {
  name="$1"
  root="$tmp/$name"
  mkdir -p "$root/jffs/ShellCrash/task" "$root/jffs/home-edge-bootstrap-state/runtime"
  cat >"$root/jffs/ShellCrash/start.sh" <<EOF
#!/bin/sh
printf '%s\n' start >>"$root/start.count"
exit 0
EOF
  chmod 755 "$root/jffs/ShellCrash/start.sh"
  : >"$root/jffs/ShellCrash/task/bfstart"
  : >"$root/jffs/ShellCrash/task/afstart"
  printf '%s\n' protected-core >"$root/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz"
  printf '%s\n' "$root"
}

run_starter() {
  root="$1"
  shift
  PATH="$fakebin:$PATH" \
    PIDOF_RUNNING="${PIDOF_RUNNING:-0}" \
    HOME_EDGE_SHELLCRASH_DIR="$root/jffs/ShellCrash" \
    HOME_EDGE_STATE_ROOT="$root/jffs/home-edge-bootstrap-state" \
    HOME_EDGE_SHELLCRASH_BOOT_DELAY=0 \
    HOME_EDGE_SHELLCRASH_BOOT_LOCK="$root/boot.lock" \
    HOME_EDGE_SHELLCRASH_BOOT_LOG="$root/boot.log" \
    "$@" sh "$sut"
}

already=$(make_root already)
PIDOF_RUNNING=1 run_starter "$already"
[ ! -e "$already/start.count" ] || fail "already-running core was restarted"
grep -q 'state=ready reason=already_running' "$already/boot.log" ||
  fail "already-running state was not reported"

unsafe=$(make_root unsafe)
printf '%s\n' '/jffs/ShellCrash/task/task.sh 101 服务启动前启动ShellCrash服务' >"$unsafe/jffs/ShellCrash/task/bfstart"
if PIDOF_RUNNING=0 run_starter "$unsafe"; then
  fail "recursive startup task should block boot recovery"
fi
[ ! -e "$unsafe/start.count" ] || fail "unsafe automatic tasks still dispatched startup"
grep -q 'state=blocked reason=unsafe_automatic_tasks' "$unsafe/boot.log" ||
  fail "unsafe automatic task reason was not reported"

disabled=$(make_root disabled)
: >"$disabled/jffs/ShellCrash/.dis_startup"
PIDOF_RUNNING=0 run_starter "$disabled"
[ ! -e "$disabled/start.count" ] || fail "manual disable marker was ignored"
grep -q 'state=skipped reason=manually_disabled' "$disabled/boot.log" ||
  fail "manual disable state was not reported"

prior_error=$(make_root prior-error)
: >"$prior_error/jffs/ShellCrash/.start_error"
PIDOF_RUNNING=0 run_starter "$prior_error"
[ ! -e "$prior_error/start.count" ] || fail "prior start error marker was ignored"
grep -q 'state=skipped reason=prior_start_error' "$prior_error/boot.log" ||
  fail "prior start error state was not reported"

recovery=$(make_root recovery)
PIDOF_RUNNING=0 run_starter "$recovery"
[ "$(wc -l <"$recovery/start.count")" -eq 1 ] || fail "boot recovery did not dispatch exactly once"
[ -s "$recovery/jffs/ShellCrash/CrashCore.gz" ] || fail "protected core was not restored"
cmp -s \
  "$recovery/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz" \
  "$recovery/jffs/ShellCrash/CrashCore.gz" ||
  fail "restored ShellCrash core differs from protected source"
[ ! -e "$recovery/boot.lock" ] || fail "boot lock remained after dispatch"
grep -q 'state=dispatched' "$recovery/boot.log" || fail "dispatch state was not reported"

locked=$(make_root locked)
mkdir "$locked/boot.lock"
PIDOF_RUNNING=0 run_starter "$locked"
[ ! -e "$locked/start.count" ] || fail "existing boot lock was ignored"
grep -q 'state=skipped reason=start_already_in_progress' "$locked/boot.log" ||
  fail "existing boot lock state was not reported"

echo "shellcrash_boot_fixture_tests=ok"
