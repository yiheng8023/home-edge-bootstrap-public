#!/bin/sh
set -eu

repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-data-test.XXXXXX") || exit 1
trap 'case "$tmp" in */home-edge-data-test.*) rm -rf "$tmp" ;; esac' EXIT HUP INT TERM

fail() {
  echo "shellcrash_data_fixture_tests=failed"
  echo "$*" >&2
  exit 1
}

shellcrash="$tmp/ShellCrash"
state="$tmp/state"
mkdir -p "$shellcrash/ruleset" "$state"
printf 'country-fixture\n' >"$shellcrash/Country.mmdb"
printf 'cn-mrs-fixture\n' >"$shellcrash/ruleset/cn.mrs"

sha256_of() {
  sha256sum "$1" | awk '{print $1}'
}

run_data() {
  HOME_EDGE_SHELLCRASH_DIR="$shellcrash" \
  HOME_EDGE_STATE_ROOT="$state" \
  HOME_EDGE_COUNTRY_SHA256="$(sha256_of "$shellcrash/Country.mmdb")" \
  HOME_EDGE_COUNTRY_BYTES="$(wc -c <"$shellcrash/Country.mmdb" | tr -d ' ')" \
  HOME_EDGE_CN_MRS_SHA256="$(sha256_of "$shellcrash/ruleset/cn.mrs")" \
  HOME_EDGE_CN_MRS_BYTES="$(wc -c <"$shellcrash/ruleset/cn.mrs" | tr -d ' ')" \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  "$@" sh "$repo/scripts/prefetch-shellcrash-data.sh"
}

ready_output=$(run_data env HOME_EDGE_DATA_ACTION=status)
printf '%s\n' "$ready_output" | grep -q '^country_data_state=ready$' ||
  fail "ready Country.mmdb was not recognized"
printf '%s\n' "$ready_output" | grep -q '^cn_mrs_data_state=ready$' ||
  fail "ready cn.mrs was not recognized"
printf '%s\n' "$ready_output" | grep -q '^shellcrash_data_state=ready$' ||
  fail "ready summary was not reported"

missing_root="$tmp/missing"
mkdir -p "$missing_root/ShellCrash/ruleset" "$missing_root/state"
if HOME_EDGE_SHELLCRASH_DIR="$missing_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$missing_root/state" \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  HOME_EDGE_DATA_ACTION=plan \
  sh "$repo/scripts/prefetch-shellcrash-data.sh" \
    >"$tmp/missing-pin.out" 2>"$tmp/missing-pin.err"; then
  fail "plan accepted missing SHA-256 pins"
fi
grep -q '^shellcrash_data_pin_state=missing$' "$tmp/missing-pin.out" ||
  fail "missing pin classification was not reported"
grep -q '^shellcrash_data_state=blocked$' "$tmp/missing-pin.out" ||
  fail "missing pin did not block the plan"

pin_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
pin_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
if HOME_EDGE_SHELLCRASH_DIR="$missing_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$missing_root/state" \
  HOME_EDGE_COUNTRY_SHA256="$pin_a" \
  HOME_EDGE_CN_MRS_SHA256="$pin_b" \
  HOME_EDGE_COUNTRY_URL='http://downloads.example/Country.mmdb' \
  HOME_EDGE_CN_MRS_URL='https://downloads.example/cn.mrs' \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  HOME_EDGE_DATA_ACTION=plan \
  sh "$repo/scripts/prefetch-shellcrash-data.sh" \
    >"$tmp/non-https.out" 2>"$tmp/non-https.err"; then
  fail "plan accepted a non-HTTPS source"
fi
grep -q '^shellcrash_data_source_state=invalid$' "$tmp/non-https.out" ||
  fail "non-HTTPS source classification was not reported"
grep -q '^shellcrash_data_state=blocked$' "$tmp/non-https.out" ||
  fail "non-HTTPS source did not block the plan"
! grep -Fq 'downloads.example' "$tmp/non-https.out" ||
  fail "source URL leaked into plan output"
! grep -Fq 'downloads.example' "$tmp/non-https.err" ||
  fail "source URL leaked into plan diagnostics"

fake_df="$tmp/fake-df"
cat >"$fake_df" <<'EOF'
#!/bin/sh
printf '%s\n' \
  'Filesystem 1024-blocks Used Available Capacity Mounted on' \
  '/dev/fixture 1024 1023 1 100% /jffs'
EOF
chmod 755 "$fake_df"
fake_df_ample="$tmp/fake-df-ample"
cat >"$fake_df_ample" <<'EOF'
#!/bin/sh
printf '%s\n' \
  'Filesystem 1024-blocks Used Available Capacity Mounted on' \
  '/dev/fixture 1048576 1 1048575 1% /jffs'
EOF
chmod 755 "$fake_df_ample"
if HOME_EDGE_SHELLCRASH_DIR="$missing_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$missing_root/state" \
  HOME_EDGE_COUNTRY_SHA256="$pin_a" \
  HOME_EDGE_CN_MRS_SHA256="$pin_b" \
  HOME_EDGE_COUNTRY_URL='https://downloads.example/Country.mmdb' \
  HOME_EDGE_CN_MRS_URL='https://downloads.example/cn.mrs' \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_DATA_SPACE_BUFFER_KIB=4 \
  HOME_EDGE_DATA_DF_BIN="$fake_df" \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  HOME_EDGE_DATA_ACTION=plan \
  sh "$repo/scripts/prefetch-shellcrash-data.sh" \
    >"$tmp/space.out" 2>"$tmp/space.err"; then
  fail "plan accepted insufficient JFFS space"
fi
grep -q '^shellcrash_data_space_state=insufficient$' "$tmp/space.out" ||
  fail "insufficient-space classification was not reported"
grep -q '^shellcrash_data_state=blocked$' "$tmp/space.out" ||
  fail "insufficient space did not block the plan"

default_plan_output=$(
  HOME_EDGE_SHELLCRASH_DIR="$missing_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$missing_root/state" \
  HOME_EDGE_COUNTRY_SHA256="$pin_a" \
  HOME_EDGE_CN_MRS_SHA256="$pin_b" \
  HOME_EDGE_COUNTRY_URL='https://downloads.example/Country.mmdb' \
  HOME_EDGE_CN_MRS_URL='https://downloads.example/cn.mrs' \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_DATA_SPACE_BUFFER_KIB=1 \
  HOME_EDGE_DATA_DF_BIN="$fake_df_ample" \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  sh "$repo/scripts/prefetch-shellcrash-data.sh"
)
printf '%s\n' "$default_plan_output" | grep -q '^shellcrash_data_state=planned$' ||
  fail "default action did not produce a plan"
[ ! -e "$missing_root/ShellCrash/Country.mmdb" ] ||
  fail "default plan changed Country.mmdb"
[ ! -e "$missing_root/ShellCrash/ruleset/cn.mrs" ] ||
  fail "default plan changed cn.mrs"

failure_root="$tmp/download-failure"
mkdir -p "$failure_root/ShellCrash/ruleset" "$failure_root/state"
printf 'old-country\n' >"$failure_root/ShellCrash/Country.mmdb"
printf 'old-cn\n' >"$failure_root/ShellCrash/ruleset/cn.mrs"
old_country_sha=$(sha256_of "$failure_root/ShellCrash/Country.mmdb")
old_cn_sha=$(sha256_of "$failure_root/ShellCrash/ruleset/cn.mrs")
printf 'new-country-payload\n' >"$tmp/new-country"
printf 'new-cn-payload\n' >"$tmp/new-cn"
new_country_sha=$(sha256_of "$tmp/new-country")
new_cn_sha=$(sha256_of "$tmp/new-cn")
fake_curl_fail="$tmp/fake-curl-fail"
cat >"$fake_curl_fail" <<'EOF'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = --config ] && [ "$2" = - ] || exit 64
config=$(cat)
printf '%s\n' "$config" | grep -q '^connect-timeout = 3$' || exit 64
printf '%s\n' "$config" | grep -q '^max-time = 7$' || exit 64
printf '%s\n' "$config" | grep -q '^proto = "=https"$' || exit 64
printf '%s\n' "$config" | grep -q '^proto-redir = "=https"$' || exit 64
exit 28
EOF
chmod 755 "$fake_curl_fail"
if HOME_EDGE_SHELLCRASH_DIR="$failure_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$failure_root/state" \
  HOME_EDGE_COUNTRY_SHA256="$new_country_sha" \
  HOME_EDGE_CN_MRS_SHA256="$new_cn_sha" \
  HOME_EDGE_COUNTRY_URL='https://downloads.example/Country.mmdb' \
  HOME_EDGE_CN_MRS_URL='https://downloads.example/cn.mrs' \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_DATA_SPACE_BUFFER_KIB=1 \
  HOME_EDGE_DATA_DF_BIN="$fake_df_ample" \
  HOME_EDGE_DATA_CURL_BIN="$fake_curl_fail" \
  HOME_EDGE_DATA_CONNECT_TIMEOUT=3 \
  HOME_EDGE_DATA_TOTAL_TIMEOUT=7 \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  HOME_EDGE_DATA_ACTION=apply \
  sh "$repo/scripts/prefetch-shellcrash-data.sh" \
    >"$tmp/download-failure.out" 2>"$tmp/download-failure.err"; then
  fail "apply accepted a failed or timed-out download"
fi
grep -q '^shellcrash_data_download_state=failed$' "$tmp/download-failure.out" ||
  fail "download failure classification was not reported"
[ "$(sha256_of "$failure_root/ShellCrash/Country.mmdb")" = "$old_country_sha" ] ||
  fail "failed download changed Country.mmdb"
[ "$(sha256_of "$failure_root/ShellCrash/ruleset/cn.mrs")" = "$old_cn_sha" ] ||
  fail "failed download changed cn.mrs"

fake_curl_bad="$tmp/fake-curl-bad"
cat >"$fake_curl_bad" <<'EOF'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = --config ] && [ "$2" = - ] || exit 64
config=$(cat)
out=$(printf '%s\n' "$config" | sed -n 's/^output = "\(.*\)"$/\1/p' | head -n 1)
[ -n "$out" ] || exit 64
printf 'wrong-payload\n' >"$out"
EOF
chmod 755 "$fake_curl_bad"
if HOME_EDGE_SHELLCRASH_DIR="$failure_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$failure_root/state" \
  HOME_EDGE_COUNTRY_SHA256="$new_country_sha" \
  HOME_EDGE_CN_MRS_SHA256="$new_cn_sha" \
  HOME_EDGE_COUNTRY_URL='https://downloads.example/Country.mmdb' \
  HOME_EDGE_CN_MRS_URL='https://downloads.example/cn.mrs' \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_DATA_SPACE_BUFFER_KIB=1 \
  HOME_EDGE_DATA_DF_BIN="$fake_df_ample" \
  HOME_EDGE_DATA_CURL_BIN="$fake_curl_bad" \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  HOME_EDGE_DATA_ACTION=apply \
  sh "$repo/scripts/prefetch-shellcrash-data.sh" \
    >"$tmp/bad-digest.out" 2>"$tmp/bad-digest.err"; then
  fail "apply accepted a downloaded payload with the wrong digest"
fi
grep -q '^shellcrash_data_validation_state=failed$' "$tmp/bad-digest.out" ||
  fail "downloaded digest failure classification was not reported"
[ "$(sha256_of "$failure_root/ShellCrash/Country.mmdb")" = "$old_country_sha" ] ||
  fail "bad digest changed Country.mmdb"
[ "$(sha256_of "$failure_root/ShellCrash/ruleset/cn.mrs")" = "$old_cn_sha" ] ||
  fail "bad digest changed cn.mrs"

fake_curl_ok="$tmp/fake-curl-ok"
cat >"$fake_curl_ok" <<'EOF'
#!/bin/sh
[ "$#" -eq 2 ] && [ "$1" = --config ] && [ "$2" = - ] || exit 64
config=$(cat)
out=$(printf '%s\n' "$config" | sed -n 's/^output = "\(.*\)"$/\1/p' | head -n 1)
url=$(printf '%s\n' "$config" | sed -n 's/^url = "\(.*\)"$/\1/p' | head -n 1)
[ -n "$out" ] && [ -n "$url" ] || exit 64
case "$url" in
  */Country.mmdb) cp "$DATA_FIXTURE_COUNTRY" "$out" ;;
  */cn.mrs) cp "$DATA_FIXTURE_CN_MRS" "$out" ;;
  *) exit 65 ;;
esac
EOF
chmod 755 "$fake_curl_ok"
success_output=$(
  DATA_FIXTURE_COUNTRY="$tmp/new-country" \
  DATA_FIXTURE_CN_MRS="$tmp/new-cn" \
  HOME_EDGE_SHELLCRASH_DIR="$failure_root/ShellCrash" \
  HOME_EDGE_STATE_ROOT="$failure_root/state" \
  HOME_EDGE_COUNTRY_SHA256="$new_country_sha" \
  HOME_EDGE_COUNTRY_BYTES="$(wc -c <"$tmp/new-country" | tr -d ' ')" \
  HOME_EDGE_CN_MRS_SHA256="$new_cn_sha" \
  HOME_EDGE_CN_MRS_BYTES="$(wc -c <"$tmp/new-cn" | tr -d ' ')" \
  HOME_EDGE_COUNTRY_URL='https://downloads.example/Country.mmdb' \
  HOME_EDGE_CN_MRS_URL='https://downloads.example/cn.mrs' \
  HOME_EDGE_COUNTRY_MIN_BYTES=1 \
  HOME_EDGE_COUNTRY_MAX_BYTES=1024 \
  HOME_EDGE_CN_MRS_MIN_BYTES=1 \
  HOME_EDGE_CN_MRS_MAX_BYTES=1024 \
  HOME_EDGE_DATA_SPACE_BUFFER_KIB=1 \
  HOME_EDGE_DATA_DF_BIN="$fake_df_ample" \
  HOME_EDGE_DATA_CURL_BIN="$fake_curl_ok" \
  HOME_EDGE_SECURE_TEMP_HELPER="$repo/scripts/home-edge-secure-temp.sh" \
  HOME_EDGE_DATA_ACTION=apply \
  sh "$repo/scripts/prefetch-shellcrash-data.sh"
)
printf '%s\n' "$success_output" | grep -q '^shellcrash_data_commit_state=committed$' ||
  fail "successful apply did not report a committed transaction"
printf '%s\n' "$success_output" | grep -q '^shellcrash_data_state=ready$' ||
  fail "successful apply did not report ready"
[ "$(sha256_of "$failure_root/ShellCrash/Country.mmdb")" = "$new_country_sha" ] ||
  fail "successful apply did not commit Country.mmdb"
[ "$(sha256_of "$failure_root/ShellCrash/ruleset/cn.mrs")" = "$new_cn_sha" ] ||
  fail "successful apply did not commit cn.mrs"
[ "$(stat -c '%a' "$failure_root/ShellCrash/Country.mmdb")" = 644 ] ||
  fail "Country.mmdb permissions are not 0644"
[ "$(stat -c '%a' "$failure_root/ShellCrash/ruleset/cn.mrs")" = 644 ] ||
  fail "cn.mrs permissions are not 0644"

echo "shellcrash_data_fixture_tests=ok"
