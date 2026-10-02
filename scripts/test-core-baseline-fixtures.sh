#!/bin/sh
# Offline evidence tests. No SSH target, subscription or real /proc is accessed.
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
. "$repo/scripts/audit-core-baseline.sh"
fixture_root=$(mktemp -d /tmp/home-edge-core-baseline.XXXXXX)
case "$fixture_root" in /tmp/home-edge-core-baseline.*) ;; *) exit 1 ;; esac
cleanup() { rm -rf "$fixture_root"; }
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
mkdir -p "$fixture_root/proc/4242" "$fixture_root/jffs/ShellCrash/configs" \
  "$fixture_root/jffs/home-edge-bootstrap-state/runtime" "$fixture_root/jffs/.home-core-update-fixture" "$fixture_root/bin"
record="$fixture_root/jffs/home-edge-bootstrap-state/runtime-core-baseline.env"
receipt="$fixture_root/jffs/.home-core-update-fixture/result.env"
acceptance_status="$fixture_root/jffs/.home-core-update-fixture/status"
native="$fixture_root/jffs/ShellCrash/CrashCore.gz"
protected="$fixture_root/jffs/home-edge-bootstrap-state/runtime/mihomo-linux-arm64.gz"
metadata="$fixture_root/jffs/ShellCrash/configs/ShellCrash.cfg"
exe="$fixture_root/proc/4242/exe"
cat >"$exe" <<'EOF'
#!/bin/sh
printf 'Mihomo Meta v1.19.32 linux arm64\n'
EOF
chmod 700 "$exe"
cp "$exe" "$fixture_root/exe-before"
{
  printf '4242 (fixture) S'
  fixture_i=0
  while [ "$fixture_i" -lt 18 ]; do printf ' 0'; fixture_i=$((fixture_i+1)); done
  printf ' 4242\n'
} >"$fixture_root/proc/4242/stat"
gzip -n -c "$exe" >"$native"
cp "$native" "$protected"
printf "core_v='1.19.32'\n" >"$metadata"
printf '%s\n' 'version=v1.19.32' 'selectors_unchanged=yes' 'route_verified=yes' >"$receipt"
printf 'verified\n' >"$acceptance_status"
raw_hash=$(core_baseline_sha256 "$exe")
gzip_hash=$(core_baseline_sha256 "$native")
write_record() {
  receipt_hash=$(core_baseline_sha256 "$receipt")
  printf '%s\n' 'schema_version=1' 'core_version=v1.19.32' "core_raw_sha256=$raw_hash" \
    "core_gzip_sha256=$gzip_hash" 'receipt_path=/jffs/.home-core-update-fixture/result.env' \
    "receipt_sha256=$receipt_hash" >"$record"
}
write_record
cp "$record" "$fixture_root/record-before"
cp "$receipt" "$fixture_root/receipt-before"
expect_state() {
  fixture_output=$(HOME_EDGE_CORE_AUDIT_ROOT="$fixture_root" HOME_EDGE_CORE_PROC_ROOT="$fixture_root/proc" audit_core_baseline 4242)
  printf '%s\n' "$fixture_output" | grep -Fx "core_baseline_state=$2" >/dev/null || {
    printf '%s\n' "$fixture_output" >&2; echo "core_baseline_case=$1:failed" >&2; exit 1;
  }
  printf '%s\n' "$fixture_output" | grep -Fx "core_baseline_reason=$3" >/dev/null || exit 1
  echo "core_baseline_case=$1:pass"
}
expect_state match match accepted_site_core_and_receipt_match
printf '%s\n' "$fixture_output" | grep -Fx 'core_baseline_status_source=separate_file' >/dev/null
printf '%s\n' "$fixture_output" | grep -Fx 'mihomo_version=v1.19.32' >/dev/null
printf '%s\n' "$fixture_output" | grep -Fx 'shellcrash_core_version=v1.19.32' >/dev/null
command() { return 127; }
expect_state no_command_builtin match accepted_site_core_and_receipt_match
unset -f command
mv "$acceptance_status" "$fixture_root/status-held"
expect_state status_missing unavailable acceptance_status_missing
printf 'status=verified\n' >>"$receipt"; write_record
expect_state legacy_receipt_status match accepted_site_core_and_receipt_match
printf '%s\n' "$fixture_output" | grep -Fx 'core_baseline_status_source=receipt_field' >/dev/null
cp "$fixture_root/receipt-before" "$receipt"; cp "$fixture_root/record-before" "$record"
mv "$fixture_root/status-held" "$acceptance_status"
printf 'verified\nverified\n' >"$acceptance_status"
expect_state status_multiple_lines invalid receipt_acceptance_not_verified
printf 'verified\n' >"$acceptance_status"

printf '\n# changed bytes, same reported version\n' >>"$exe"
expect_state changed_binary drift runtime_digest_mismatch
cp "$fixture_root/exe-before" "$exe"
sed 's/v1.19.32/v1.19.31/' "$exe" >"$fixture_root/exe-old"
cat "$fixture_root/exe-old" >"$exe"
expect_state changed_version drift runtime_version_mismatch
cp "$fixture_root/exe-before" "$exe"
printf 'core_v=v1.19.31\n' >"$metadata"
expect_state metadata_mismatch drift shellcrash_metadata_mismatch
printf 'core_v=1.19.32\n' >"$metadata"
printf '\n' >>"$native"
expect_state native_archive_changed drift native_archive_mismatch
cp "$protected" "$native"
printf '\n' >>"$protected"
expect_state protected_archive_changed drift protected_archive_mismatch
cp "$native" "$protected"
printf 'historical_note=changed\n' >>"$receipt"
expect_state receipt_changed drift receipt_digest_mismatch
cp "$fixture_root/receipt-before" "$receipt"
mv "$receipt" "$fixture_root/receipt-held"
expect_state receipt_missing unavailable receipt_missing_or_unreadable
mv "$fixture_root/receipt-held" "$receipt"
printf 'failed\n' >"$acceptance_status"
expect_state receipt_not_accepted invalid receipt_acceptance_not_verified
printf 'verified\n' >"$acceptance_status"
cp "$fixture_root/receipt-before" "$receipt"; cp "$fixture_root/record-before" "$record"
printf 'schema_version=1\n' >>"$record"
expect_state duplicate_field invalid malformed_site_record
cp "$fixture_root/record-before" "$record"
printf '$(touch %s/record-executed)\n' "$fixture_root" >>"$record"
expect_state arbitrary_record_line invalid malformed_site_record
[ ! -e "$fixture_root/record-executed" ]
cp "$fixture_root/record-before" "$record"
printf 'extra=$(touch %s/receipt-executed)\n' "$fixture_root" >>"$receipt"; write_record
expect_state receipt_is_data match accepted_site_core_and_receipt_match
[ ! -e "$fixture_root/receipt-executed" ]
cp "$fixture_root/receipt-before" "$receipt"; cp "$fixture_root/record-before" "$record"
mv "$record" "$fixture_root/record-held"
expect_state no_record unrecorded site_record_missing
mv "$fixture_root/record-held" "$record"
mv "$exe" "$fixture_root/exe-held"
expect_state runtime_missing unavailable observation_incomplete
mv "$fixture_root/exe-held" "$exe"
mv "$receipt" "$fixture_root/receipt-held"
ln -s "$fixture_root/receipt-held" "$receipt"
if [ -L "$receipt" ]; then
  expect_state receipt_link invalid unsafe_receipt_path
else
  # Git Bash may emulate ln -s with a copy when Windows symlinks are unavailable.
  echo core_baseline_case=receipt_link:skipped_no_native_symlink
fi
rm "$receipt"; mv "$fixture_root/receipt-held" "$receipt"

# Capture both host payloads through fake local SSH, never execute the router audit.
cat >"$fixture_root/bin/ssh" <<'EOF'
#!/bin/sh
cat >"$CORE_FIXTURE_PAYLOAD"
printf 'device_state=ssh_reachable\n'
EOF
chmod 700 "$fixture_root/bin/ssh"
CORE_FIXTURE_PAYLOAD="$fixture_root/payload-shell.sh" PATH="$fixture_root/bin:$PATH" \
  LOG_PATH="$fixture_root/shell.log" KNOWN_HOSTS_FILE="$fixture_root/known-hosts" \
  sh "$repo/scripts/audit-router-baseline.sh" fixture@invalid >/dev/null
library_lines=$(wc -l <"$repo/scripts/audit-core-baseline.sh" | tr -d ' ')
head -n "$library_lines" "$fixture_root/payload-shell.sh" >"$fixture_root/library-shell.sh"
cmp -s "$repo/scripts/audit-core-baseline.sh" "$fixture_root/library-shell.sh"
grep -F 'audit_core_baseline "${runtime_pid:-}"' "$fixture_root/payload-shell.sh" >/dev/null
echo core_baseline_case=shell_payload_library:pass
if command -v pwsh >/dev/null 2>&1; then
  cat >"$fixture_root/capture.ps1" <<'EOF'
param([string]$Audit, [string]$Temp)
$ErrorActionPreference = 'Stop'
$global:CoreFixtureTemp = $Temp
function global:ssh {
  begin { $PayloadText = '' }
  process { $PayloadText += [string]$_ }
  end {
    $Decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($PayloadText))
    [IO.File]::WriteAllText((Join-Path $global:CoreFixtureTemp 'payload-ps.sh'), $Decoded, [Text.UTF8Encoding]::new($false))
    $global:LASTEXITCODE = 0
    'device_state=ssh_reachable'
  }
}
& $Audit -Router 'fixture@invalid' -LogPath (Join-Path $Temp 'ps.log') -KnownHostsFile (Join-Path $Temp 'known-hosts') -NoPause | Out-Null
EOF
  pwsh -NoProfile -File "$fixture_root/capture.ps1" -Audit "$repo/scripts/audit-router-baseline.ps1" -Temp "$fixture_root" >/dev/null
  head -n "$library_lines" "$fixture_root/payload-ps.sh" >"$fixture_root/library-ps.sh"
  cmp -s "$repo/scripts/audit-core-baseline.sh" "$fixture_root/library-ps.sh"
  grep -F 'audit_core_baseline "${runtime_pid:-}"' "$fixture_root/payload-ps.sh" >/dev/null
  echo core_baseline_case=powershell_payload_library:pass
else
  echo core_baseline_case=powershell_payload_library:skipped_no_pwsh
fi
echo core_baseline_fixture_tests=ok
