#!/bin/sh
# Prepare, install, inspect, or roll back a ShellCrash user.yaml DNS override.
# The default action is plan: render and semantically validate without changing live state.
set -u
umask 077

ACTION="${HOME_EDGE_DNS_ACTION:-plan}"
SHELLCRASH_DIR="${HOME_EDGE_SHELLCRASH_DIR:-/jffs/ShellCrash}"
STATE_ROOT="${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}"
USER_YAML="${HOME_EDGE_DNS_USER_YAML:-$SHELLCRASH_DIR/yamls/user.yaml}"
RUNTIME_CONFIG="${HOME_EDGE_DNS_RUNTIME_CONFIG:-}"
MIHOMO_BIN="${HOME_EDGE_DNS_MIHOMO_BIN:-}"
MIHOMO_DATA_DIR="${HOME_EDGE_DNS_MIHOMO_DATA_DIR:-$SHELLCRASH_DIR}"
SECURE_UPSTREAMS="${HOME_EDGE_DNS_SECURE_UPSTREAMS:-https://1.1.1.1/dns-query, https://dns.google/dns-query}"
if [ -n "${HOME_EDGE_DNS_LOCAL_UPSTREAMS:-}" ]; then
  LOCAL_UPSTREAMS=$HOME_EDGE_DNS_LOCAL_UPSTREAMS
elif [ -n "${HOME_EDGE_DNS_DEFAULT_RESOLVER:-}" ]; then
  LOCAL_UPSTREAMS=$HOME_EDGE_DNS_DEFAULT_RESOLVER
else
  LOCAL_UPSTREAMS="https://223.5.5.5/dns-query, https://1.12.12.12/dns-query"
fi
CANDIDATE_DIR="${HOME_EDGE_DNS_CANDIDATE_DIR:-$STATE_ROOT/candidates}"
BACKUP_DIR="${HOME_EDGE_DNS_BACKUP_DIR:-$STATE_ROOT/backups/shellcrash-user-dns}"
STATE_DIR="${HOME_EDGE_DNS_STATE_DIR:-$STATE_ROOT/lifecycle}"
STATE_FILE="${HOME_EDGE_DNS_STATE_FILE:-$STATE_DIR/shellcrash-user-dns.env}"
BEGIN_MARKER="# BEGIN home-edge-bootstrap shellcrash-user-dns/v1"
END_MARKER="# END home-edge-bootstrap shellcrash-user-dns/v1"
LEGACY_MARKER="# home-edge-bootstrap-owned: shellcrash-user-dns/v1"

tmp_candidate=""
tmp_merged=""
tmp_core=""
state_tmp=""

say() { printf '%s\n' "$*"; }
die() { printf 'configure-shellcrash-dns: ERROR: %s\n' "$*" >&2; exit 1; }

secure_temp_helper=${HOME_EDGE_SECURE_TEMP_HELPER:-}
if [ -z "$secure_temp_helper" ]; then
  source_dir=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd) ||
    die "cannot resolve helper directory"
  secure_temp_helper="$source_dir/home-edge-secure-temp.sh"
  [ -r "$secure_temp_helper" ] || secure_temp_helper=/jffs/scripts/home-edge-secure-temp.sh
fi
[ -r "$secure_temp_helper" ] || die "project secure temporary-path helper is unavailable"
. "$secure_temp_helper"

cleanup() {
  [ -z "$tmp_candidate" ] || rm -f "$tmp_candidate" 2>/dev/null || true
  [ -z "$tmp_merged" ] || rm -f "$tmp_merged" 2>/dev/null || true
  [ -z "$tmp_core" ] || rm -f "$tmp_core" 2>/dev/null || true
  [ -z "$state_tmp" ] || rm -f "$state_tmp" 2>/dev/null || true
}
handle_signal() {
  cleanup
  trap - EXIT
  exit 130
}
trap cleanup EXIT
trap handle_signal HUP INT TERM

validate_absolute_path() {
  name=$1
  value=$2
  case "$value" in
    /*) ;;
    *) die "$name must be absolute" ;;
  esac
  case "$value" in
    /|*[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*)
      die "unsafe $name"
      ;;
  esac
}

validate_absolute_path HOME_EDGE_SHELLCRASH_DIR "$SHELLCRASH_DIR"
validate_absolute_path HOME_EDGE_STATE_ROOT "$STATE_ROOT"
validate_absolute_path HOME_EDGE_DNS_USER_YAML "$USER_YAML"
validate_absolute_path HOME_EDGE_DNS_MIHOMO_DATA_DIR "$MIHOMO_DATA_DIR"
validate_absolute_path HOME_EDGE_DNS_CANDIDATE_DIR "$CANDIDATE_DIR"
validate_absolute_path HOME_EDGE_DNS_BACKUP_DIR "$BACKUP_DIR"
validate_absolute_path HOME_EDGE_DNS_STATE_DIR "$STATE_DIR"
validate_absolute_path HOME_EDGE_DNS_STATE_FILE "$STATE_FILE"

case "$ACTION" in
  plan|apply|status|rollback) ;;
  *) die "HOME_EDGE_DNS_ACTION must be plan, apply, status, or rollback" ;;
esac

printf '%s\n' "$SECURE_UPSTREAMS" |
  grep -Eq '^https://[A-Za-z0-9.:-]+(/[A-Za-z0-9._~/?=-]*)?(, https://[A-Za-z0-9.:-]+(/[A-Za-z0-9._~/?=-]*)?)*$' ||
  die "HOME_EDGE_DNS_SECURE_UPSTREAMS must be a comma-space separated HTTPS resolver list"
printf '%s\n' "$LOCAL_UPSTREAMS" |
  grep -Eq '^((https://[A-Za-z0-9.:-]+(/[A-Za-z0-9._~/?=-]*)?)|([0-9]{1,3}\.){3}[0-9]{1,3})(, ((https://[A-Za-z0-9.:-]+(/[A-Za-z0-9._~/?=-]*)?)|([0-9]{1,3}\.){3}[0-9]{1,3}))*$' ||
  die "HOME_EDGE_DNS_LOCAL_UPSTREAMS must be a comma-space separated HTTPS or IPv4 resolver list"
YAML_UPSTREAMS=$(printf '%s\n' "$SECURE_UPSTREAMS" | sed 's/, /", "/g')
YAML_LOCAL_UPSTREAMS=$(printf '%s\n' "$LOCAL_UPSTREAMS" | sed 's/, /", "/g')

file_sha256() {
  target=$1
  if which sha256sum >/dev/null 2>&1; then
    sha256sum "$target" | awk '{print $1}'
  elif which openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$target" | awk '{print $NF}'
  else
    return 1
  fi
}

discover_runtime_config() {
  [ -z "$RUNTIME_CONFIG" ] || {
    validate_absolute_path HOME_EDGE_DNS_RUNTIME_CONFIG "$RUNTIME_CONFIG"
    [ -s "$RUNTIME_CONFIG" ] || die "runtime config is unavailable"
    return 0
  }

  if which pidof >/dev/null 2>&1; then
    for pid in $(pidof CrashCore mihomo clash 2>/dev/null || true); do
      candidate=$(tr '\000' '\n' <"/proc/$pid/cmdline" 2>/dev/null |
        awk 'take { print; exit } $0 == "-f" || $0 == "--config" { take=1; next }')
      case "$candidate" in
        /*)
          if [ -s "$candidate" ]; then
            RUNTIME_CONFIG=$candidate
            return 0
          fi
          ;;
      esac
    done
  fi

  for candidate in /tmp/ShellCrash/config.yaml "$SHELLCRASH_DIR/config.yaml"; do
    if [ -s "$candidate" ]; then
      RUNTIME_CONFIG=$candidate
      return 0
    fi
  done
  die "active ShellCrash runtime config could not be discovered"
}

resolve_validator() {
  if [ -n "$MIHOMO_BIN" ]; then
    validate_absolute_path HOME_EDGE_DNS_MIHOMO_BIN "$MIHOMO_BIN"
    [ -x "$MIHOMO_BIN" ] || die "HOME_EDGE_DNS_MIHOMO_BIN is not executable"
    return 0
  fi

  for candidate in "$SHELLCRASH_DIR/CrashCore" /tmp/ShellCrash/CrashCore; do
    if [ -x "$candidate" ]; then
      MIHOMO_BIN=$candidate
      return 0
    fi
  done

  if [ -s "$SHELLCRASH_DIR/CrashCore.gz" ] && which gzip >/dev/null 2>&1; then
    tmp_core=$(home_edge_secure_temp /tmp/home-edge-dns-core.XXXXXX) ||
      die "cannot allocate temporary Mihomo validator"
    gzip -dc "$SHELLCRASH_DIR/CrashCore.gz" >"$tmp_core" ||
      die "cannot decompress Mihomo validator"
    chmod 700 "$tmp_core" 2>/dev/null || die "cannot secure Mihomo validator"
    MIHOMO_BIN=$tmp_core
    return 0
  fi
  die "Mihomo validator is unavailable"
}

render_candidate() {
  discover_runtime_config
  [ -d "$CANDIDATE_DIR" ] || mkdir -p "$CANDIDATE_DIR" ||
    die "cannot create DNS candidate directory"
  chmod 700 "$CANDIDATE_DIR" 2>/dev/null || die "cannot secure DNS candidate directory"
  tmp_candidate=$(home_edge_secure_temp "$CANDIDATE_DIR/.shellcrash-user-dns.XXXXXX") ||
    die "cannot allocate DNS candidate"

  {
    printf '%s\n' "$BEGIN_MARKER"
    awk -v local_upstreams="$YAML_LOCAL_UPSTREAMS" -v secure_upstreams="$YAML_UPSTREAMS" '
      BEGIN { in_dns=0; found_dns=0; skip_value=0; emitted_follow=0 }
      /^dns:[[:space:]]*($|#)/ {
        in_dns=1
        found_dns=1
        print "dns:"
        print "  default-nameserver: [ \"" local_upstreams "\" ]"
        print "  direct-nameserver: [ \"" local_upstreams "\" ]"
        print "  proxy-server-nameserver: [ \"" local_upstreams "\" ]"
        print "  nameserver: [ \"" secure_upstreams "\" ]"
        next
      }
      !in_dns { next }
      /^[^[:space:]#][^:]*:/ { exit }
      {
        if (skip_value) {
          if ($0 ~ /^    / || $0 ~ /^[[:space:]]*$/ || $0 ~ /^  #/) next
          skip_value=0
        }
        if ($0 ~ /^  (default-nameserver|direct-nameserver|proxy-server-nameserver|nameserver|nameserver-policy|fallback|fallback-filter)[[:space:]]*:/) {
          skip_value=1
          next
        }
        if ($0 ~ /^  direct-nameserver-follow-policy[[:space:]]*:/) {
          if (!emitted_follow) print "  direct-nameserver-follow-policy: false"
          emitted_follow=1
          next
        }
        print
      }
      END {
        if (found_dns && !emitted_follow) print "  direct-nameserver-follow-policy: false"
      }
    ' "$RUNTIME_CONFIG"
    printf '%s\n' "$END_MARKER"
  } >"$tmp_candidate" || die "cannot render DNS candidate"

  grep -q '^dns:' "$tmp_candidate" || die "runtime config has no DNS section"
  chmod 600 "$tmp_candidate" 2>/dev/null || die "cannot secure DNS candidate"

  ! grep -q '^  nameserver-policy:' "$tmp_candidate" ||
    die "DNS candidate retained the unsafe CN resolver policy"
  ! grep -Eq '^  (fallback|fallback-filter):' "$tmp_candidate" ||
    die "DNS candidate retained fallback resolvers"
  ! grep -q 'interface-name:' "$tmp_candidate" ||
    die "DNS candidate retained a fixed interface binding"
  ! grep -q '^secret:' "$tmp_candidate" ||
    die "DNS candidate unexpectedly contains a controller secret"
}

validate_candidate() {
  resolve_validator
  [ -d "$MIHOMO_DATA_DIR" ] || die "Mihomo data directory is unavailable"
  [ ! -L "$MIHOMO_DATA_DIR" ] || die "Mihomo data directory must not be a symbolic link"
  tmp_merged=$(home_edge_secure_temp /tmp/home-edge-dns-merged.XXXXXX) ||
    die "cannot allocate merged validation config"
  awk '
    BEGIN { skip_dns=0 }
    /^dns:/ { skip_dns=1; next }
    skip_dns && /^[^[:space:]#][^:]*:/ { skip_dns=0 }
    skip_dns { next }
    { print }
  ' "$RUNTIME_CONFIG" >"$tmp_merged" || die "cannot stage merged validation config"
  printf '\n' >>"$tmp_merged"
  sed '1d;$d' "$tmp_candidate" >>"$tmp_merged" ||
    die "cannot append DNS override to merged validation config"
  chmod 600 "$tmp_merged" 2>/dev/null || die "cannot secure merged validation config"
  "$MIHOMO_BIN" -d "$MIHOMO_DATA_DIR" -t -f "$tmp_merged" >/dev/null 2>&1 ||
    die "Mihomo rejected the DNS override"
}

stage_state() {
  prior_state=$1
  backup_path=$2
  applied_sha=$3
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" || die "cannot create DNS state directory"
  chmod 700 "$STATE_DIR" 2>/dev/null || die "cannot secure DNS state directory"
  state_tmp=$(home_edge_secure_temp "$STATE_DIR/.shellcrash-user-dns-state.XXXXXX") ||
    die "cannot allocate DNS state file"
  {
    printf 'state_schema_version=1\n'
    printf 'dns_override_state=applied\n'
    printf 'dns_user_yaml=%s\n' "$USER_YAML"
    printf 'dns_prior_state=%s\n' "$prior_state"
    printf 'dns_backup_path=%s\n' "$backup_path"
    printf 'dns_applied_sha256=%s\n' "$applied_sha"
  } >"$state_tmp" || { rm -f "$state_tmp"; die "cannot write DNS state"; }
  chmod 600 "$state_tmp" 2>/dev/null || { rm -f "$state_tmp"; die "cannot secure DNS state"; }
}

restore_prior_user() {
  restore_prior_state=$1
  restore_backup_path=$2
  case "$restore_prior_state" in
    absent)
      rm -f "$USER_YAML"
      ;;
    present)
      restore_tmp=$(home_edge_secure_temp "$(dirname "$USER_YAML")/.home-edge-user-dns-restore.XXXXXX") ||
        return 1
      cp "$restore_backup_path" "$restore_tmp" &&
        chmod 600 "$restore_tmp" 2>/dev/null &&
        mv "$restore_tmp" "$USER_YAML" || {
          rm -f "$restore_tmp" 2>/dev/null || true
          return 1
        }
      ;;
    *) return 1 ;;
  esac
}

apply_candidate() {
  user_dir=$(dirname "$USER_YAML")
  [ -d "$user_dir" ] || mkdir -p "$user_dir" || die "cannot create ShellCrash YAML directory"
  [ ! -L "$user_dir" ] || die "ShellCrash YAML directory must not be a symbolic link"
  [ ! -L "$USER_YAML" ] || die "ShellCrash user.yaml must not be a symbolic link"

  prior_state=absent
  backup_path=""
  if [ -e "$USER_YAML" ]; then
    [ -f "$USER_YAML" ] && [ -r "$USER_YAML" ] || die "existing user.yaml is not a readable regular file"
    prior_state=present
    mkdir -p "$BACKUP_DIR" || die "cannot create DNS backup directory"
    chmod 700 "$BACKUP_DIR" 2>/dev/null || die "cannot secure DNS backup directory"
    backup_path="$BACKUP_DIR/user.$(date +%Y%m%d%H%M%S).$$.yaml"
    cp "$USER_YAML" "$backup_path" || die "cannot back up existing user.yaml"
    chmod 600 "$backup_path" 2>/dev/null || die "cannot secure DNS backup"
  fi

  user_tmp=$(home_edge_secure_temp "$user_dir/.home-edge-user-dns.XXXXXX") ||
    die "cannot allocate user.yaml staging file"
  if [ "$prior_state" = present ]; then
    awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" -v legacy="$LEGACY_MARKER" '
      BEGIN { in_owned=0; seen_begin=0; seen_end=0; skip_dns=0; invalid=0 }
      $0 == begin {
        if (in_owned || seen_begin > 0) { invalid=1; exit }
        in_owned=1
        seen_begin=1
        next
      }
      $0 == end {
        if (!in_owned || seen_end > 0) { invalid=1; exit }
        in_owned=0
        seen_end=1
        next
      }
      in_owned { next }
      $0 == legacy { next }
      skip_dns {
        if ($0 ~ /^[^[:space:]#][^:]*:/) {
          skip_dns=0
        } else {
          next
        }
      }
      /^dns:[[:space:]]*($|#)/ {
        skip_dns=1
        next
      }
      { print }
      END {
        if (in_owned || seen_begin != seen_end || invalid) exit 41
      }
    ' "$USER_YAML" >"$user_tmp" || {
      rm -f "$user_tmp"
      die "existing user.yaml contains a malformed managed DNS block"
    }
  fi
  {
    printf '\n'
    cat "$tmp_candidate"
  } >>"$user_tmp" || { rm -f "$user_tmp"; die "cannot stage user.yaml"; }
  chmod 600 "$user_tmp" 2>/dev/null || { rm -f "$user_tmp"; die "cannot secure user.yaml"; }
  applied_sha=$(file_sha256 "$user_tmp") || { rm -f "$user_tmp"; die "cannot hash staged user.yaml"; }
  stage_state "$prior_state" "$backup_path" "$applied_sha"
  mv "$user_tmp" "$USER_YAML" || {
    rm -f "$user_tmp" "$state_tmp"
    state_tmp=""
    die "cannot commit user.yaml"
  }
  if ! mv "$state_tmp" "$STATE_FILE"; then
    rm -f "$state_tmp" 2>/dev/null || true
    state_tmp=""
    if restore_prior_user "$prior_state" "$backup_path"; then
      die "cannot commit DNS state; restored prior user.yaml"
    fi
    die "cannot commit DNS state and prior user.yaml restoration failed"
  fi
  state_tmp=""
  say "dns_override_state=applied"
  say "dns_override_restart_required=1"
  say "dns_override_sha256=$applied_sha"
}

show_status() {
  if [ ! -e "$USER_YAML" ]; then
    say "dns_override_state=absent"
    return 0
  fi
  if [ ! -f "$USER_YAML" ] || [ -L "$USER_YAML" ]; then
    say "dns_override_state=invalid"
    return 1
  fi
  if ! grep -Fxq "$BEGIN_MARKER" "$USER_YAML" || ! grep -Fxq "$END_MARKER" "$USER_YAML"; then
    say "dns_override_state=unmanaged"
    return 0
  fi
  current_sha=$(file_sha256 "$USER_YAML" 2>/dev/null || true)
  expected_sha=$(sed -n 's/^dns_applied_sha256=//p' "$STATE_FILE" 2>/dev/null | head -n 1)
  if [ -n "$current_sha" ] && [ "$current_sha" = "$expected_sha" ]; then
    say "dns_override_state=applied"
  else
    say "dns_override_state=drift"
  fi
  say "dns_override_sha256=${current_sha:-unavailable}"
}

rollback_override() {
  [ -s "$STATE_FILE" ] || die "DNS override state is unavailable"
  prior_state=$(sed -n 's/^dns_prior_state=//p' "$STATE_FILE" | head -n 1)
  backup_path=$(sed -n 's/^dns_backup_path=//p' "$STATE_FILE" | head -n 1)
  recorded_user_yaml=$(sed -n 's/^dns_user_yaml=//p' "$STATE_FILE" | head -n 1)
  [ "$recorded_user_yaml" = "$USER_YAML" ] || die "DNS state does not match the configured user.yaml"
  [ -f "$USER_YAML" ] && [ ! -L "$USER_YAML" ] &&
    grep -Fxq "$BEGIN_MARKER" "$USER_YAML" &&
    grep -Fxq "$END_MARKER" "$USER_YAML" ||
    die "current user.yaml is not the managed DNS override"

  if [ "$prior_state" = present ]; then
    validate_absolute_path dns_backup_path "$backup_path"
    [ -f "$backup_path" ] && [ -r "$backup_path" ] && [ ! -L "$backup_path" ] ||
      die "DNS backup is unavailable"
  elif [ "$prior_state" != absent ]; then
    die "invalid DNS prior state"
  fi

  rollback_current=$(home_edge_secure_temp "$(dirname "$USER_YAML")/.home-edge-user-dns-current.XXXXXX") ||
    die "cannot stage current managed user.yaml"
  cp "$USER_YAML" "$rollback_current" ||
    { rm -f "$rollback_current"; die "cannot preserve current managed user.yaml"; }
  chmod 600 "$rollback_current" 2>/dev/null ||
    { rm -f "$rollback_current"; die "cannot secure current managed user.yaml"; }

  state_tmp=$(home_edge_secure_temp "$STATE_DIR/.shellcrash-user-dns-state.XXXXXX") ||
    { rm -f "$rollback_current"; die "cannot allocate rolled-back state"; }
  {
    sed '/^dns_override_state=/d' "$STATE_FILE"
    printf 'dns_override_state=rolled_back\n'
  } >"$state_tmp" || {
    rm -f "$rollback_current" "$state_tmp"
    state_tmp=""
    die "cannot write rolled-back state"
  }
  chmod 600 "$state_tmp" 2>/dev/null || {
    rm -f "$rollback_current" "$state_tmp"
    state_tmp=""
    die "cannot secure rolled-back state"
  }

  case "$prior_state" in
    absent)
      rm -f "$USER_YAML" || die "cannot remove managed user.yaml"
      ;;
    present)
      restore_prior_user present "$backup_path" || die "cannot restore prior user.yaml"
      ;;
  esac

  if ! mv "$state_tmp" "$STATE_FILE"; then
    rm -f "$state_tmp" 2>/dev/null || true
    state_tmp=""
    rollback_restore=$(home_edge_secure_temp "$(dirname "$USER_YAML")/.home-edge-user-dns-restore.XXXXXX") ||
      die "cannot commit rolled-back state and cannot allocate managed restore"
    cp "$rollback_current" "$rollback_restore" &&
      chmod 600 "$rollback_restore" 2>/dev/null &&
      mv "$rollback_restore" "$USER_YAML" || {
        rm -f "$rollback_restore" "$rollback_current" 2>/dev/null || true
        die "cannot commit rolled-back state and managed user.yaml restoration failed"
      }
    rm -f "$rollback_current"
    die "cannot commit rolled-back state; restored managed user.yaml"
  fi
  state_tmp=""
  rm -f "$rollback_current"
  say "dns_override_state=rolled_back"
  say "dns_override_restart_required=1"
}

case "$ACTION" in
  status)
    show_status
    ;;
  rollback)
    rollback_override
    ;;
  plan|apply)
    render_candidate
    validate_candidate
    candidate_sha=$(file_sha256 "$tmp_candidate") || die "cannot hash DNS candidate"
    say "dns_candidate_validation=ok"
    say "dns_candidate_sha256=$candidate_sha"
    if [ "$ACTION" = apply ]; then
      apply_candidate
    else
      say "dns_override_state=planned"
      say "dns_override_restart_required=0"
    fi
    ;;
esac
