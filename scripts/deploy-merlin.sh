#!/bin/sh
# Host-side deploy helper for macOS/Linux/Git Bash.
set -u
validate_bool() {
  name="$1"
  value="$2"
  case "$value" in 0|1) ;; *) echo "deploy-merlin: invalid boolean $name=$value; expected 0 or 1" >&2; exit 2 ;; esac
}

router=""
project_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --project-only) project_only=1 ;;
    -*) echo "deploy-merlin: unknown option: $1" >&2; exit 2 ;;
    *) [ -z "$router" ] || { echo 'deploy-merlin: unexpected router argument' >&2; exit 2; }; router=$1 ;;
  esac
  shift
done
router="${router:-${ROUTER:-}}"
if [ -z "$router" ]; then
  echo "usage: sh scripts/deploy-merlin.sh <ssh-user>@<router-ip>" >&2
  echo "       or set ROUTER=<ssh-user>@<router-ip>" >&2
  exit 2
fi

remote_dir="${REMOTE_DIR:-/jffs/home-edge-bootstrap}"
apply="${APPLY:-0}"
runtime_install="${BOOTSTRAP_INSTALL_RUNTIME:-0}"
replace_runtime="${BOOTSTRAP_REPLACE_RUNTIME:-0}"
replace_core="${BOOTSTRAP_REPLACE_CORE:-0}"
replace_project="${BOOTSTRAP_REPLACE_PROJECT:-0}"
project_confirmation="${BOOTSTRAP_PROJECT_CONFIRMATION:-}"
include_bundle="${INCLUDE_BUNDLE:-0}"
if [ "$project_only" = 1 ]; then runtime_install=0; replace_runtime=0; replace_core=0; include_bundle=0; fi
validate_bool APPLY "$apply"
validate_bool BOOTSTRAP_INSTALL_RUNTIME "$runtime_install"
validate_bool BOOTSTRAP_REPLACE_RUNTIME "$replace_runtime"
validate_bool BOOTSTRAP_REPLACE_CORE "$replace_core"
validate_bool INCLUDE_BUNDLE "$include_bundle"
validate_bool BOOTSTRAP_REPLACE_PROJECT "$replace_project"
if [ "$replace_project" = 1 ] || [ -n "$project_confirmation" ]; then
  [ "$replace_project" = 1 ] && [ "$project_confirmation" = REPLACE ] || { echo "Project replacement requires BOOTSTRAP_REPLACE_PROJECT=1 and BOOTSTRAP_PROJECT_CONFIRMATION=REPLACE" >&2; exit 2; }
fi
known_hosts_file="${KNOWN_HOSTS_FILE:-/tmp/home-edge-bootstrap-known-hosts}"
ssh_timeout="${SSH_CONNECT_TIMEOUT_SEC:-8}"
ssh_command="${HOME_EDGE_SSH_COMMAND:-ssh}"
ssh_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=$ssh_timeout -o ConnectionAttempts=1 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts_file}"
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
bundle_dir="${DEPLOY_BUNDLE_DIR:-$repo/bundle}"
archive_items="README.md README.zh-CN.md bootstrap.sh adapters config docs scripts tools"
[ "$include_bundle" = "1" ] && archive_items="$archive_items bundle"
deploy_stage=""
cleanup_host_stage() {
  [ -z "$deploy_stage" ] || rm -rf "$deploy_stage"
}
trap cleanup_host_stage EXIT HUP INT TERM

case "$remote_dir" in
  /jffs/?*) ;;
  /jffs|/jffs/) echo "deploy-merlin: remote dir must not be the JFFS root" >&2; exit 2 ;;
  *) echo "deploy-merlin: remote dir must be under /jffs: $remote_dir" >&2; exit 2 ;;
esac
case "$remote_dir" in
  *[!A-Za-z0-9_./-]*) echo "deploy-merlin: remote dir contains unsupported characters: $remote_dir" >&2; exit 2 ;;
esac
remote_leaf=${remote_dir#/jffs/}
case "$remote_leaf" in
  ""|.|..|*/*) echo "deploy-merlin: remote dir must be one concrete directory below /jffs" >&2; exit 2 ;;
esac

host_bundle_verified=0
runtime_payload_bytes=0
runtime_space_required_kib=0
if [ "$runtime_install" = "1" ]; then
  [ -d "$bundle_dir" ] || {
    echo "deploy-merlin: bundle directory not found: $bundle_dir" >&2
    exit 1
  }
  sh "$repo/scripts/verify-bundle.sh" "$bundle_dir" || {
    echo "deploy-merlin: local offline bundle verification failed" >&2
    exit 1
  }
  host_bundle_verified=1
  for bundle_file in "$bundle_dir"/*; do
    [ -f "$bundle_file" ] || continue
    bundle_file_bytes=$(wc -c <"$bundle_file" | tr -d ' ')
    case "$bundle_file_bytes" in
      ""|*[!0-9]*) echo "deploy-merlin: cannot determine runtime bundle size" >&2; exit 1 ;;
    esac
    runtime_payload_bytes=$((runtime_payload_bytes + bundle_file_bytes))
  done
  [ "$runtime_payload_bytes" -gt 0 ] || {
    echo "deploy-merlin: runtime bundle size is zero" >&2
    exit 1
  }
  runtime_space_required_kib=$(((runtime_payload_bytes * 2 + 1023) / 1024 + 16384))
fi

installation_library=$(cat "$repo/adapters/merlin/lib/installation-state.sh") || exit 1
if installation_output=$(KNOWN_HOSTS_FILE="$known_hosts_file" sh "$repo/scripts/check-project-installation.sh" --remote-dir "$remote_dir" "$router"); then installation_status=0; else installation_status=$?; fi
printf '%s\n' "$installation_output"
installation_state=$(printf '%s\n' "$installation_output" | sed -n 's/^project_install_state=//p')
installation_allowed=$(printf '%s\n' "$installation_output" | sed -n 's/^project_install_replace_allowed=//p')
replacement_required=0
case "$installation_state" in installed|partial) replacement_required=1 ;; unknown|'') replacement_required=unknown ;; esac

if [ "$apply" != "1" ]; then
  echo "deploy_state=plan"
  echo "apply_required=1"
  echo "router=$router"
  echo "remote_dir=$remote_dir"
  echo "include_bundle=$include_bundle"
  echo "install_runtime=$runtime_install"
  echo "runtime_bundle_transport=$([ "$runtime_install" = "1" ] && echo temporary || echo none)"
  echo "replace_runtime=$replace_runtime"
  echo "replace_core=$replace_core"
  echo "replace_project=$replace_project"
  echo "project_replacement_required=$replacement_required"
  echo "installation_probe=read_only"
  echo "project_only=$project_only"
  if [ "$project_only" = 1 ]; then echo 'runtime_assets_effect=preserve'; echo 'integration_effect=project_managed_configuration_may_change'; fi
  if [ "$installation_state" = unknown ]; then echo 'next_action=resolve the reported installation observation before deployment'
  elif [ "$installation_state" != not_installed ] && [ "$installation_allowed" != 1 ]; then echo 'next_action=preserve incomplete artifacts and establish ownership before deployment'
  elif [ "$replacement_required" = 1 ]; then echo 'next_action=review existing project replacement; require BOOTSTRAP_REPLACE_PROJECT=1 BOOTSTRAP_PROJECT_CONFIRMATION=REPLACE with APPLY=1'
  else echo 'next_action=rerun with APPLY=1 after reviewing this plan'; fi
  exit "$installation_status"
fi

[ "$installation_status" = 0 ] || { echo "deploy_guard_state=unknown_installation" >&2; exit 1; }
if [ "$installation_state" != not_installed ]; then
  [ "$installation_allowed" = 1 ] && [ "$replace_project" = 1 ] && [ "$project_confirmation" = REPLACE ] || { echo "deploy_guard_state=replacement_required" >&2; exit 1; }
fi

mkdir -p "$(dirname "$known_hosts_file")"

if [ "$runtime_install" = "1" ]; then
  runtime_space_preflight='
set -eu
required_kib=__REQUIRED_KIB__
payload_bytes=__PAYLOAD_BYTES__
available_kib=$(
  LC_ALL=C df -k /tmp 2>/dev/null |
    awk "NR > 1 && NF >= 4 && \$4 ~ /^[0-9]+$/ { available = \$4 } END { if (available == \"\") exit 1; print available }"
) || {
  echo "runtime_space_preflight_state=unavailable"
  echo "runtime_bundle_payload_bytes=$payload_bytes"
  echo "runtime_space_required_kib=$required_kib"
  echo "deploy-merlin: cannot determine available /tmp space" >&2
  exit 1
}
case "$available_kib" in
  ""|*[!0-9]*)
    echo "runtime_space_preflight_state=unavailable"
    echo "runtime_bundle_payload_bytes=$payload_bytes"
    echo "runtime_space_required_kib=$required_kib"
    echo "deploy-merlin: invalid available /tmp space" >&2
    exit 1
    ;;
esac
echo "runtime_bundle_payload_bytes=$payload_bytes"
echo "runtime_space_required_kib=$required_kib"
echo "runtime_space_available_kib=$available_kib"
if [ "$available_kib" -lt "$required_kib" ]; then
  echo "runtime_space_preflight_state=insufficient"
  echo "deploy-merlin: insufficient /tmp space for temporary runtime bundle" >&2
  exit 1
fi
echo "runtime_space_preflight_state=ready"
'
  runtime_space_preflight=$(printf '%s' "$runtime_space_preflight" |
    sed "s#__REQUIRED_KIB__#$runtime_space_required_kib#g; s#__PAYLOAD_BYTES__#$runtime_payload_bytes#g")
  printf '%s\n' "$runtime_space_preflight" | "$ssh_command" $ssh_opts -- "$router" 'sh -s' || exit $?
fi

mode="BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0"
[ "$runtime_install" = "1" ] && mode="$mode BOOTSTRAP_RUNTIME_FOLLOWS=1"

remote_script=$(cat <<'HOME_EDGE_REMOTE_SCRIPT'
set -eu
remote_dir="__REMOTE_DIR__"
runtime_follows="__RUNTIME_FOLLOWS__"
staging="${remote_dir}.tmp.$$"
previous="${remote_dir}.prev"
lock_dir="/tmp/home-edge-bootstrap-write.lock"
failed_dir="${remote_dir}.failed.$(date +%Y%m%d%H%M%S).$$"
lock_held=0
staging_owned=0

for protected_path in "$remote_dir" "$staging" "$previous"; do
  [ ! -L "$protected_path" ] || {
    echo "deploy-merlin: refusing symbolic-link deployment path: $protected_path" >&2
    exit 1
  }
done

cleanup_deploy() {
  if [ "$staging_owned" = 1 ]; then rm -rf "$staging" 2>/dev/null || true; fi
  if [ "$lock_held" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
handle_deploy_signal() {
  cleanup_deploy
  trap - EXIT
  exit 130
}
trap cleanup_deploy EXIT
trap handle_deploy_signal HUP INT TERM

acquire_deploy_lock() {
  if ! mkdir "$lock_dir" 2>/dev/null; then
    owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$lock_dir/operation" 2>/dev/null || echo unknown)
      echo "deploy-merlin: global write lock held by pid=$owner_pid operation=$operation" >&2
      exit 1
    fi
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || { echo "deploy-merlin: stale deployment lock cannot be cleared" >&2; exit 1; }
    mkdir "$lock_dir" 2>/dev/null || { echo "deploy-merlin: deployment lock was reacquired" >&2; exit 1; }
    echo "deploy-merlin: recovered stale deployment lock" >&2
  fi
  lock_held=1
  date +%s >"$lock_dir/started_at" || { echo "deploy-merlin: cannot record write lock start" >&2; exit 1; }
  printf "%s\n" "$$" >"$lock_dir/pid" || { echo "deploy-merlin: cannot record write lock owner" >&2; exit 1; }
  printf "%s\n" deploy >"$lock_dir/operation" || { echo "deploy-merlin: cannot record write operation" >&2; exit 1; }
}

preserve_local_state() {
  prev="$1"
  current="$2"
  [ -d "$prev" ] || return 0
  for item in SUBSCRIPTION.local policy.local; do
    [ -e "$prev/$item" ] || continue
    cp -p "$prev/$item" "$current/$item"
  done
  for dir in cache backups; do
    [ -d "$prev/$dir" ] || continue
    rm -rf "$current/$dir"
    cp -a "$prev/$dir" "$current/$dir"
  done
}

cleanup_first_install_active_state() {
  cru d home_edge_selfheal >/dev/null 2>&1 || true
  services_start=/jffs/scripts/services-start
  if [ -f "$services_start" ] && [ ! -L "$services_start" ]; then
    services_tmp="${services_start}.deploy-rollback.$$"
    if awk '
      $0 == "# BEGIN home-edge-bootstrap self-heal lifecycle" { managed=1; next }
      $0 == "# END home-edge-bootstrap self-heal lifecycle" && managed { managed=0; next }
      !managed { print }
    ' "$services_start" >"$services_tmp"; then
      chmod 700 "$services_tmp" 2>/dev/null || true
      mv "$services_tmp" "$services_start" || rm -f "$services_tmp"
    else
      rm -f "$services_tmp"
    fi
  fi
  for active_file in \
    home-edge-policy.env \
    home-edge-policy.local \
    home-edge-self-heal.sh \
    home-edge-update-sub.sh \
    home-edge-subscription-runtime-evidence.sh \
    home-edge-verify-bundle.sh \
    home-edge-reconcile-self-heal.sh \
    home-edge-self-heal-cron.sh \
    home-edge-subscription-auto.sh \
    home-edge-subscription-tools.sh \
    home-edge-subscription-merge.jq \
    home-edge-configure-dashboard-defaults.sh \
    home-edge-dashboard-defaults.js \
    home-edge-secure-temp.sh \
    home-edge-configure-dns.sh \
    home-edge-prefetch-shellcrash-data.sh \
    home-edge-start-shellcrash.sh \
    home-edge-configure-service-rules.sh
  do
    rm -f "/jffs/scripts/$active_file" 2>/dev/null || true
  done
}

rollback_deploy() {
  restored=0
  [ -d "$remote_dir" ] && mv "$remote_dir" "$failed_dir"
  if [ -d "$previous" ]; then
    mv "$previous" "$remote_dir"
    restored=1
  else
    cleanup_first_install_active_state
  fi
  if [ -f "$remote_dir/bootstrap.sh" ]; then
    if ! HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_INSTALL_DIR="$remote_dir" sh "$remote_dir/bootstrap.sh" >/dev/null 2>&1; then
      echo "deploy-merlin: WARN previous kit was restored but its bootstrap replay failed" >&2
    fi
  fi
  if [ ! -f "$remote_dir/scripts/subscription-auto.sh" ] && which cru >/dev/null 2>&1; then
    if cru l 2>/dev/null | grep -Fq '#home_edge_subscription#'; then cru d home_edge_subscription; fi
  fi
  [ "$restored" = "1" ] && rm -rf "$failed_dir"
}

acquire_deploy_lock
__INSTALLATION_LIBRARY__
HOME_EDGE_INSTALLATION_DIR="$remote_dir"
HOME_EDGE_INSTALLATION_ROUTER="__ROUTER__"
HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''
home_edge_inspect_installation
home_edge_require_project_replacement "__REPLACE_PROJECT__" "__PROJECT_CONFIRMATION__" || exit 1
[ ! -e "$staging" ] || { echo "deploy_guard_state=occupied_staging_path" >&2; exit 1; }
# An unrecognized previous backup remains addressable instead of being deleted.
if [ -e "$previous" ]; then
  [ -f "$previous/adapters/merlin/bootstrap.sh" ] && [ ! -L "$previous/adapters" ] && [ ! -L "$previous/adapters/merlin" ] && [ ! -L "$previous/adapters/merlin/bootstrap.sh" ] &&
    grep -Fq 'Merlin adapter' "$previous/adapters/merlin/bootstrap.sh" || { echo "deploy_guard_state=foreign_previous_backup" >&2; exit 1; }
fi
mkdir "$staging"
staging_owned=1
decode_payload() {
  if which base64 >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | base64 -d
  elif which openssl >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A
  else
    echo "deploy-merlin: base64 or openssl is required to decode deployment payload" >&2
    return 1
  fi
}
decode_payload <<'HOME_EDGE_ARCHIVE_BASE64' | tar -xzf - -C "$staging"
__PAYLOAD__
HOME_EDGE_ARCHIVE_BASE64
[ -s "$staging/bootstrap.sh" ] || { echo "deploy-merlin: staged kit is incomplete" >&2; exit 1; }
rm -rf "$previous"
[ ! -d "$remote_dir" ] || mv "$remote_dir" "$previous"
if ! mv "$staging" "$remote_dir"; then
  [ ! -d "$previous" ] || mv "$previous" "$remote_dir"
  exit 1
fi
if ! preserve_local_state "$previous" "$remote_dir"; then
  rollback_deploy
  echo "deploy-merlin: local state preservation failed; previous kit restored" >&2
  exit 1
fi
if [ "$runtime_follows" = "1" ]; then
  echo "deploy_state=staged"
  echo "runtime_stage_required=1"
  echo "rollback_available=$([ -d "$previous" ] && echo 1 || echo 0)"
  exit 0
fi
if ! (cd "$remote_dir" && HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_INSTALL_DIR="$remote_dir" __MODE__ sh bootstrap.sh); then
  rollback_deploy
  echo "deploy-merlin: bootstrap failed; previous kit restored" >&2
  exit 1
fi
state_schema=/jffs/home-edge-bootstrap-state/lifecycle/state.env
if [ ! -f "$state_schema" ] ||
  ! grep -Fxq "state_schema_version=1" "$state_schema" ||
  ! grep -Fxq "stable_state_root=/jffs/home-edge-bootstrap-state" "$state_schema"; then
  rollback_deploy
  echo "deploy-merlin: stable state schema verification failed; previous kit restored" >&2
  exit 1
fi
echo "deploy_state=applied"
echo "rollback_available=$([ -d "$previous" ] && echo 1 || echo 0)"
HOME_EDGE_REMOTE_SCRIPT
)
remote_script=$(printf '%s' "$remote_script" |
  sed "s#__REMOTE_DIR__#$remote_dir#g; s#__MODE__#$mode#g; s#__RUNTIME_FOLLOWS__#$runtime_install#g; s#__ROUTER__#$router#g; s#__REPLACE_PROJECT__#$replace_project#g; s#__PROJECT_CONFIRMATION__#$project_confirmation#g")
remote_script="${remote_script%%__INSTALLATION_LIBRARY__*}$installation_library${remote_script#*__INSTALLATION_LIBRARY__}"

# Stage first so provenance hashes the exact bytes sent to the router.
tmp_parent=${TMPDIR:-/tmp}
deploy_stage=$(mktemp -d "${tmp_parent%/}/home-edge-deploy-stage.XXXXXX") || exit 1
mkdir "$deploy_stage/source"
# shellcheck disable=SC2086
tar -C "$repo" -cf "$deploy_stage/source.tar" $archive_items || exit $?
tar -C "$deploy_stage/source" -xf "$deploy_stage/source.tar" || exit $?
rm "$deploy_stage/source.tar"
sh "$repo/scripts/new-deployment-provenance.sh" "$deploy_stage/source" "$repo" || exit 1
[ -s "$deploy_stage/source/DEPLOYMENT-CONTENT-SHA256SUMS" ] || { echo "deploy-merlin: provenance generation failed" >&2; exit 1; }
send_archive_script() {
  script=$1
  archive=$2
  if which base64 >/dev/null 2>&1; then
    base64 <"$archive" >"$archive.base64" || return $?
  elif which openssl >/dev/null 2>&1; then
    openssl base64 -A <"$archive" >"$archive.base64" || return $?
  else
    echo 'deploy-merlin: host base64 or openssl is required' >&2
    return 1
  fi
  # Underscores in the quoted delimiter cannot collide with base64 data.
  printf '%s' "${script%%__PAYLOAD__*}" >"$archive.remote.sh" || return $?
  fold -w 76 "$archive.base64" >>"$archive.remote.sh" || return $?
  printf '\n%s\n' "${script#*__PAYLOAD__}" >>"$archive.remote.sh" || return $?
  "$ssh_command" $ssh_opts -- "$router" 'sh -s' <"$archive.remote.sh"
}
# Keep transport artifacts outside the source tree whose bytes provenance covers.
deploy_archive="$deploy_stage/project.tgz"
tar -C "$deploy_stage/source" -czf "$deploy_archive" . || exit $?
send_archive_script "$remote_script" "$deploy_archive" || exit $?

if [ "$runtime_install" = "1" ]; then
  runtime_rollback_script='
set -eu
remote_dir="__REMOTE_DIR__"
previous="${remote_dir}.prev"
failed="${remote_dir}.runtime-failed.$$"
lock_dir="/tmp/home-edge-bootstrap-write.lock"
lock_held=0

cleanup_rollback() {
  if [ "$lock_held" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
handle_rollback_signal() {
  cleanup_rollback
  trap - EXIT
  exit 130
}
trap cleanup_rollback EXIT
trap handle_rollback_signal HUP INT TERM

cleanup_first_install_active_state() {
  cru d home_edge_selfheal >/dev/null 2>&1 || true
  services_start=/jffs/scripts/services-start
  if [ -f "$services_start" ] && [ ! -L "$services_start" ]; then
    services_tmp="${services_start}.runtime-rollback.$$"
    if awk '\''
      $0 == "# BEGIN home-edge-bootstrap self-heal lifecycle" { managed=1; next }
      $0 == "# END home-edge-bootstrap self-heal lifecycle" && managed { managed=0; next }
      !managed { print }
    '\'' "$services_start" >"$services_tmp"; then
      chmod 700 "$services_tmp" 2>/dev/null || true
      mv "$services_tmp" "$services_start" || rm -f "$services_tmp"
    else
      rm -f "$services_tmp"
    fi
  fi
  for active_file in \
    home-edge-policy.env \
    home-edge-policy.local \
    home-edge-self-heal.sh \
    home-edge-update-sub.sh \
    home-edge-subscription-runtime-evidence.sh \
    home-edge-verify-bundle.sh \
    home-edge-reconcile-self-heal.sh \
    home-edge-self-heal-cron.sh \
    home-edge-subscription-auto.sh \
    home-edge-subscription-tools.sh \
    home-edge-subscription-merge.jq \
    home-edge-configure-dashboard-defaults.sh \
    home-edge-dashboard-defaults.js \
    home-edge-secure-temp.sh \
    home-edge-configure-dns.sh \
    home-edge-prefetch-shellcrash-data.sh \
    home-edge-start-shellcrash.sh \
    home-edge-configure-service-rules.sh
  do
    rm -f "/jffs/scripts/$active_file" 2>/dev/null || true
  done
}

for protected_path in "$remote_dir" "$previous" "$failed"; do
  [ ! -L "$protected_path" ] || {
    echo "deploy-merlin: refusing symbolic-link rollback path: $protected_path" >&2
    exit 1
  }
done
mkdir "$lock_dir" 2>/dev/null || {
  echo "deploy-merlin: cannot acquire runtime rollback lock" >&2
  exit 1
}
lock_held=1
date +%s >"$lock_dir/started_at"
printf "%s\n" "$$" >"$lock_dir/pid"
printf "%s\n" runtime-rollback >"$lock_dir/operation"

[ ! -d "$failed" ] || rm -rf "$failed"
[ ! -d "$remote_dir" ] || mv "$remote_dir" "$failed"
if [ -d "$previous" ]; then
  mv "$previous" "$remote_dir"
  if [ -f "$remote_dir/bootstrap.sh" ]; then
    HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 BOOTSTRAP_INSTALL_DIR="$remote_dir" sh "$remote_dir/bootstrap.sh" >/dev/null 2>&1 || {
      echo "deploy-merlin: restored control-plane bootstrap replay failed" >&2
      exit 1
    }
  fi
  rm -rf "$failed"
  echo "control_plane_rollback_state=restored"
else
  cleanup_first_install_active_state
  rm -rf "$failed"
  echo "control_plane_rollback_state=removed"
fi
'
  runtime_rollback_script=$(printf '%s' "$runtime_rollback_script" |
    sed "s#__REMOTE_DIR__#$remote_dir#g")
  runtime_script='
set -eu
remote_dir="__REMOTE_DIR__"
runtime_stage="/tmp/home-edge-runtime-bundle.$$"

cleanup_runtime_stage() {
  case "$runtime_stage" in /tmp/home-edge-runtime-bundle.*) rm -rf "$runtime_stage" 2>/dev/null || true ;; esac
}
handle_runtime_signal() {
  cleanup_runtime_stage
  trap - EXIT
  exit 130
}
trap cleanup_runtime_stage EXIT
trap handle_runtime_signal HUP INT TERM

[ ! -L "$runtime_stage" ] || { echo "deploy-merlin: refusing symbolic-link runtime stage" >&2; exit 1; }
mkdir -m 700 "$runtime_stage"
decode_payload() {
  if which base64 >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | base64 -d
  elif which openssl >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A
  else
    echo "deploy-merlin: base64 or openssl is required to decode runtime payload" >&2
    return 1
  fi
}
decode_payload <<'HOME_EDGE_ARCHIVE_BASE64' | tar -xzf - -C "$runtime_stage"
__PAYLOAD__
HOME_EDGE_ARCHIVE_BASE64
[ -s "$runtime_stage/mihomo-linux-arm64" ] || { echo "deploy-merlin: temporary runtime bundle is missing Mihomo" >&2; exit 1; }
[ -s "$runtime_stage/ShellCrash.tar.gz" ] || { echo "deploy-merlin: temporary runtime bundle is missing ShellCrash" >&2; exit 1; }
[ -s "$runtime_stage/SHA256SUMS" ] || { echo "deploy-merlin: temporary runtime bundle is missing SHA256SUMS" >&2; exit 1; }
(cd "$remote_dir" && \
  BOOTSTRAP_APPLY=1 \
  BOOTSTRAP_INSTALL_RUNTIME=1 \
  BOOTSTRAP_INSTALL_DIR="$remote_dir" \
  BOOTSTRAP_BUNDLE_HOST_VERIFIED=1 \
  BOOTSTRAP_REPLACE_RUNTIME=__REPLACE_RUNTIME__ \
  BOOTSTRAP_REPLACE_CORE=__REPLACE_CORE__ \
  BOOTSTRAP_BUNDLE_DIR="$runtime_stage" \
  sh bootstrap.sh)
echo "runtime_deploy_state=applied"
'
  runtime_script=$(printf '%s' "$runtime_script" |
    sed "s#__REMOTE_DIR__#$remote_dir#g; s#__REPLACE_RUNTIME__#$replace_runtime#g; s#__REPLACE_CORE__#$replace_core#g")
  if tar -C "$bundle_dir" -czf "$deploy_stage/runtime.tgz" . &&
    send_archive_script "$runtime_script" "$deploy_stage/runtime.tgz"; then
    :
  else
    runtime_status=$?
    echo "deploy-merlin: runtime stage failed; restoring the prior staged control plane" >&2
    printf '%s\n' "$runtime_rollback_script" | "$ssh_command" $ssh_opts -- "$router" 'sh -s' || {
      echo "deploy-merlin: runtime stage failed and control-plane rollback could not be verified" >&2
      exit 1
    }
    exit "$runtime_status"
  fi
fi
