#!/bin/sh
# Plan or remove only the fixed Home Edge Bootstrap control surfaces on Merlin.
set -u
umask 077

apply=${DECOMMISSION_APPLY:-0}
confirmation=${DECOMMISSION_CONFIRMATION:-}
fixture_root=${HOME_EDGE_DECOMMISSION_ROOT:-}
migrator=${HOME_EDGE_STATE_MIGRATOR:-/jffs/home-edge-bootstrap/scripts/migrate-router-state.sh}

install_root=/jffs/home-edge-bootstrap
script_root=/jffs/scripts
state_root=/jffs/home-edge-bootstrap-state
services_start=/jffs/scripts/services-start
cache_root=/jffs/home-edge-bootstrap-state/cache
lock_root=/tmp/home-edge-bootstrap-write.lock
job_name=home_edge_selfheal
begin_marker='# BEGIN home-edge-bootstrap self-heal lifecycle'
end_marker='# END home-edge-bootstrap self-heal lifecycle'
helper_names='home-edge-policy.env
home-edge-policy.local
home-edge-self-heal.sh
home-edge-update-sub.sh
home-edge-subscription-runtime-evidence.sh
home-edge-verify-bundle.sh
home-edge-reconcile-self-heal.sh
home-edge-self-heal-cron.sh'

state_migration_state=unavailable
project_registration_state=unavailable
deployment_provenance_state=unavailable
retained_subscription_state=unavailable
retained_policy_state=unavailable
retained_recovery_state=unavailable
helper_count=0
kit_count=0
cache_state=unavailable
marker_state=unavailable
cron_state=unavailable
active_surface_count=0
mutation_started=0
current_action=preflight
lock_acquired=0

emit() { printf '%s=%s\n' "$1" "$2"; }
physical() { printf '%s%s\n' "$fixture_root" "$1"; }

emit_common() {
  emit state_migration_state "$state_migration_state"
  emit project_registration_state "$project_registration_state"
  emit deployment_provenance_state "$deployment_provenance_state"
  emit retained_state_root "$state_root"
  emit retained_subscription_state "$retained_subscription_state"
  emit retained_policy_state "$retained_policy_state"
  emit retained_recovery_state "$retained_recovery_state"
  emit project_helper_count "$helper_count"
  emit project_kit_count "$kit_count"
  emit project_cache_state "$cache_state"
}

release_lock() {
  [ "$lock_acquired" = 1 ] || return 0
  lock_path=$(physical "$lock_root")
  release_status=0
  rm -f "$lock_path/started_at" "$lock_path/pid" "$lock_path/operation" 2>/dev/null || release_status=1
  rmdir "$lock_path" 2>/dev/null || release_status=1
  [ "$release_status" -eq 0 ] || return 1
  lock_acquired=0
}
handle_signal() {
  release_lock >/dev/null 2>&1 || true
  exit 130
}
trap 'release_lock >/dev/null 2>&1 || true' EXIT
trap handle_signal HUP INT TERM

stop_before_mutation() {
  message=$1
  state=${2:-blocked}
  if [ "$mutation_started" = 1 ]; then
    stop_apply "$message"
  fi
  printf 'decommission: ERROR: %s\n' "$message" >&2
  emit_common
  emit decommission_state "$state"
  case "$state" in
    conflict) emit next_action_code resolve_state_migration_conflict ;;
    *) emit next_action_code resolve_decommission_blocker ;;
  esac
  exit 1
}

stop_apply() {
  message=$1
  printf 'decommission: ERROR: %s\n' "$message" >&2
  emit_common
  if [ "$mutation_started" = 1 ]; then
    emit decommission_state partial
    emit failed_action "$current_action"
    emit next_action_code inspect_decommission_partial_state
  else
    emit decommission_state blocked
    emit next_action_code resolve_decommission_blocker
  fi
  exit 1
}

case "$apply" in 0|1) ;; *) stop_before_mutation "DECOMMISSION_APPLY must be 0 or 1" ;; esac
if [ "$apply" = 1 ] && [ "$confirmation" != DECOMMISSION ]; then
  stop_before_mutation "exact DECOMMISSION confirmation is required"
fi
if [ -n "$fixture_root" ]; then
  case "$fixture_root" in /*) ;; *) stop_before_mutation "HOME_EDGE_DECOMMISSION_ROOT must be absolute" ;; esac
  [ -d "$fixture_root" ] && [ ! -L "$fixture_root" ] || stop_before_mutation "fixture root must be a real directory"
fi
[ -f "$migrator" ] && [ ! -L "$migrator" ] || stop_before_mutation "state migrator is unavailable"

classify_retained() {
  state_path=$(physical "$state_root")
  [ ! -L "$state_path" ] || stop_before_mutation "stable state root is a symbolic link"
  if [ -e "$state_path" ] && [ ! -d "$state_path" ]; then
    stop_before_mutation "stable state root has an unexpected type"
  fi

  subscription="$state_path/SUBSCRIPTION.local"
  policy="$state_path/policy.local"
  for retained_file in "$subscription" "$policy"; do
    [ ! -L "$retained_file" ] || stop_before_mutation "retained state file is a symbolic link"
    [ ! -e "$retained_file" ] || [ -f "$retained_file" ] || stop_before_mutation "retained state file has an unexpected type"
  done
  if [ -s "$subscription" ] && [ -r "$subscription" ]; then retained_subscription_state=present
  elif [ -e "$subscription" ]; then retained_subscription_state=unavailable
  else retained_subscription_state=absent
  fi
  if [ -s "$policy" ] && [ -r "$policy" ]; then retained_policy_state=present
  elif [ -e "$policy" ]; then retained_policy_state=unavailable
  else retained_policy_state=absent
  fi

  recovery="$state_path/backups"
  [ ! -L "$recovery" ] || stop_before_mutation "retained recovery root is a symbolic link"
  if [ -d "$recovery" ] && [ -r "$recovery" ]; then retained_recovery_state=present
  elif [ -e "$recovery" ]; then retained_recovery_state=unavailable
  else retained_recovery_state=absent
  fi
}

count_kit_variants() {
  count=0
  jffs_path=$(physical /jffs)
  for candidate in \
    "$jffs_path/home-edge-bootstrap" \
    "$jffs_path/home-edge-bootstrap.prev" \
    "$jffs_path"/home-edge-bootstrap.rollback.[0-9]* \
    "$jffs_path"/home-edge-bootstrap.failed.[0-9]* \
    "$jffs_path"/home-edge-bootstrap.tmp.[0-9]*
  do
    [ -e "$candidate" ] || [ -L "$candidate" ] || continue
    leaf=${candidate##*/}
    is_fixed_kit_leaf "$leaf" || continue
    [ ! -L "$candidate" ] || stop_before_mutation "kit variant is a symbolic link: /jffs/$leaf"
    [ -d "$candidate" ] || stop_before_mutation "kit variant has an unexpected type: /jffs/$leaf"
    count=$((count + 1))
  done
  kit_count=$count
}

is_fixed_kit_leaf() {
  leaf=$1
  case "$leaf" in
    home-edge-bootstrap|home-edge-bootstrap.prev) return 0 ;;
    home-edge-bootstrap.rollback.*) suffix=${leaf#home-edge-bootstrap.rollback.} ;;
    home-edge-bootstrap.failed.*) suffix=${leaf#home-edge-bootstrap.failed.} ;;
    home-edge-bootstrap.tmp.*) suffix=${leaf#home-edge-bootstrap.tmp.} ;;
    *) return 1 ;;
  esac
  case "$suffix" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac
}

classify_helpers() {
  helper_count=0
  scripts_path=$(physical "$script_root")
  old_ifs=$IFS
  IFS='
'
  for name in $helper_names; do
    path="$scripts_path/$name"
    [ ! -L "$path" ] || { IFS=$old_ifs; stop_before_mutation "fixed helper is a symbolic link: $script_root/$name"; }
    if [ -e "$path" ]; then
      [ -f "$path" ] || { IFS=$old_ifs; stop_before_mutation "fixed helper has an unexpected type: $script_root/$name"; }
      helper_count=$((helper_count + 1))
    fi
  done
  IFS=$old_ifs
}

classify_registration() {
  services_path=$(physical "$services_start")
  [ ! -L "$services_path" ] || stop_before_mutation "services-start is a symbolic link"
  if [ -e "$services_path" ] && [ ! -f "$services_path" ]; then
    stop_before_mutation "services-start has an unexpected type"
  fi
  begin_count=0
  end_count=0
  begin_line=0
  end_line=0
  if [ -f "$services_path" ]; then
    begin_count=$(grep -Fxc "$begin_marker" "$services_path" 2>/dev/null || true)
    end_count=$(grep -Fxc "$end_marker" "$services_path" 2>/dev/null || true)
    begin_line=$(grep -nFx "$begin_marker" "$services_path" 2>/dev/null | sed -n 's/:.*//p' | head -n 1)
    end_line=$(grep -nFx "$end_marker" "$services_path" 2>/dev/null | sed -n 's/:.*//p' | head -n 1)
    [ -n "$begin_line" ] || begin_line=0
    [ -n "$end_line" ] || end_line=0
  fi
  if [ "$begin_count" -eq 0 ] && [ "$end_count" -eq 0 ]; then
    marker_state=absent
  elif [ "$begin_count" -eq 1 ] && [ "$end_count" -eq 1 ] && [ "$begin_line" -lt "$end_line" ]; then
    marker_state=present
  else
    marker_state=drift
    project_registration_state=drift
    stop_before_mutation "managed services-start markers are malformed or duplicated"
  fi

  command -v cru >/dev/null 2>&1 || stop_before_mutation "cru is unavailable"
  cron_list=$(cru l 2>/dev/null) || stop_before_mutation "cannot read cron registration"
  exact_count=$(printf '%s\n' "$cron_list" | awk '{ line=$0; while (sub(/#home_edge_selfheal#/, "", line)) n++ } END { print n+0 }')
  loose_count=$(printf '%s\n' "$cron_list" | grep -c 'home_edge_selfheal' 2>/dev/null || true)
  if [ "$exact_count" -eq 0 ] && [ "$loose_count" -eq 0 ]; then
    cron_state=absent
  elif [ "$exact_count" -eq 1 ] && [ "$loose_count" -eq 1 ]; then
    cron_state=present
  else
    cron_state=drift
    project_registration_state=drift
    stop_before_mutation "cron registration is ambiguous"
  fi
  if [ "$marker_state" = present ] || [ "$cron_state" = present ]; then
    project_registration_state=present
  else
    project_registration_state=absent
  fi
}

classify_cache() {
  cache_path=$(physical "$cache_root")
  [ ! -L "$cache_path" ] || stop_before_mutation "default stable cache is a symbolic link"
  if [ -d "$cache_path" ]; then cache_state=present
  elif [ -e "$cache_path" ]; then stop_before_mutation "default stable cache has an unexpected type"
  else cache_state=absent
  fi
}

metadata_value() {
  awk -F= -v key="$1" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$2" 2>/dev/null
}

verify_provenance() {
  if [ "$active_surface_count" -eq 0 ]; then
    deployment_provenance_state=not_applicable
    return 0
  fi
  install_path=$(physical "$install_root")
  verifier="$install_path/scripts/verify-deployment-provenance.sh"
  metadata="$install_path/DEPLOYMENT-PROVENANCE.env"
  [ -f "$verifier" ] && [ ! -L "$verifier" ] && [ -f "$metadata" ] || stop_before_mutation "deployment provenance evidence is missing"
  source_kind=$(metadata_value source_kind "$metadata")
  source_commit=$(metadata_value source_commit "$metadata")
  source_version=$(metadata_value source_version "$metadata")
  case "$source_kind" in git|release) ;; *) stop_before_mutation "deployment provenance source kind is unsupported" ;; esac
  provenance_output=$(HOME_EDGE_INSTALL_DIR="$install_path" \
    HOME_EDGE_ROUTER_SCRIPT_DIR="$(physical "$script_root")" \
    HOME_EDGE_EXPECTED_SOURCE_KIND="$source_kind" \
    HOME_EDGE_EXPECTED_SOURCE_COMMIT="$source_commit" \
    HOME_EDGE_EXPECTED_SOURCE_VERSION="$source_version" \
    sh "$verifier" 2>/dev/null) || stop_before_mutation "deployment provenance verification failed"
  deployment_provenance_state=$(printf '%s\n' "$provenance_output" | sed -n 's/^deployment_provenance_state=//p' | head -n 1)
  [ "$deployment_provenance_state" = match ] || stop_before_mutation "deployment provenance does not establish fixed surface ownership"
}

run_migration_plan() {
  migration_output=$(HOME_EDGE_STATE_FIXTURE_ROOT="$fixture_root" \
    HOME_EDGE_STATE_ROOT="$state_root" \
    HOME_EDGE_INSTALL_DIR="$install_root" \
    HOME_EDGE_SCRIPT_DIR="$script_root" \
    HOME_EDGE_STATE_APPLY=0 sh "$migrator" 2>/dev/null)
  migration_status=$?
  state_migration_state=$(printf '%s\n' "$migration_output" | sed -n 's/^state_migration_state=//p' | head -n 1)
  [ -n "$state_migration_state" ] || state_migration_state=blocked
  if [ "$migration_status" -ne 0 ]; then
    case "$state_migration_state" in conflict) stop_before_mutation "stable state migration has a conflict" conflict ;;
      *) stop_before_mutation "stable state migration is blocked" ;;
    esac
  fi
  case "$state_migration_state" in ready|needed) ;;
    conflict) stop_before_mutation "stable state migration has a conflict" conflict ;;
    *) stop_before_mutation "stable state migration plan is not actionable" ;;
  esac
}

check_lock_clear() {
  [ "$lock_acquired" = 1 ] && return 0
  lock_path=$(physical "$lock_root")
  [ ! -L "$lock_path" ] || stop_before_mutation "global write lock is a symbolic link"
  [ ! -e "$lock_path" ] || stop_before_mutation "global write lock is active"
}

preflight() {
  classify_retained
  classify_helpers
  count_kit_variants
  classify_registration
  classify_cache
  active_surface_count=$((helper_count + kit_count))
  [ "$project_registration_state" = absent ] || active_surface_count=$((active_surface_count + 1))
  [ "$cache_state" = absent ] || active_surface_count=$((active_surface_count + 1))
  run_migration_plan
  if [ "$active_surface_count" -eq 0 ]; then
    state_migration_state=not_applicable
    deployment_provenance_state=not_applicable
  else
    verify_provenance
  fi
  check_lock_clear
}

preflight

if [ "$active_surface_count" -eq 0 ]; then
  emit_common
  emit decommission_state already_decommissioned
  emit next_action_code none
  exit 0
fi

if [ "$apply" = 0 ]; then
  emit_common
  emit planned_helper_root "$script_root"
  emit planned_install_root "$install_root"
  emit planned_cache_path "$cache_root"
  emit decommission_state plan_ready
  emit next_action_code review_decommission_plan
  exit 0
fi

acquire_lock() {
  lock_path=$(physical "$lock_root")
  mkdir -p "$(dirname "$lock_path")" || stop_apply "cannot prepare lock parent"
  mkdir "$lock_path" 2>/dev/null || stop_apply "global write lock was acquired concurrently"
  lock_acquired=1
  date +%s >"$lock_path/started_at" || stop_apply "cannot record write lock start"
  printf '%s\n' "$$" >"$lock_path/pid" || stop_apply "cannot record write lock owner"
  printf '%s\n' decommission >"$lock_path/operation" || stop_apply "cannot record write operation"
}

acquire_lock
preflight

current_action=run_migration_apply
mutation_started=1
migration_output=$(HOME_EDGE_STATE_FIXTURE_ROOT="$fixture_root" \
  HOME_EDGE_STATE_ROOT="$state_root" \
  HOME_EDGE_INSTALL_DIR="$install_root" \
  HOME_EDGE_SCRIPT_DIR="$script_root" \
  HOME_EDGE_STATE_APPLY=1 sh "$migrator" 2>/dev/null)
[ $? -eq 0 ] || stop_apply "stable state migration apply failed"
state_migration_state=$(printf '%s\n' "$migration_output" | sed -n 's/^state_migration_state=//p' | head -n 1)
[ "$state_migration_state" = ready ] || stop_apply "stable state migration did not reach ready"

current_action=remove_exact_cron
if [ "$cron_state" = present ]; then
  cru d "$job_name" >/dev/null 2>&1 || stop_apply "cannot remove exact cron registration"
fi
cron_after=$(cru l 2>/dev/null) || stop_apply "cannot verify cron removal"
printf '%s\n' "$cron_after" | grep -q 'home_edge_selfheal' && stop_apply "cron registration remained after deletion"
cron_state=absent

current_action=remove_one_managed_block
if [ "$marker_state" = present ]; then
  services_path=$(physical "$services_start")
  services_tmp="$services_path.decommission.$$"
  mode=$(stat -c '%a' "$services_path" 2>/dev/null || stat -f '%Lp' "$services_path" 2>/dev/null) || stop_apply "cannot read services-start mode"
  awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { managed=1; next }
    $0 == end && managed { managed=0; next }
    !managed { print }
  ' "$services_path" >"$services_tmp" || stop_apply "cannot build services-start replacement"
  chmod "$mode" "$services_tmp" || stop_apply "cannot preserve services-start mode"
  mv "$services_tmp" "$services_path" || stop_apply "cannot replace services-start"
fi
marker_state=absent
project_registration_state=absent

current_action=remove_fixed_helpers
scripts_path=$(physical "$script_root")
old_ifs=$IFS
IFS='
'
for name in $helper_names; do
  path="$scripts_path/$name"
  [ ! -e "$path" ] || rm -f "$path" || { IFS=$old_ifs; stop_apply "cannot remove fixed helper: $script_root/$name"; }
done
IFS=$old_ifs
helper_count=0

current_action=remove_validated_kit_variants
jffs_path=$(physical /jffs)
for candidate in \
  "$jffs_path/home-edge-bootstrap" \
  "$jffs_path/home-edge-bootstrap.prev" \
  "$jffs_path"/home-edge-bootstrap.rollback.[0-9]* \
  "$jffs_path"/home-edge-bootstrap.failed.[0-9]* \
  "$jffs_path"/home-edge-bootstrap.tmp.[0-9]*
do
  [ -e "$candidate" ] || continue
  leaf=${candidate##*/}
  is_fixed_kit_leaf "$leaf" || continue
  rm -rf "$candidate" || stop_apply "cannot remove validated kit variant"
done
kit_count=0

current_action=remove_default_cache
cache_path=$(physical "$cache_root")
[ ! -e "$cache_path" ] || rm -rf "$cache_path" || stop_apply "cannot remove default stable cache"
cache_state=absent

current_action=verify_retained_state
schema_path="$(physical "$state_root")/lifecycle/state.env"
[ -f "$schema_path" ] && grep -Fxq 'state_schema_version=1' "$schema_path" &&
  grep -Fxq 'stable_state_root=/jffs/home-edge-bootstrap-state' "$schema_path" || stop_apply "retained state schema is invalid"
classify_retained
case "$retained_subscription_state:$retained_policy_state:$retained_recovery_state" in
  *unavailable*) stop_apply "retained operator or recovery state is unreadable" ;;
esac

current_action=verify_active_surfaces_absent
classify_helpers
count_kit_variants
classify_registration
classify_cache
[ "$helper_count" -eq 0 ] && [ "$kit_count" -eq 0 ] &&
  [ "$project_registration_state" = absent ] && [ "$cache_state" = absent ] || stop_apply "active project surface remained"

deployment_provenance_state=removed_with_validated_kit
current_action=release_write_lock
release_lock || stop_apply "cannot release global write lock"
emit_common
emit decommission_state ready
emit next_action_code none
exit 0
