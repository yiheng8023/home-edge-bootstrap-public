#!/bin/sh
# Validate and prefetch ShellCrash geo data without restarting ShellCrash.
# The default action is plan; status is read-only and apply uses staged commits.
set -u
umask 077

ACTION="${HOME_EDGE_DATA_ACTION:-plan}"
SHELLCRASH_DIR="${HOME_EDGE_SHELLCRASH_DIR:-/jffs/ShellCrash}"
COUNTRY_FILE="${HOME_EDGE_COUNTRY_FILE:-$SHELLCRASH_DIR/Country.mmdb}"
CN_MRS_FILE="${HOME_EDGE_CN_MRS_FILE:-$SHELLCRASH_DIR/ruleset/cn.mrs}"
COUNTRY_SHA256="${HOME_EDGE_COUNTRY_SHA256:-}"
COUNTRY_BYTES="${HOME_EDGE_COUNTRY_BYTES:-}"
CN_MRS_SHA256="${HOME_EDGE_CN_MRS_SHA256:-}"
CN_MRS_BYTES="${HOME_EDGE_CN_MRS_BYTES:-}"
COUNTRY_URL="${HOME_EDGE_COUNTRY_URL:-}"
CN_MRS_URL="${HOME_EDGE_CN_MRS_URL:-}"
COUNTRY_MIN_BYTES="${HOME_EDGE_COUNTRY_MIN_BYTES:-65536}"
COUNTRY_MAX_BYTES="${HOME_EDGE_COUNTRY_MAX_BYTES:-33554432}"
CN_MRS_MIN_BYTES="${HOME_EDGE_CN_MRS_MIN_BYTES:-65536}"
CN_MRS_MAX_BYTES="${HOME_EDGE_CN_MRS_MAX_BYTES:-33554432}"
SPACE_BUFFER_KIB="${HOME_EDGE_DATA_SPACE_BUFFER_KIB:-4096}"
DF_BIN="${HOME_EDGE_DATA_DF_BIN:-}"
CONNECT_TIMEOUT="${HOME_EDGE_DATA_CONNECT_TIMEOUT:-5}"
TOTAL_TIMEOUT="${HOME_EDGE_DATA_TOTAL_TIMEOUT:-60}"
CURL_BIN="${HOME_EDGE_DATA_CURL_BIN:-}"

country_stage=""
cn_mrs_stage=""
country_backup=""
cn_mrs_backup=""
country_prior=absent
cn_mrs_prior=absent
country_changed=0
cn_mrs_changed=0
commit_in_progress=0

restore_originals() {
  restore_failed=0
  if [ "$cn_mrs_changed" -eq 1 ]; then
    rm -f "$CN_MRS_FILE" 2>/dev/null || restore_failed=1
    if [ "$cn_mrs_prior" = present ] && [ -n "$cn_mrs_backup" ] && [ -e "$cn_mrs_backup" ]; then
      if mv "$cn_mrs_backup" "$CN_MRS_FILE" 2>/dev/null; then
        cn_mrs_backup=""
        cn_mrs_changed=0
      else
        restore_failed=1
      fi
    elif [ "$cn_mrs_prior" = absent ] && [ ! -e "$CN_MRS_FILE" ]; then
      cn_mrs_changed=0
    else
      restore_failed=1
    fi
  fi
  if [ "$country_changed" -eq 1 ]; then
    rm -f "$COUNTRY_FILE" 2>/dev/null || restore_failed=1
    if [ "$country_prior" = present ] && [ -n "$country_backup" ] && [ -e "$country_backup" ]; then
      if mv "$country_backup" "$COUNTRY_FILE" 2>/dev/null; then
        country_backup=""
        country_changed=0
      else
        restore_failed=1
      fi
    elif [ "$country_prior" = absent ] && [ ! -e "$COUNTRY_FILE" ]; then
      country_changed=0
    else
      restore_failed=1
    fi
  fi
  [ "$restore_failed" -eq 0 ]
}

cleanup() {
  if [ "$commit_in_progress" -eq 1 ]; then
    restore_originals || true
  fi
  [ -z "$country_stage" ] || rm -f "$country_stage" 2>/dev/null || true
  [ -z "$cn_mrs_stage" ] || rm -f "$cn_mrs_stage" 2>/dev/null || true
  if [ "$country_changed" -eq 0 ]; then
    [ -z "$country_backup" ] || rm -f "$country_backup" 2>/dev/null || true
  fi
  if [ "$cn_mrs_changed" -eq 0 ]; then
    [ -z "$cn_mrs_backup" ] || rm -f "$cn_mrs_backup" 2>/dev/null || true
  fi
}
handle_signal() {
  cleanup
  trap - EXIT
  exit 130
}
trap cleanup EXIT
trap handle_signal HUP INT TERM

die() {
  printf 'prefetch-shellcrash-data: ERROR: %s\n' "$1" >&2
  exit 1
}

validate_absolute_path() {
  case "$2" in
    /*) ;;
    *) die "unsafe path configuration" ;;
  esac
  case "$2" in
    /|*[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*)
      die "unsafe path configuration"
      ;;
  esac
}

validate_uint() {
  case "$2" in
    ''|*[!0-9]*) die "invalid numeric configuration" ;;
  esac
  [ "$2" -gt 0 ] 2>/dev/null || die "invalid numeric configuration"
}

validate_optional_sha256() {
  [ -z "$2" ] && return 0
  [ "${#2}" -eq 64 ] || die "invalid SHA-256 pin"
  case "$2" in *[!0-9A-Fa-f]*) die "invalid SHA-256 pin" ;; esac
}

validate_optional_bytes() {
  [ -z "$2" ] || validate_uint "$1" "$2"
}

valid_https_url() {
  case "$1" in
    https://?*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[[:space:]]*|*[\"]*|*[\\]*|https://*@*) return 1 ;;
  esac
  return 0
}

download_asset() {
  source_url=$1
  destination=$2
  {
    printf 'url = "%s"\n' "$source_url"
    printf 'output = "%s"\n' "$destination"
    printf 'fail\n'
    printf 'location\n'
    printf 'silent\n'
    printf 'show-error = false\n'
    printf 'proto = "=https"\n'
    printf 'proto-redir = "=https"\n'
    printf 'connect-timeout = %s\n' "$CONNECT_TIMEOUT"
    printf 'max-time = %s\n' "$TOTAL_TIMEOUT"
  } | "$CURL_BIN" --config - >/dev/null 2>&1
}

secure_temp_helper=${HOME_EDGE_SECURE_TEMP_HELPER:-}
if [ -z "$secure_temp_helper" ]; then
  source_dir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) ||
    die "secure temporary-path helper is unavailable"
  secure_temp_helper="$source_dir/home-edge-secure-temp.sh"
  [ -r "$secure_temp_helper" ] || secure_temp_helper=/jffs/scripts/home-edge-secure-temp.sh
fi
[ -r "$secure_temp_helper" ] || die "secure temporary-path helper is unavailable"
. "$secure_temp_helper"

file_sha256() {
  if which sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  elif which openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}'
  else
    return 1
  fi
}

file_bytes() {
  wc -c <"$1" 2>/dev/null | tr -d '[:space:]'
}

asset_state() {
  target=$1
  expected_sha=$2
  expected_bytes=$3
  min_bytes=$4
  max_bytes=$5

  if [ ! -e "$target" ]; then
    printf 'missing\n'
    return
  fi
  if [ ! -f "$target" ] || [ -L "$target" ] || [ ! -r "$target" ]; then
    printf 'invalid\n'
    return
  fi
  actual_bytes=$(file_bytes "$target") || {
    printf 'invalid\n'
    return
  }
  case "$actual_bytes" in ''|*[!0-9]*)
    printf 'invalid\n'
    return
  esac
  if [ "$actual_bytes" -lt "$min_bytes" ] || [ "$actual_bytes" -gt "$max_bytes" ]; then
    printf 'size_out_of_bounds\n'
    return
  fi
  if [ -n "$expected_bytes" ] && [ "$actual_bytes" -ne "$expected_bytes" ]; then
    printf 'size_mismatch\n'
    return
  fi
  if [ -z "$expected_sha" ]; then
    printf 'unpinned\n'
    return
  fi
  actual_sha=$(file_sha256 "$target") || {
    printf 'unverifiable\n'
    return
  }
  actual_sha=$(printf '%s' "$actual_sha" | tr 'A-F' 'a-f')
  expected_sha=$(printf '%s' "$expected_sha" | tr 'A-F' 'a-f')
  if [ "$actual_sha" = "$expected_sha" ]; then
    printf 'ready\n'
  else
    printf 'digest_mismatch\n'
  fi
}

validate_absolute_path HOME_EDGE_SHELLCRASH_DIR "$SHELLCRASH_DIR"
validate_absolute_path HOME_EDGE_COUNTRY_FILE "$COUNTRY_FILE"
validate_absolute_path HOME_EDGE_CN_MRS_FILE "$CN_MRS_FILE"
validate_optional_sha256 HOME_EDGE_COUNTRY_SHA256 "$COUNTRY_SHA256"
validate_optional_sha256 HOME_EDGE_CN_MRS_SHA256 "$CN_MRS_SHA256"
validate_optional_bytes HOME_EDGE_COUNTRY_BYTES "$COUNTRY_BYTES"
validate_optional_bytes HOME_EDGE_CN_MRS_BYTES "$CN_MRS_BYTES"
validate_uint HOME_EDGE_COUNTRY_MIN_BYTES "$COUNTRY_MIN_BYTES"
validate_uint HOME_EDGE_COUNTRY_MAX_BYTES "$COUNTRY_MAX_BYTES"
validate_uint HOME_EDGE_CN_MRS_MIN_BYTES "$CN_MRS_MIN_BYTES"
validate_uint HOME_EDGE_CN_MRS_MAX_BYTES "$CN_MRS_MAX_BYTES"
validate_uint HOME_EDGE_DATA_SPACE_BUFFER_KIB "$SPACE_BUFFER_KIB"
validate_uint HOME_EDGE_DATA_CONNECT_TIMEOUT "$CONNECT_TIMEOUT"
validate_uint HOME_EDGE_DATA_TOTAL_TIMEOUT "$TOTAL_TIMEOUT"
[ "$CONNECT_TIMEOUT" -le "$TOTAL_TIMEOUT" ] || die "invalid timeout configuration"
[ "$COUNTRY_MIN_BYTES" -le "$COUNTRY_MAX_BYTES" ] || die "invalid size bounds"
[ "$CN_MRS_MIN_BYTES" -le "$CN_MRS_MAX_BYTES" ] || die "invalid size bounds"
if [ -n "$COUNTRY_BYTES" ] &&
  { [ "$COUNTRY_BYTES" -lt "$COUNTRY_MIN_BYTES" ] || [ "$COUNTRY_BYTES" -gt "$COUNTRY_MAX_BYTES" ]; }; then
  die "invalid exact-size pin"
fi
if [ -n "$CN_MRS_BYTES" ] &&
  { [ "$CN_MRS_BYTES" -lt "$CN_MRS_MIN_BYTES" ] || [ "$CN_MRS_BYTES" -gt "$CN_MRS_MAX_BYTES" ]; }; then
  die "invalid exact-size pin"
fi
case "$COUNTRY_FILE" in "$SHELLCRASH_DIR"/*) ;; *) die "data target is outside ShellCrash" ;; esac
case "$CN_MRS_FILE" in "$SHELLCRASH_DIR"/*) ;; *) die "data target is outside ShellCrash" ;; esac

case "$ACTION" in
  plan|apply|status) ;;
  *) die "HOME_EDGE_DATA_ACTION must be plan, apply, or status" ;;
esac

country_state=$(asset_state "$COUNTRY_FILE" "$COUNTRY_SHA256" "$COUNTRY_BYTES" \
  "$COUNTRY_MIN_BYTES" "$COUNTRY_MAX_BYTES")
cn_mrs_state=$(asset_state "$CN_MRS_FILE" "$CN_MRS_SHA256" "$CN_MRS_BYTES" \
  "$CN_MRS_MIN_BYTES" "$CN_MRS_MAX_BYTES")

printf 'country_data_state=%s\n' "$country_state"
printf 'cn_mrs_data_state=%s\n' "$cn_mrs_state"

if [ "$country_state" = ready ] && [ "$cn_mrs_state" = ready ]; then
  printf 'shellcrash_data_state=ready\n'
  [ "$ACTION" != apply ] || printf 'shellcrash_data_commit_state=unchanged\n'
  exit 0
fi

if [ "$ACTION" = status ]; then
  if [ "$country_state" = unpinned ] || [ "$cn_mrs_state" = unpinned ]; then
    printf 'shellcrash_data_state=unpinned\n'
  else
    printf 'shellcrash_data_state=requires_download\n'
  fi
  exit 0
fi

if [ -z "$COUNTRY_SHA256" ] || [ -z "$CN_MRS_SHA256" ]; then
  printf 'shellcrash_data_pin_state=missing\n'
  printf 'shellcrash_data_source_state=not_checked\n'
  printf 'shellcrash_data_space_state=not_checked\n'
  printf 'shellcrash_data_state=blocked\n'
  exit 1
else
  printf 'shellcrash_data_pin_state=valid\n'
fi

source_state=valid
if [ "$country_state" != ready ]; then
  valid_https_url "$COUNTRY_URL" || source_state=invalid
fi
if [ "$cn_mrs_state" != ready ]; then
  valid_https_url "$CN_MRS_URL" || source_state=invalid
fi
printf 'shellcrash_data_source_state=%s\n' "$source_state"
if [ "$source_state" != valid ]; then
  printf 'shellcrash_data_space_state=not_checked\n'
  printf 'shellcrash_data_state=blocked\n'
  exit 1
fi

if [ -n "$DF_BIN" ]; then
  validate_absolute_path HOME_EDGE_DATA_DF_BIN "$DF_BIN"
  [ -x "$DF_BIN" ] || die "space inspection is unavailable"
else
  DF_BIN=$(which df 2>/dev/null || true)
  [ -n "$DF_BIN" ] || die "space inspection is unavailable"
fi

required_bytes=0
if [ "$country_state" != ready ]; then
  if [ -n "$COUNTRY_BYTES" ]; then
    required_bytes=$((required_bytes + COUNTRY_BYTES))
  else
    required_bytes=$((required_bytes + COUNTRY_MAX_BYTES))
  fi
fi
if [ "$cn_mrs_state" != ready ]; then
  if [ -n "$CN_MRS_BYTES" ]; then
    required_bytes=$((required_bytes + CN_MRS_BYTES))
  else
    required_bytes=$((required_bytes + CN_MRS_MAX_BYTES))
  fi
fi
required_kib=$(((required_bytes + 1023) / 1024 + SPACE_BUFFER_KIB))
available_kib=$(
  LC_ALL=C "$DF_BIN" -k "$SHELLCRASH_DIR" 2>/dev/null |
    awk 'NR > 1 && NF >= 4 && $4 ~ /^[0-9]+$/ { available=$4 } END { if (available == "") exit 1; print available }'
) || {
  printf 'shellcrash_data_space_state=unavailable\n'
  printf 'shellcrash_data_state=blocked\n'
  exit 1
}
case "$available_kib" in ''|*[!0-9]*)
  printf 'shellcrash_data_space_state=unavailable\n'
  printf 'shellcrash_data_state=blocked\n'
  exit 1
  ;;
esac
if [ "$available_kib" -lt "$required_kib" ]; then
  printf 'shellcrash_data_space_state=insufficient\n'
  printf 'shellcrash_data_state=blocked\n'
  exit 1
fi
printf 'shellcrash_data_space_state=sufficient\n'

if [ "$ACTION" = apply ]; then
  if [ -n "$CURL_BIN" ]; then
    validate_absolute_path HOME_EDGE_DATA_CURL_BIN "$CURL_BIN"
    [ -x "$CURL_BIN" ] || die "download capability is unavailable"
  else
    CURL_BIN=$(which curl 2>/dev/null || true)
    [ -n "$CURL_BIN" ] || die "download capability is unavailable"
  fi

  country_dir=$(dirname "$COUNTRY_FILE")
  cn_mrs_dir=$(dirname "$CN_MRS_FILE")
  [ -d "$country_dir" ] && [ ! -L "$country_dir" ] ||
    die "target directory is unavailable"
  [ -d "$cn_mrs_dir" ] && [ ! -L "$cn_mrs_dir" ] ||
    die "target directory is unavailable"
  [ ! -L "$COUNTRY_FILE" ] && [ ! -L "$CN_MRS_FILE" ] ||
    die "target file is unsafe"

  download_failed=0
  if [ "$country_state" != ready ]; then
    country_stage=$(home_edge_secure_temp "$country_dir/.home-edge-country.XXXXXX") ||
      die "cannot allocate staged data file"
    download_asset "$COUNTRY_URL" "$country_stage" || download_failed=1
  fi
  if [ "$download_failed" -eq 0 ] && [ "$cn_mrs_state" != ready ]; then
    cn_mrs_stage=$(home_edge_secure_temp "$cn_mrs_dir/.home-edge-cn-mrs.XXXXXX") ||
      die "cannot allocate staged data file"
    download_asset "$CN_MRS_URL" "$cn_mrs_stage" || download_failed=1
  fi
  if [ "$download_failed" -ne 0 ]; then
    printf 'shellcrash_data_download_state=failed\n'
    printf 'shellcrash_data_commit_state=unchanged\n'
    printf 'shellcrash_data_state=blocked\n'
    exit 1
  fi
  printf 'shellcrash_data_download_state=complete\n'

  country_candidate_state=ready
  cn_mrs_candidate_state=ready
  if [ -n "$country_stage" ]; then
    country_candidate_state=$(asset_state "$country_stage" "$COUNTRY_SHA256" "$COUNTRY_BYTES" \
      "$COUNTRY_MIN_BYTES" "$COUNTRY_MAX_BYTES")
  fi
  if [ -n "$cn_mrs_stage" ]; then
    cn_mrs_candidate_state=$(asset_state "$cn_mrs_stage" "$CN_MRS_SHA256" "$CN_MRS_BYTES" \
      "$CN_MRS_MIN_BYTES" "$CN_MRS_MAX_BYTES")
  fi
  if [ "$country_candidate_state" != ready ] || [ "$cn_mrs_candidate_state" != ready ]; then
    printf 'shellcrash_data_validation_state=failed\n'
    printf 'shellcrash_data_commit_state=unchanged\n'
    printf 'shellcrash_data_state=blocked\n'
    exit 1
  fi
  printf 'shellcrash_data_validation_state=ready\n'

  [ -z "$country_stage" ] || chmod 644 "$country_stage" 2>/dev/null ||
    die "cannot secure staged data file"
  [ -z "$cn_mrs_stage" ] || chmod 644 "$cn_mrs_stage" 2>/dev/null ||
    die "cannot secure staged data file"

  commit_in_progress=1
  commit_failed=0
  if [ -n "$country_stage" ]; then
    if [ -e "$COUNTRY_FILE" ]; then
      country_prior=present
      country_backup=$(home_edge_secure_temp "$country_dir/.home-edge-country-backup.XXXXXX") ||
        commit_failed=1
      if [ "$commit_failed" -eq 0 ]; then
        mv "$COUNTRY_FILE" "$country_backup" 2>/dev/null || commit_failed=1
      fi
    fi
    if [ "$commit_failed" -eq 0 ]; then
      country_changed=1
      mv "$country_stage" "$COUNTRY_FILE" 2>/dev/null || commit_failed=1
      [ "$commit_failed" -ne 0 ] || country_stage=""
    fi
  fi

  if [ "$commit_failed" -eq 0 ] && [ -n "$cn_mrs_stage" ]; then
    if [ -e "$CN_MRS_FILE" ]; then
      cn_mrs_prior=present
      cn_mrs_backup=$(home_edge_secure_temp "$cn_mrs_dir/.home-edge-cn-mrs-backup.XXXXXX") ||
        commit_failed=1
      if [ "$commit_failed" -eq 0 ]; then
        mv "$CN_MRS_FILE" "$cn_mrs_backup" 2>/dev/null || commit_failed=1
      fi
    fi
    if [ "$commit_failed" -eq 0 ]; then
      cn_mrs_changed=1
      mv "$cn_mrs_stage" "$CN_MRS_FILE" 2>/dev/null || commit_failed=1
      [ "$commit_failed" -ne 0 ] || cn_mrs_stage=""
    fi
  fi

  if [ "$commit_failed" -eq 0 ]; then
    final_country_state=$(asset_state "$COUNTRY_FILE" "$COUNTRY_SHA256" "$COUNTRY_BYTES" \
      "$COUNTRY_MIN_BYTES" "$COUNTRY_MAX_BYTES")
    final_cn_mrs_state=$(asset_state "$CN_MRS_FILE" "$CN_MRS_SHA256" "$CN_MRS_BYTES" \
      "$CN_MRS_MIN_BYTES" "$CN_MRS_MAX_BYTES")
    if [ "$final_country_state" != ready ] || [ "$final_cn_mrs_state" != ready ]; then
      commit_failed=1
    fi
  fi

  if [ "$commit_failed" -ne 0 ]; then
    if restore_originals; then
      commit_in_progress=0
      printf 'shellcrash_data_commit_state=rolled_back\n'
    else
      printf 'shellcrash_data_commit_state=rollback_failed\n'
    fi
    printf 'shellcrash_data_state=blocked\n'
    exit 1
  fi

  commit_in_progress=0
  [ -z "$country_backup" ] || {
    rm -f "$country_backup" 2>/dev/null || true
    country_backup=""
  }
  [ -z "$cn_mrs_backup" ] || {
    rm -f "$cn_mrs_backup" 2>/dev/null || true
    cn_mrs_backup=""
  }
  printf 'shellcrash_data_commit_state=committed\n'
  printf 'shellcrash_data_restart_required=0\n'
  printf 'shellcrash_data_state=ready\n'
else
  printf 'shellcrash_data_state=planned\n'
fi
