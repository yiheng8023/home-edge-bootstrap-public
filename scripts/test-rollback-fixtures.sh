#!/bin/sh
# Offline behavior tests for router rollback.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-rollback-test.XXXXXX") || exit 1
rollback_lock=$(mktemp -d "/tmp/home-edge-rollback-lock.XXXXXX") || { rm -rf "$tmp_root"; exit 1; }
rmdir "$rollback_lock" || { rm -rf "$tmp_root" "$rollback_lock"; exit 1; }
export ROLLBACK_LOCK_DIR="$rollback_lock"

cleanup() {
  rm -rf "$tmp_root"
  case "$rollback_lock" in /tmp/home-edge-rollback-lock.*) rm -rf "$rollback_lock" ;; esac
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "rollback_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

write_prev_bootstrap() {
  prev="$1"
  cat >"$prev/bootstrap.sh" <<'EOF'
#!/bin/sh
set -u
root="${HOME_EDGE_ROLLBACK_ROOT:-}"
mkdir -p "$root/jffs/scripts"
printf 'restored\n' > "$root/jffs/scripts/bootstrap-applied"
EOF
  chmod 755 "$prev/bootstrap.sh"
}

make_fixture() {
  name="$1"
  root="$tmp_root/$name"
  mkdir -p "$root/jffs/home-edge-bootstrap" "$root/jffs/home-edge-bootstrap.prev" "$root/jffs/scripts" "$root/jffs/ShellCrash"
  printf 'current\n' > "$root/jffs/home-edge-bootstrap/current.txt"
  printf 'previous\n' > "$root/jffs/home-edge-bootstrap.prev/previous.txt"
  printf 'current-runtime\n' > "$root/jffs/ShellCrash/current-runtime.txt"
  write_prev_bootstrap "$root/jffs/home-edge-bootstrap.prev"
  printf '%s\n' "$root"
}

assert_file() {
  [ -f "$1" ] || fail "missing file: $1"
}

assert_not_path() {
  [ ! -e "$1" ] || fail "path should not exist: $1"
}

dry_root=$(make_fixture dry)
HOME_EDGE_ROLLBACK_ROOT="$dry_root" sh "$repo/scripts/rollback-router-state.sh" >"$tmp_root/rollback-dry.log"
assert_file "$dry_root/jffs/home-edge-bootstrap/current.txt"
assert_file "$dry_root/jffs/home-edge-bootstrap.prev/previous.txt"
assert_not_path "$dry_root/jffs/scripts/bootstrap-applied"

apply_root=$(make_fixture apply)
HOME_EDGE_ROLLBACK_ROOT="$apply_root" ROLLBACK_APPLY=1 sh "$repo/scripts/rollback-router-state.sh" >"$tmp_root/rollback-apply.log"
assert_file "$apply_root/jffs/home-edge-bootstrap/previous.txt"
assert_not_path "$apply_root/jffs/home-edge-bootstrap.prev"
assert_file "$apply_root/jffs/scripts/bootstrap-applied"
ls "$apply_root"/jffs/home-edge-bootstrap.rollback.* >/dev/null 2>&1 || fail "missing rollback backup directory"

runtime_root=$(make_fixture runtime)
mkdir -p "$runtime_root/jffs/home-edge-bootstrap-state/backups/runtime/ShellCrash.20260101000000"
printf 'old-runtime\n' > "$runtime_root/jffs/home-edge-bootstrap-state/backups/runtime/ShellCrash.20260101000000/old-runtime.txt"
HOME_EDGE_ROLLBACK_ROOT="$runtime_root" ROLLBACK_APPLY=1 ROLLBACK_RUNTIME=1 sh "$repo/scripts/rollback-router-state.sh" >"$tmp_root/rollback-runtime.log"
assert_file "$runtime_root/jffs/ShellCrash/old-runtime.txt"
ls "$runtime_root"/jffs/home-edge-bootstrap-state/backups/runtime/ShellCrash.rollback-current.* >/dev/null 2>&1 || fail "missing current runtime backup"
grep -Fq 'runtime_backup_dir=/jffs/home-edge-bootstrap-state/backups/runtime' "$tmp_root/rollback-runtime.log" || fail "rollback did not report stable runtime backup root"

if sh "$repo/scripts/rollback-merlin.sh" user@192.0.2.1 --remote-dir /tmp/not-jffs >"$tmp_root/rollback-wrapper.out" 2>"$tmp_root/rollback-wrapper.err"; then
  fail "rollback wrapper should reject remote directories outside /jffs"
fi
grep -q 'under /jffs' "$tmp_root/rollback-wrapper.err" || fail "missing /jffs validation message"

echo "rollback_fixture_tests=ok"
