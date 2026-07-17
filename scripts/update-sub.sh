#!/bin/sh
# Refresh a provider subscription into a validated Mihomo/Clash YAML cache.
# Default is DRY-RUN so it cannot break the live router by accident.
set -u
umask 077

if [ -n "${SUBSCRIPTION_POLICY_FILE:-}" ] && [ -r "$SUBSCRIPTION_POLICY_FILE" ]; then
  . "$SUBSCRIPTION_POLICY_FILE"
else
  for f in /jffs/scripts/home-edge-policy.env /jffs/home-edge-bootstrap/config/policy.env ./config/policy.env; do
    [ -r "$f" ] && { . "$f"; break; }
  done
fi

STATE_ROOT="${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}"
SUB_FILE="${SUBSCRIPTION_FILE:-$STATE_ROOT/SUBSCRIPTION.local}"
SUB_CACHE="${SUBSCRIPTION_CACHE:-$STATE_ROOT/cache/subscription.yaml}"
BACKUP_DIR="${SUBSCRIPTION_BACKUP_DIR:-$STATE_ROOT/backups/subscription}"
APPLY_PATH="${SUBSCRIPTION_APPLY_PATH:-}"
APPLY_ROOT="${SUBSCRIPTION_APPLY_ROOT:-}"
RELOAD_CMD="${SUBSCRIPTION_RELOAD_CMD:-}"
RUNTIME_EVIDENCE="${SUBSCRIPTION_RUNTIME_EVIDENCE:-/tmp/home-edge-subscription-runtime.evidence}"
RUNTIME_EVIDENCE_HELPER="${SUBSCRIPTION_RUNTIME_EVIDENCE_HELPER:-}"
DRY_RUN="${SUBSCRIPTION_DRY_RUN:-1}"
LOG="${SUBSCRIPTION_LOG:-/tmp/update-sub.log}"
FETCH_PROXY="${SUBSCRIPTION_FETCH_PROXY:-}"
CONVERTER_BASE="${SUBSCRIPTION_CONVERTER_BASE_URL:-}"
CONVERTER_TARGET="${SUBSCRIPTION_CONVERTER_TARGET:-clash}"
CONVERTER_CONFIG="${SUBSCRIPTION_CONVERTER_CONFIG_URL:-}"
ALLOW_REMOTE_CONVERTER="${SUBSCRIPTION_ALLOW_REMOTE_CONVERTER:-0}"
MIN_BYTES="${SUBSCRIPTION_MIN_BYTES:-64}"
MAX_BYTES="${SUBSCRIPTION_MAX_BYTES:-10485760}"
MIHOMO_BIN="${SUBSCRIPTION_MIHOMO_BIN:-}"
CURL_BIN="${CURL_BIN:-}"
JQ_BIN="${JQ_BIN:-}"
LOCK_DIR="${SUBSCRIPTION_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}"
LOCK_STALE_SEC="${SUBSCRIPTION_LOCK_STALE_SEC:-600}"
WRITE_LOCK_ALREADY_HELD="${HOME_EDGE_WRITE_LOCK_HELD:-0}"
MAX_BACKUPS="${SUBSCRIPTION_MAX_BACKUPS:-5}"
LOG_MAX_BYTES="${SUBSCRIPTION_LOG_MAX_BYTES:-262144}"
tmp=""
lock_held=0

if [ -z "$RUNTIME_EVIDENCE_HELPER" ]; then
  script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
  for candidate in "$script_dir/home-edge-subscription-runtime-evidence.sh" "$script_dir/subscription-runtime-evidence.sh"; do
    [ -r "$candidate" ] && { RUNTIME_EVIDENCE_HELPER=$candidate; break; }
  done
fi

log() { echo "$(date '+%F %T') update-sub: $*" >> "$LOG"; }
die() { log "ERROR: $*"; echo "ERROR: $*" >&2; exit 1; }
say() { echo "$*"; log "$*"; }
validate_bool() {
  name="$1"
  value="$2"
  case "$value" in
    0|1) ;;
    *) die "invalid boolean $name=$value; expected 0 or 1" ;;
  esac
}
validate_bool SUBSCRIPTION_DRY_RUN "$DRY_RUN"
validate_bool SUBSCRIPTION_ALLOW_REMOTE_CONVERTER "$ALLOW_REMOTE_CONVERTER"
validate_bool HOME_EDGE_WRITE_LOCK_HELD "$WRITE_LOCK_ALREADY_HELD"

rotate_log() {
  case "$LOG_MAX_BYTES" in ""|*[!0-9]*|0) LOG_MAX_BYTES=262144 ;; esac
  [ -f "$LOG" ] || return 0
  log_bytes=$(wc -c <"$LOG" 2>/dev/null | tr -d " ")
  case "$log_bytes" in ""|*[!0-9]*) log_bytes=0 ;; esac
  [ "$log_bytes" -le "$LOG_MAX_BYTES" ] || mv -f "$LOG" "$LOG.1"
}

prune_backups() {
  case "$MAX_BACKUPS" in ""|*[!0-9]*|0) MAX_BACKUPS=5 ;; esac
  count=0
  for candidate in $(ls -1t "$BACKUP_DIR"/*.yaml 2>/dev/null); do
    count=$((count + 1))
    [ "$count" -le "$MAX_BACKUPS" ] || rm -f "$candidate"
  done
}

cleanup() {
  [ -n "$tmp" ] && rm -f "$tmp"
  if [ "$lock_held" = "1" ]; then
    rm -f "$LOCK_DIR/started_at" "$LOCK_DIR/pid" "$LOCK_DIR/operation" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
  fi
}
handle_signal() {
  cleanup
  trap - EXIT
  exit 130
}
trap cleanup EXIT
trap handle_signal HUP INT TERM

acquire_lock() {
  [ "$WRITE_LOCK_ALREADY_HELD" != "1" ] || { log "inherited global write lock"; return 0; }
  [ -n "$LOCK_DIR" ] && [ "$LOCK_DIR" != "/" ] || die "invalid subscription lock directory"
  case "$LOCK_STALE_SEC" in ""|*[!0-9]*|0) LOCK_STALE_SEC=600 ;; esac
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || die "cannot prepare subscription lock parent"

  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    owner_pid=$(cat "$LOCK_DIR/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$LOCK_DIR/operation" 2>/dev/null || echo unknown)
      die "global write lock held by pid=$owner_pid operation=$operation"
    fi
    started=$(cat "$LOCK_DIR/started_at" 2>/dev/null || true)
    now=$(date +%s)
    case "$started:$now" in *[!0-9:]*|:*|*:) age=0 ;; *) age=$((now - started)) ;; esac
    if [ -z "$owner_pid" ] && [ "$age" -le "$LOCK_STALE_SEC" ]; then
      die "global write lock has no verifiable owner and lease has not expired"
    fi
    rm -f "$LOCK_DIR/started_at" "$LOCK_DIR/pid" "$LOCK_DIR/operation" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || die "stale global write lock could not be cleared: $LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || die "global write lock was reacquired by another process"
    log "recovered stale global write lock"
  fi

  lock_held=1
  date +%s >"$LOCK_DIR/started_at" || die "cannot record write lock start time"
  printf '%s\n' "$$" >"$LOCK_DIR/pid" || die "cannot record write lock owner"
  printf '%s\n' subscription-update >"$LOCK_DIR/operation" || die "cannot record write lock operation"
}

find_cmd() {
  name="$1"
  shift
  found=$(command -v "$name" 2>/dev/null || true)
  if [ -n "$found" ] && [ -x "$found" ]; then
    printf '%s\n' "$found"
    return 0
  fi
  for candidate in "$@"; do
    [ -x "$candidate" ] && { printf '%s\n' "$candidate"; return 0; }
  done
  return 1
}

resolve_curl() {
  if [ -n "$CURL_BIN" ]; then
    [ -x "$CURL_BIN" ] || die "CURL_BIN is not executable: $CURL_BIN"
    return 0
  fi
  CURL_BIN=$(find_cmd curl /usr/sbin/curl /usr/bin/curl /bin/curl /opt/bin/curl /opt/usr/bin/curl /jffs/ShellCrash/bin/curl) ||
    die "curl is required to download the subscription"
}

resolve_jq() {
  if [ -n "$JQ_BIN" ]; then
    [ -x "$JQ_BIN" ] || die "JQ_BIN is not executable: $JQ_BIN"
    return 0
  fi
  JQ_BIN=$(find_cmd jq /usr/sbin/jq /usr/bin/jq /bin/jq /opt/bin/jq /opt/usr/bin/jq /jffs/ShellCrash/bin/jq) ||
    die "jq is required for subscription converter URL encoding"
}

urlenc() {
  resolve_jq
  printf '%s' "$1" | "$JQ_BIN" -sRr @uri
}

private_ipv4() {
  host=$1
  case "$host" in
    *[!0-9.]*|*.*.*.*.*|.*|*.) return 1 ;;
  esac
  old_ifs=$IFS
  IFS=.
  set -- $host
  IFS=$old_ifs
  [ "$#" -eq 4 ] || return 1
  for octet in "$@"; do
    case "$octet" in ""|*[!0-9]*) return 1 ;; esac
    [ "$octet" -le 255 ] || return 1
  done
  case "$1" in
    10|127) return 0 ;;
    192) [ "$2" -eq 168 ] ;;
    172) [ "$2" -ge 16 ] && [ "$2" -le 31 ] ;;
    *) return 1 ;;
  esac
}

converter_is_allowed() {
  [ -z "$CONVERTER_BASE" ] && return 0
  [ "$ALLOW_REMOTE_CONVERTER" = "1" ] && return 0

  case "$CONVERTER_BASE" in
    http://*) authority=${CONVERTER_BASE#http://} ;;
    https://*) authority=${CONVERTER_BASE#https://} ;;
    *) return 1 ;;
  esac
  authority=${authority%%/*}
  authority=${authority%%\?*}
  authority=${authority%%\#*}
  [ -n "$authority" ] || return 1
  case "$authority" in *"@"*) return 1 ;; esac

  case "$authority" in
    localhost|localhost:*) return 0 ;;
    "[::1]"|"[::1]":*) return 0 ;;
    \[*\]*) return 1 ;;
  esac

  host=${authority%%:*}
  private_ipv4 "$host"
}

converter_url() {
  base="$CONVERTER_BASE"
  sep="?"
  case "$base" in
    *\?*) sep="&" ;;
  esac

  out="${base}${sep}target=$(urlenc "$CONVERTER_TARGET")&url=$(urlenc "$url")"
  if [ -n "$CONVERTER_CONFIG" ]; then
    out="${out}&config=$(urlenc "$CONVERTER_CONFIG")"
  fi
  printf '%s\n' "$out"
}

fetch_subscription() {
  resolve_curl
  if [ -n "$FETCH_PROXY" ]; then
    log "using subscription fetch proxy"
  fi

  if [ -n "$CONVERTER_BASE" ]; then
    converter_is_allowed || die "remote subscription converter blocked; use a local/private converter or set SUBSCRIPTION_ALLOW_REMOTE_CONVERTER=1 intentionally"
    converted_url=$(converter_url)
    log "downloading converted subscription via converter target=$CONVERTER_TARGET"
    if [ -n "$FETCH_PROXY" ]; then
      "$CURL_BIN" -x "$FETCH_PROXY" -fsSL --connect-timeout 8 --max-time 90 "$converted_url" -o "$tmp" || die "converted subscription download failed"
    else
      "$CURL_BIN" -fsSL --connect-timeout 8 --max-time 90 "$converted_url" -o "$tmp" || die "converted subscription download failed"
    fi
  else
    log "downloading subscription directly"
    if [ -n "$FETCH_PROXY" ]; then
      "$CURL_BIN" -x "$FETCH_PROXY" -fsSL --connect-timeout 8 --max-time 60 "$url" -o "$tmp" || die "download failed"
    else
      "$CURL_BIN" -fsSL --connect-timeout 8 --max-time 60 "$url" -o "$tmp" || die "download failed"
    fi
  fi
}

validate_subscription() {
  f="$1"
  [ -s "$f" ] || die "downloaded subscription is empty"

  size=$(wc -c < "$f" | tr -d ' ')
  case "$size" in
    ""|*[!0-9]*) die "cannot measure subscription size" ;;
  esac
  [ "$size" -ge "$MIN_BYTES" ] || die "subscription too small (${size} bytes)"
  [ "$size" -le "$MAX_BYTES" ] || die "subscription exceeds maximum size (${size} bytes)"

  if grep -Eiq '<!doctype|<html|<body|</html>|access denied|unauthorized|forbidden' "$f"; then
    die "downloaded subscription looks like an error page"
  fi

  if grep -Eq '^[[:space:]]*(ss|ssr|vmess|vless|trojan|hysteria2|hy2|tuic)://' "$f" ||
     grep -Eq '^[A-Za-z0-9+/=]{80,}$' "$f"; then
    die "subscription looks like a raw/base64 provider feed; configure SUBSCRIPTION_CONVERTER_BASE_URL or import it through ShellCrash"
  fi

  if ! grep -Eq '^[[:space:]]*(proxies|proxy-providers|rules|rule-providers|mixed-port|port|socks-port|allow-lan|mode|external-controller):' "$f"; then
    die "subscription does not look like a Mihomo/Clash YAML profile; configure SUBSCRIPTION_CONVERTER_BASE_URL if the provider gives a raw/base64 subscription"
  fi
}

validate_apply_path() {
  [ -n "$APPLY_PATH" ] || return 0
  [ "$APPLY_PATH" != "$SUB_CACHE" ] || die "SUBSCRIPTION_APPLY_PATH must differ from SUBSCRIPTION_CACHE"
  case "$APPLY_PATH" in
    /*) ;;
    *) die "SUBSCRIPTION_APPLY_PATH must be absolute" ;;
  esac
  case "$APPLY_PATH" in
    *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*|*/) die "unsafe SUBSCRIPTION_APPLY_PATH: $APPLY_PATH" ;;
  esac

  allowed_root="$APPLY_ROOT"
  if [ -z "$allowed_root" ]; then
    case "$APPLY_PATH" in
      /jffs/ShellCrash/*) allowed_root=/jffs/ShellCrash ;;
      /jffs/ShellClash/*) allowed_root=/jffs/ShellClash ;;
      *) die "live apply requires SUBSCRIPTION_APPLY_ROOT or a path below /jffs/ShellCrash or /jffs/ShellClash" ;;
    esac
  fi
  case "$allowed_root" in
    /*) ;;
    *) die "SUBSCRIPTION_APPLY_ROOT must be absolute" ;;
  esac
  case "$allowed_root" in
    /|*[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*) die "unsafe SUBSCRIPTION_APPLY_ROOT: $allowed_root" ;;
  esac
  allowed_root=${allowed_root%/}
  case "$APPLY_PATH" in "$allowed_root"/?*) ;; *) die "SUBSCRIPTION_APPLY_PATH must remain below $allowed_root" ;; esac

  current="$allowed_root"
  [ ! -L "$current" ] || die "live apply root must not be a symbolic link: $current"
  relative=${APPLY_PATH#"$allowed_root"/}
  old_ifs=$IFS
  IFS=/
  set -- $relative
  IFS=$old_ifs
  for segment in "$@"; do
    current="$current/$segment"
    [ ! -L "$current" ] || die "live apply path must not traverse a symbolic link: $current"
  done
}

file_sha256() {
  target=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$target" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$target" | awk '{print $NF}'
  else
    return 1
  fi
}

validate_runtime_evidence_path() {
  case "$RUNTIME_EVIDENCE" in
    /*) ;;
    *) die "SUBSCRIPTION_RUNTIME_EVIDENCE must be absolute" ;;
  esac
  case "$RUNTIME_EVIDENCE" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*) die "unsafe SUBSCRIPTION_RUNTIME_EVIDENCE" ;; esac
  case "$RUNTIME_EVIDENCE" in
    /tmp/home-edge-*|/jffs/home-edge-bootstrap/?*) ;;
    *) die "SUBSCRIPTION_RUNTIME_EVIDENCE must remain in a project-owned path" ;;
  esac
  current=""
  relative=${RUNTIME_EVIDENCE#/}
  old_ifs=$IFS
  IFS=/
  set -- $relative
  IFS=$old_ifs
  for segment in "$@"; do
    current="$current/$segment"
    [ ! -L "$current" ] || die "SUBSCRIPTION_RUNTIME_EVIDENCE must not traverse a symlink: $current"
  done
}

write_runtime_evidence() {
  validate_runtime_evidence_path
  [ -r "$RUNTIME_EVIDENCE_HELPER" ] || { say "subscription_runtime_evidence=unavailable_helper"; return 0; }
  runtime_identity=${SUBSCRIPTION_RUNTIME_PROCESS_IDENTITY:-}
  runtime_start=${SUBSCRIPTION_RUNTIME_PROCESS_START_EPOCH:-}
  if [ -z "$runtime_identity" ] || [ -z "$runtime_start" ]; then
    runtime_output=$(sh "$RUNTIME_EVIDENCE_HELPER" observe 2>/dev/null || true)
    runtime_identity=$(printf '%s\n' "$runtime_output" | sed -n 's/^runtime_process_identity=//p' | head -n 1)
    runtime_start=$(printf '%s\n' "$runtime_output" | sed -n 's/^runtime_process_start_epoch=//p' | head -n 1)
  fi
  case "$runtime_identity" in ""|unknown) say "subscription_runtime_evidence=unavailable_runtime_identity"; return 0 ;; esac
  case "$runtime_start" in ""|unknown|*[!0-9]*) say "subscription_runtime_evidence=unavailable_runtime_identity"; return 0 ;; esac
  HOME_EDGE_SUB_CACHE="$SUB_CACHE" HOME_EDGE_SUB_APPLY_PATH="$APPLY_PATH" HOME_EDGE_SUB_EVIDENCE="$RUNTIME_EVIDENCE" \
    HOME_EDGE_RUNTIME_PROCESS_IDENTITY="$runtime_identity" HOME_EDGE_RUNTIME_PROCESS_START_EPOCH="$runtime_start" \
    sh "$RUNTIME_EVIDENCE_HELPER" attest || die "cannot attest runtime subscription reload"
}

validate_mihomo_semantics() {
  f="$1"
  validator="$MIHOMO_BIN"
  if [ -n "$validator" ]; then
    [ -x "$validator" ] || die "SUBSCRIPTION_MIHOMO_BIN is not executable: $validator"
  else
    for candidate in /jffs/home-edge-bootstrap/bundle/mihomo-linux-arm64 /jffs/ShellCrash/CrashCore /jffs/ShellClash/CrashCore; do
      [ -x "$candidate" ] && { validator="$candidate"; break; }
    done
  fi

  if [ -z "$validator" ]; then
    say "subscription_semantic_validation=unavailable"
    if [ "$DRY_RUN" = "0" ] && [ -n "$APPLY_PATH" ]; then
      die "live apply requires an executable Mihomo validator"
    fi
    return 0
  fi
  "$validator" -t -f "$f" >/dev/null 2>&1 || die "Mihomo rejected the downloaded configuration"
  say "subscription_semantic_validation=ok"
}

apply_live_profile() {
  [ -n "$APPLY_PATH" ] || { say "subscription_apply=cache_only"; return 0; }
  validate_apply_path
  validate_runtime_evidence_path
  rm -f "$RUNTIME_EVIDENCE" 2>/dev/null || true

  apply_dir=$(dirname "$APPLY_PATH")
  mkdir -p "$apply_dir" "$BACKUP_DIR" 2>/dev/null || die "cannot prepare live apply directory: $apply_dir"
  chmod 700 "$apply_dir" "$BACKUP_DIR" 2>/dev/null || die "cannot secure live apply directories"

  had_live=0
  live_backup=""
  if [ -s "$APPLY_PATH" ]; then
    had_live=1
    live_backup="$BACKUP_DIR/live.$(date +%Y%m%d%H%M%S).$$.yaml"
    cp "$APPLY_PATH" "$live_backup" || die "live config backup failed"
    chmod 600 "$live_backup" 2>/dev/null || die "cannot secure live config backup"
  fi

  tmp_live=$(mktemp "$apply_dir/.home-edge-live.XXXXXX") || die "cannot create secure live config staging file"
  cp "$SUB_CACHE" "$tmp_live" || { rm -f "$tmp_live"; die "live config staging failed"; }
  chmod 600 "$tmp_live" 2>/dev/null || { rm -f "$tmp_live"; die "cannot secure live config staging file"; }
  mv "$tmp_live" "$APPLY_PATH" || { rm -f "$tmp_live"; die "apply failed: $APPLY_PATH"; }
  chmod 600 "$APPLY_PATH" 2>/dev/null || die "cannot secure live config"
  say "subscription_apply=updated"
  say "subscription_apply_path=$APPLY_PATH"

  if [ -n "$RELOAD_CMD" ]; then
    log "running live reload command"
    if sh -c "$RELOAD_CMD" >>"$LOG" 2>&1; then
      say "subscription_reload=ok"
      write_runtime_evidence
    else
      if [ "$had_live" = "1" ] && [ -n "$live_backup" ] && [ -s "$live_backup" ]; then
        cp "$live_backup" "$APPLY_PATH" || die "reload failed and live config restore failed"
        chmod 600 "$APPLY_PATH" 2>/dev/null || die "reload failed and restored config permissions could not be secured"
        say "subscription_apply=restored_after_reload_failure"
      else
        rm -f "$APPLY_PATH" || die "reload failed and the newly created live config could not be removed"
        say "subscription_apply=removed_after_reload_failure"
      fi
      log "reloading restored live state"
      sh -c "$RELOAD_CMD" >>"$LOG" 2>&1 || die "reload failed and restored state could not be reloaded"
      say "subscription_rollback_reload=ok"
      die "reload command failed; prior live state restored"
    fi
  else
    say "subscription_reload=not_configured"
  fi
}

if [ -n "$APPLY_PATH" ]; then
  validate_apply_path
  validate_runtime_evidence_path
fi

[ -r "$SUB_FILE" ] || die "subscription file not found: $SUB_FILE"
url=$(sed -n '1p' "$SUB_FILE" | tr -d '\r')
[ -n "$url" ] || die "subscription URL is empty"

case "$MIN_BYTES" in
  ""|*[!0-9]*|0) MIN_BYTES=64 ;;
esac
case "$MAX_BYTES" in
  ""|*[!0-9]*|0) MAX_BYTES=10485760 ;;
esac
[ "$MAX_BYTES" -ge "$MIN_BYTES" ] || die "SUBSCRIPTION_MAX_BYTES must be at least SUBSCRIPTION_MIN_BYTES"

acquire_lock
rotate_log
cache_dir=$(dirname "$SUB_CACHE")
mkdir -p "$cache_dir" "$BACKUP_DIR" 2>/dev/null || die "cannot prepare subscription cache directories"
chmod 700 "$cache_dir" "$BACKUP_DIR" 2>/dev/null || die "cannot secure subscription cache directories"
tmp=$(mktemp "$cache_dir/.subscription.XXXXXX") || die "cannot create secure subscription staging file"

fetch_subscription
validate_subscription "$tmp"
validate_mihomo_semantics "$tmp"

if [ "$DRY_RUN" = "1" ]; then
  size=$(wc -c < "$tmp" | tr -d ' ')
  say "subscription_dry_run=ok"
  say "subscription_bytes=$size"
  say "subscription_cache=unchanged"
  exit 0
fi

if [ -s "$SUB_CACHE" ]; then
  cache_backup="$BACKUP_DIR/subscription.$(date +%Y%m%d%H%M%S).$$.yaml"
  cp "$SUB_CACHE" "$cache_backup" || die "backup failed"
  chmod 600 "$cache_backup" 2>/dev/null || die "cannot secure subscription backup"
fi
mv "$tmp" "$SUB_CACHE" || die "cache update failed"
tmp=""
chmod 600 "$SUB_CACHE" 2>/dev/null || die "cannot secure subscription cache"
size=$(wc -c < "$SUB_CACHE" | tr -d ' ')
say "subscription_cache=updated"
say "subscription_cache_path=$SUB_CACHE"
say "subscription_bytes=$size"

apply_live_profile
prune_backups
