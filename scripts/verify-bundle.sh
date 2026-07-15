#!/bin/sh
# Verify the offline payload bundle without contacting the network.
set -u

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
repo_root=$(CDPATH= cd "$script_dir/.." && pwd)
bundle_dir="${1:-$repo_root/bundle}"

failures=0
warnings=0

info() { echo "verify-bundle: $*"; }
warn() { warnings=$((warnings + 1)); echo "verify-bundle: WARN: $*" >&2; }
fail() { failures=$((failures + 1)); echo "verify-bundle: ERROR: $*" >&2; }

need_file() {
  f="$1"
  if [ ! -s "$bundle_dir/$f" ]; then
    fail "missing or empty bundle/$f"
    return 1
  fi
  return 0
}

need_file "mihomo-linux-arm64" || true
need_file "ShellCrash.tar.gz" || true
need_file "SHA256SUMS" || true

if [ "$failures" -eq 0 ]; then
  sums_tmp=$(mktemp "${TMPDIR:-/tmp}/home-edge-sha256.XXXXXX" 2>/dev/null) || sums_tmp=""
  if [ -z "$sums_tmp" ]; then
    fail "cannot create secure temporary SHA256SUMS file"
  else
    tr -d '\r' < "$bundle_dir/SHA256SUMS" > "$sums_tmp"
    if command -v sha256sum >/dev/null 2>&1; then
      (cd "$bundle_dir" && sha256sum -c "$sums_tmp") || fail "SHA256SUMS check failed"
    elif command -v shasum >/dev/null 2>&1; then
      (cd "$bundle_dir" && shasum -a 256 -c "$sums_tmp") || fail "SHA256SUMS check failed"
    elif [ "${BUNDLE_DIGEST_HOST_VERIFIED:-0}" = "1" ]; then
      warn "router digest tool unavailable; relying on explicit host verification attestation"
    else
      fail "sha256sum or shasum is required unless host verification was explicitly attested"
    fi
    rm -f "$sums_tmp"
  fi
fi

if [ -s "$bundle_dir/ShellCrash.tar.gz" ]; then
  tar_list=$(mktemp "${TMPDIR:-/tmp}/home-edge-shellcrash-list.XXXXXX" 2>/dev/null) || tar_list=""
  tar_verbose=$(mktemp "${TMPDIR:-/tmp}/home-edge-shellcrash-verbose.XXXXXX" 2>/dev/null) || tar_verbose=""
  if [ -z "$tar_list" ] || [ -z "$tar_verbose" ]; then
    fail "cannot create secure temporary archive inspection files"
  elif tar -tzf "$bundle_dir/ShellCrash.tar.gz" >"$tar_list" 2>/dev/null &&
       tar -tvzf "$bundle_dir/ShellCrash.tar.gz" >"$tar_verbose" 2>/dev/null; then
    entry_count=$(wc -l <"$tar_list" | tr -d ' ')
    case "$entry_count" in ""|*[!0-9]*) fail "cannot count ShellCrash archive entries" ;; esac
    [ "${entry_count:-0}" -le 4096 ] || fail "ShellCrash archive has too many entries"

    while IFS= read -r entry; do
      case "$entry" in
        ""|/*|..|../*|*/../*|*/..|*//*)
          fail "ShellCrash archive contains unsafe path: $entry"
          ;;
      esac
    done <"$tar_list"

    awk '{
      type = substr($1, 1, 1)
      if (type != "-" && type != "d") exit 1
      if ($1 ~ /[sS]/) exit 1
    }' "$tar_verbose" || fail "ShellCrash archive contains links, special files, or privileged mode bits"

    for required in init.sh start.sh menu.sh libs/set_config.sh starts/check_core.sh libs/core_tools.sh; do
      grep -qx "$required" "$tar_list" || fail "ShellCrash.tar.gz missing $required"
    done
  else
    fail "ShellCrash.tar.gz cannot be safely listed"
  fi
  [ -z "$tar_list" ] || rm -f "$tar_list"
  [ -z "$tar_verbose" ] || rm -f "$tar_verbose"
fi

if [ -s "$bundle_dir/mihomo-linux-arm64" ]; then
  if command -v od >/dev/null 2>&1; then
    magic=$(dd if="$bundle_dir/mihomo-linux-arm64" bs=4 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    [ "$magic" = "7f454c46" ] || fail "mihomo-linux-arm64 is not an ELF binary"
  else
    warn "od not found; skipped ELF magic verification"
  fi

  os=$(uname -s 2>/dev/null || echo unknown)
  arch=$(uname -m 2>/dev/null || echo unknown)
  case "$os:$arch" in
    Linux:aarch64|Linux:arm64)
      chmod 755 "$bundle_dir/mihomo-linux-arm64" 2>/dev/null || true
      "$bundle_dir/mihomo-linux-arm64" -v >/dev/null 2>&1 || fail "mihomo-linux-arm64 does not execute on this arm64 Linux host"
      ;;
    *)
      warn "not running on Linux arm64 ($os/$arch); skipped Mihomo execution check"
      ;;
  esac
fi

if [ "$failures" -gt 0 ]; then
  info "FAILED failures=$failures warnings=$warnings"
  exit 1
fi

info "OK warnings=$warnings"
