#!/bin/sh
# Manage a bounded ShellCrash service-routing profile without restarting the runtime.
# Default action is plan. Apply is atomic and rollback uses the recorded backup.
set -u
umask 077

ACTION="${HOME_EDGE_SERVICE_RULES_ACTION:-plan}"
PROFILE="${HOME_EDGE_SERVICE_PROFILE:-openai}"
SHELLCRASH_DIR="${HOME_EDGE_SHELLCRASH_DIR:-/jffs/ShellCrash}"
RULES_FILE="${HOME_EDGE_SERVICE_RULES_FILE:-$SHELLCRASH_DIR/yamls/rules.yaml}"
RUNTIME_CONFIG="${HOME_EDGE_SERVICE_RUNTIME_CONFIG:-/tmp/ShellCrash/config.yaml}"
STATE_ROOT="${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}"
STATE_DIR="${HOME_EDGE_SERVICE_RULES_STATE_DIR:-$STATE_ROOT/lifecycle}"
STATE_FILE="${HOME_EDGE_SERVICE_RULES_STATE_FILE:-$STATE_DIR/service-rules-$PROFILE.env}"
BACKUP_DIR="${HOME_EDGE_SERVICE_RULES_BACKUP_DIR:-$STATE_ROOT/backups/service-rules/$PROFILE}"
GROUP="${HOME_EDGE_SERVICE_GROUP:-}"
PROFILE_SOURCE=""
PROFILE_REVIEWED_ON="2026-07-30"
BEGIN_MARKER="# BEGIN home-edge-bootstrap service-rules/$PROFILE/v1"
END_MARKER="# END home-edge-bootstrap service-rules/$PROFILE/v1"

case "$PROFILE" in
  openai)
    PROFILE_SOURCE="https://help.openai.com/en/articles/9247338-network-recommendations-for-chatgpt-errors-on-web-and-apps"
    ;;
  asus-global-account)
    PROFILE_SOURCE="https://account.asus.com/"
    ;;
esac

tmp_base=""
tmp_profile=""
tmp_candidate=""
tmp_groups=""
tmp_state=""
tmp_original=""
tmp_prior_block=""
tmp_restore=""
tmp_rollback_base=""
pending_backup=""

say() { printf '%s\n' "$*"; }
die() {
  printf 'configure-shellcrash-service-rules: ERROR: %s\n' "$*" >&2
  exit 1
}

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
  for item in "$tmp_base" "$tmp_profile" "$tmp_candidate" "$tmp_groups" "$tmp_state" "$tmp_original" "$tmp_prior_block" "$tmp_restore" "$tmp_rollback_base" "$pending_backup"; do
    [ -z "$item" ] || rm -f "$item" 2>/dev/null || true
  done
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
  case "$value" in /*) ;; *) die "$name must be absolute" ;; esac
  case "$value" in
    /|*[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.|*//*)
      die "unsafe $name"
      ;;
  esac
}

validate_group() {
  [ -n "$GROUP" ] || die "service policy group is empty"
  case "$GROUP" in *','*) die "service policy group contains an unsupported delimiter" ;; esac
  single_line_group=$(printf '%s' "$GROUP" | tr -d '\r\n')
  [ "$single_line_group" = "$GROUP" ] ||
    die "service policy group contains an unsupported delimiter"
}

render_profile() {
  case "$PROFILE" in
    openai)
      cat <<'EOF'
DOMAIN-SUFFIX,auth.openai.com
DOMAIN-SUFFIX,chatgpt.com
DOMAIN-SUFFIX,ct.sendgrid.net
DOMAIN-SUFFIX,intercom.io
DOMAIN-SUFFIX,intercomcdn.com
DOMAIN-SUFFIX,oaistatic.com
DOMAIN-SUFFIX,oaiusercontent.com
DOMAIN-SUFFIX,openai.com
DOMAIN-SUFFIX,oaistatsig.com
DOMAIN,cdn.openaimerge.com
DOMAIN,cdn.workos.com
DOMAIN,challenges.cloudflare.com
DOMAIN,forwarder.workos.com
DOMAIN,humb.apple.com
DOMAIN,images.workoscdn.com
DOMAIN,js.stripe.com
DOMAIN,o207216.ingest.sentry.io
DOMAIN,o33249.ingest.sentry.io
DOMAIN,rum.browser-intake-datadoghq.com
DOMAIN,setup.workos.com
DOMAIN,workos.imgix.net
EOF
      ;;
    asus-global-account)
      cat <<'EOF'
DOMAIN,nomos.asus.com
EOF
      ;;
    *) die "unsupported service profile" ;;
  esac
}

strip_managed_block() {
  input=$1
  output=$2
  [ -e "$input" ] || {
    : >"$output"
    return
  }
  [ -f "$input" ] && [ ! -L "$input" ] || die "rules target must be a regular file"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { if (managed) exit 21; managed=1; seen_begin++; next }
    $0 == end {
      if (!managed) exit 22
      managed=0
      seen_end++
      next
    }
    !managed { print }
    END {
      if (managed || seen_begin != seen_end || seen_begin > 1) exit 23
    }
  ' "$input" >"$output" || die "rules file contains a malformed managed block"
}

extract_managed_block() {
  input=$1
  output=$2
  [ -e "$input" ] || {
    : >"$output"
    return
  }
  [ -f "$input" ] && [ ! -L "$input" ] || die "rules target must be a regular file"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin {
      if (managed) exit 21
      managed=1
      seen_begin++
      print
      next
    }
    $0 == end {
      if (!managed) exit 22
      print
      managed=0
      seen_end++
      next
    }
    managed { print }
    END {
      if (managed || seen_begin != seen_end || seen_begin > 1) exit 23
    }
  ' "$input" >"$output" || die "rules file contains a malformed managed block"
}

discover_group() {
  if [ -n "$GROUP" ]; then
    validate_group
    return
  fi
  [ -s "$RUNTIME_CONFIG" ] || die "active runtime config is unavailable; set HOME_EDGE_SERVICE_GROUP explicitly"
  tmp_groups=$(home_edge_secure_temp /tmp/home-edge-service-groups.XXXXXX) ||
    die "cannot allocate group discovery file"
  awk -F, '
    function trim(value) {
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      return value
    }
    {
      kind=trim($1)
      domain=trim($2)
      group=trim($3)
      if (kind !~ /DOMAIN/ || group == "") next
      if (domain == "chatgpt.com" || domain ~ /(^|\.)openai\.com$/ ||
          domain ~ /(^|\.)oaistatic\.com$/ || domain ~ /(^|\.)oaiusercontent\.com$/ ||
          domain ~ /(^|\.)oaistatsig\.com$/) {
        if (!seen[group]++) print group
      }
    }
  ' "$RUNTIME_CONFIG" >"$tmp_groups"
  group_count=$(awk 'NF { count++ } END { print count + 0 }' "$tmp_groups")
  [ "$group_count" -eq 1 ] ||
    die "could not infer exactly one service policy group; set HOME_EDGE_SERVICE_GROUP explicitly"
  GROUP=$(awk 'NF { print; exit }' "$tmp_groups")
  validate_group
}

prepare_candidate() {
  rules_dir=$(dirname "$RULES_FILE")
  [ -d "$rules_dir" ] || die "ShellCrash rules directory is unavailable"
  tmp_base=$(home_edge_secure_temp "$rules_dir/.home-edge-service-base.XXXXXX") ||
    die "cannot allocate base rules file"
  tmp_profile=$(home_edge_secure_temp "$rules_dir/.home-edge-service-profile.XXXXXX") ||
    die "cannot allocate service profile"
  tmp_candidate=$(home_edge_secure_temp "$rules_dir/.home-edge-service-candidate.XXXXXX") ||
    die "cannot allocate rules candidate"
  tmp_prior_block=$(home_edge_secure_temp "$rules_dir/.home-edge-service-prior-block.XXXXXX") ||
    die "cannot allocate prior service-rules block"

  extract_managed_block "$RULES_FILE" "$tmp_prior_block"
  strip_managed_block "$RULES_FILE" "$tmp_base"
  render_profile >"$tmp_profile"
  grep -Eq '^(DOMAIN|DOMAIN-SUFFIX),[A-Za-z0-9.-]+$' "$tmp_profile" ||
    die "service profile has no valid rules"
  if grep -Ev '^(DOMAIN|DOMAIN-SUFFIX),[A-Za-z0-9.-]+$' "$tmp_profile" | grep -q .; then
    die "service profile contains an invalid rule"
  fi

  rules_required=0
  rules_added=0
  {
    printf '%s\n' "$BEGIN_MARKER"
    while IFS= read -r rule; do
      [ -n "$rule" ] || continue
      rules_required=$((rules_required + 1))
      if grep -Fqx -- "  - $rule,$GROUP" "$tmp_base"; then
        continue
      fi
      printf '  - %s,%s\n' "$rule" "$GROUP"
      rules_added=$((rules_added + 1))
    done <"$tmp_profile"
    printf '%s\n' "$END_MARKER"
    cat "$tmp_base"
  } >"$tmp_candidate" || die "cannot render rules candidate"
  chmod 600 "$tmp_candidate" 2>/dev/null || die "cannot secure rules candidate"
}

prepare_state() {
  prior_file_state=$1
  prior_block_state=$2
  backup_path=$3
  [ -d "$STATE_DIR" ] || mkdir -p "$STATE_DIR" || die "cannot create service-rules state directory"
  chmod 700 "$STATE_DIR" 2>/dev/null || die "cannot secure service-rules state directory"
  tmp_state=$(home_edge_secure_temp "$STATE_DIR/.service-rules-state.XXXXXX") ||
    die "cannot allocate service-rules state"
  {
    printf 'state_schema_version=2\n'
    printf 'service_profile=%s\n' "$PROFILE"
    printf 'service_rules_state=applied\n'
    printf 'service_rules_prior_file_state=%s\n' "$prior_file_state"
    printf 'service_rules_prior_block_state=%s\n' "$prior_block_state"
    printf 'service_rules_backup=%s\n' "$backup_path"
    printf 'service_rules_file=%s\n' "$RULES_FILE"
    printf 'profile_reviewed_on=%s\n' "$PROFILE_REVIEWED_ON"
  } >"$tmp_state"
  chmod 600 "$tmp_state" 2>/dev/null || die "cannot secure service-rules state"
}

status() {
  if [ -f "$RULES_FILE" ] &&
    grep -Fqx "$BEGIN_MARKER" "$RULES_FILE" &&
    grep -Fqx "$END_MARKER" "$RULES_FILE"; then
    say "service_rules_state=applied"
  else
    say "service_rules_state=not_managed"
  fi
  say "service_profile=$PROFILE"
  say "profile_reviewed_on=$PROFILE_REVIEWED_ON"
  say "runtime_reload_state=not_checked"
}

rollback() {
  [ -f "$STATE_FILE" ] && [ ! -L "$STATE_FILE" ] ||
    die "service-rules state is unavailable"
  state_schema=$(awk -F= '$1 == "state_schema_version" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")
  backup_path=$(awk -F= '$1 == "service_rules_backup" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")
  recorded_file=$(awk -F= '$1 == "service_rules_file" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")
  [ "$recorded_file" = "$RULES_FILE" ] || die "recorded rules target does not match"
  case "$backup_path" in "$BACKUP_DIR"/*) ;; "") ;; *) die "recorded backup is outside the managed backup directory" ;; esac

  rules_dir=$(dirname "$RULES_FILE")
  tmp_restore=$(home_edge_secure_temp "$rules_dir/.home-edge-service-rollback.XXXXXX") ||
    die "cannot allocate rollback staging file"
  case "$state_schema" in
    1)
      prior_state=$(awk -F= '$1 == "service_rules_prior_state" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")
      other_managed_count=$(grep -F '# BEGIN home-edge-bootstrap service-rules/' "$RULES_FILE" 2>/dev/null |
        grep -Fvx "$BEGIN_MARKER" | awk 'END { print NR + 0 }')
      [ "$other_managed_count" -eq 0 ] ||
        die "legacy whole-file rollback is unsafe while another managed profile exists"
      case "$prior_state" in
        present)
          [ -f "$backup_path" ] && [ ! -L "$backup_path" ] || die "recorded backup is unavailable"
          cp -p "$backup_path" "$tmp_restore" || die "cannot stage rules backup"
          ;;
        absent)
          : >"$tmp_restore"
          ;;
        *) die "invalid prior rules state" ;;
      esac
      prior_file_state=$prior_state
      ;;
    2)
      prior_file_state=$(awk -F= '$1 == "service_rules_prior_file_state" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")
      prior_block_state=$(awk -F= '$1 == "service_rules_prior_block_state" { print substr($0, index($0, "=") + 1); exit }' "$STATE_FILE")
      tmp_rollback_base=$(home_edge_secure_temp "$rules_dir/.home-edge-service-rollback-base.XXXXXX") ||
        die "cannot allocate rollback base"
      strip_managed_block "$RULES_FILE" "$tmp_rollback_base"
      case "$prior_block_state" in
        present)
          [ -f "$backup_path" ] && [ ! -L "$backup_path" ] || die "recorded block backup is unavailable"
          cat "$backup_path" "$tmp_rollback_base" >"$tmp_restore" || die "cannot stage prior managed block"
          ;;
        absent)
          cat "$tmp_rollback_base" >"$tmp_restore" || die "cannot stage rules without managed block"
          ;;
        *) die "invalid prior managed-block state" ;;
      esac
      rm -f "$tmp_rollback_base"
      tmp_rollback_base=""
      ;;
    *) die "unsupported service-rules state schema" ;;
  esac
  case "$prior_file_state" in present|absent) ;; *) die "invalid prior rules file state" ;; esac
  chmod 600 "$tmp_restore" 2>/dev/null || die "cannot secure rollback staging file"
  if [ -s "$tmp_restore" ] || [ "$prior_file_state" = present ]; then
    mv -f "$tmp_restore" "$RULES_FILE" || die "cannot restore managed service rules"
    tmp_restore=""
  else
    rm -f "$tmp_restore"
    tmp_restore=""
    rm -f "$RULES_FILE" || die "cannot restore absent rules state"
  fi
  rm -f "$STATE_FILE" || die "cannot clear service-rules state"
  say "service_rules_state=rolled_back"
  say "service_profile=$PROFILE"
  say "runtime_reload_state=pending"
}

validate_absolute_path HOME_EDGE_SHELLCRASH_DIR "$SHELLCRASH_DIR"
validate_absolute_path HOME_EDGE_SERVICE_RULES_FILE "$RULES_FILE"
validate_absolute_path HOME_EDGE_SERVICE_RUNTIME_CONFIG "$RUNTIME_CONFIG"
validate_absolute_path HOME_EDGE_STATE_ROOT "$STATE_ROOT"
validate_absolute_path HOME_EDGE_SERVICE_RULES_STATE_DIR "$STATE_DIR"
validate_absolute_path HOME_EDGE_SERVICE_RULES_STATE_FILE "$STATE_FILE"
validate_absolute_path HOME_EDGE_SERVICE_RULES_BACKUP_DIR "$BACKUP_DIR"
case "$STATE_FILE" in "$STATE_DIR"/*) ;; *) die "service-rules state file must be under its state directory" ;; esac
case "$PROFILE" in openai|asus-global-account) ;; *) die "unsupported service profile" ;; esac
case "$ACTION" in plan|apply|status|rollback) ;; *) die "action must be plan, apply, status, or rollback" ;; esac

case "$ACTION" in
  status)
    status
    ;;
  rollback)
    rollback
    ;;
  plan|apply)
    discover_group
    prepare_candidate
    if [ "$ACTION" = plan ]; then
      say "service_rules_state=planned"
      say "service_profile=$PROFILE"
      say "rules_required=$rules_required"
      say "rules_added=$rules_added"
      say "profile_source=$PROFILE_SOURCE"
      say "profile_reviewed_on=$PROFILE_REVIEWED_ON"
      say "runtime_reload_state=not_requested"
      exit 0
    fi

    rules_dir=$(dirname "$RULES_FILE")
    [ ! -L "$RULES_FILE" ] || die "refusing symbolic-link rules target"
    prior_file_state=absent
    prior_block_state=absent
    backup_path=""
    if [ -f "$RULES_FILE" ]; then
      prior_file_state=present
    fi
    if [ -s "$tmp_prior_block" ]; then
      prior_block_state=present
      [ -d "$BACKUP_DIR" ] || mkdir -p "$BACKUP_DIR" || die "cannot create service-rules backup directory"
      chmod 700 "$BACKUP_DIR" 2>/dev/null || die "cannot secure service-rules backup directory"
      backup_path="$BACKUP_DIR/block.$(date +%Y%m%d%H%M%S).$$.yaml"
      cp -p "$tmp_prior_block" "$backup_path" || die "cannot back up existing managed block"
      chmod 600 "$backup_path" 2>/dev/null || die "cannot secure managed-block backup"
      pending_backup=$backup_path
    fi
    tmp_original=$(home_edge_secure_temp "$rules_dir/.home-edge-service-original.XXXXXX") ||
      die "cannot allocate service-rules transaction backup"
    if [ "$prior_file_state" = present ]; then
      cp -p "$RULES_FILE" "$tmp_original" || die "cannot stage service-rules transaction backup"
    else
      : >"$tmp_original"
    fi
    prepare_state "$prior_file_state" "$prior_block_state" "$backup_path"
    if ! mv -f "$tmp_candidate" "$RULES_FILE"; then
      [ -z "$backup_path" ] || rm -f "$backup_path"
      pending_backup=""
      die "cannot commit service rules"
    fi
    tmp_candidate=""
    if ! mv -f "$tmp_state" "$STATE_FILE"; then
      if [ "$prior_file_state" = present ]; then
        mv -f "$tmp_original" "$RULES_FILE" || die "cannot restore rules after state commit failure"
        tmp_original=""
      else
        rm -f "$RULES_FILE" || die "cannot remove rules after state commit failure"
      fi
      [ -z "$backup_path" ] || rm -f "$backup_path"
      pending_backup=""
      die "cannot commit service-rules state"
    fi
    tmp_state=""
    pending_backup=""
    rm -f "$tmp_original"
    tmp_original=""
    say "service_rules_state=applied"
    say "service_profile=$PROFILE"
    say "rules_required=$rules_required"
    say "rules_added=$rules_added"
    say "profile_source=$PROFILE_SOURCE"
    say "profile_reviewed_on=$PROFILE_REVIEWED_ON"
    say "backup_state=ready"
    say "runtime_reload_state=pending"
    ;;
esac
