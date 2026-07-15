#!/bin/sh
# Offline regression tests for bundle integrity and archive safety.
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-bundle-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

fail() {
  echo "bundle_fixture_tests=failed" >&2
  echo "$*" >&2
  exit 1
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

write_sums() {
  dir="$1"
  {
    printf '%s  mihomo-linux-arm64\n' "$(hash_file "$dir/mihomo-linux-arm64")"
    printf '%s  ShellCrash.tar.gz\n' "$(hash_file "$dir/ShellCrash.tar.gz")"
  } >"$dir/SHA256SUMS"
}

source_dir="$tmp/source"
mkdir -p "$source_dir/libs" "$source_dir/starts"
for file in init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh; do
  printf '#!/bin/sh\nexit 0\n' >"$source_dir/$file"
done

safe="$tmp/safe"
mkdir -p "$safe"
printf '\177ELFfixture\n' >"$safe/mihomo-linux-arm64"
(
  cd "$source_dir"
  tar -czf "$safe/ShellCrash.tar.gz" init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh
)
write_sums "$safe"
sh "$repo/scripts/verify-bundle.sh" "$safe" >"$tmp/safe.out" 2>"$tmp/safe.err" || {
  cat "$tmp/safe.err" >&2
  fail "safe fixture bundle was rejected"
}
grep -q 'verify-bundle: OK' "$tmp/safe.out" || fail "safe bundle did not report OK"

bad_hash="$tmp/bad-hash"
mkdir -p "$bad_hash"
cp "$safe/mihomo-linux-arm64" "$safe/ShellCrash.tar.gz" "$safe/SHA256SUMS" "$bad_hash/"
printf 'tamper\n' >>"$bad_hash/mihomo-linux-arm64"
if sh "$repo/scripts/verify-bundle.sh" "$bad_hash" >"$tmp/bad-hash.out" 2>"$tmp/bad-hash.err"; then
  fail "digest mismatch should fail bundle verification"
fi
grep -q 'SHA256SUMS check failed' "$tmp/bad-hash.err" || fail "digest mismatch message missing"

unsafe_source="$tmp/unsafe-source"
cp -R "$source_dir" "$unsafe_source"
if ln -s /etc/passwd "$unsafe_source/unsafe-link" 2>/dev/null; then
  unsafe="$tmp/unsafe-link"
  mkdir -p "$unsafe"
  cp "$safe/mihomo-linux-arm64" "$unsafe/"
  (
    cd "$unsafe_source"
    tar -czf "$unsafe/ShellCrash.tar.gz" init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh unsafe-link
  )
  write_sums "$unsafe"
  if sh "$repo/scripts/verify-bundle.sh" "$unsafe" >"$tmp/unsafe.out" 2>"$tmp/unsafe.err"; then
    fail "archive symbolic link should fail bundle verification"
  fi
  grep -q 'links, special files' "$tmp/unsafe.err" || fail "unsafe archive type message missing"
fi

echo "bundle_fixture_tests=ok"
