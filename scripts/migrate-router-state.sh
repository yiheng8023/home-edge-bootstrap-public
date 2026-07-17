#!/bin/sh
# Migrate mutable Merlin operator state out of the replaceable project kit.
set -eu
umask 077

apply=${HOME_EDGE_STATE_APPLY:-0}
fixture_root=${HOME_EDGE_STATE_FIXTURE_ROOT:-}
state_root=${HOME_EDGE_STATE_ROOT:-/jffs/home-edge-bootstrap-state}
install_dir=${HOME_EDGE_INSTALL_DIR:-/jffs/home-edge-bootstrap}
script_dir=${HOME_EDGE_SCRIPT_DIR:-/jffs/scripts}
schema_version=1
legacy_count=0
conflict_count=0
needed=0
bridge_state=needed
find_cmd=$(command -v find) || {
  echo "state-migration: ERROR: find is required" >&2
  exit 1
}
[ ! -x /usr/bin/find ] || find_cmd=/usr/bin/find
sort_cmd=$(command -v sort) || {
  echo "state-migration: ERROR: sort is required" >&2
  exit 1
}
[ ! -x /usr/bin/sort ] || sort_cmd=/usr/bin/sort

emit() {
  printf '%s=%s\n' "$1" "$2"
}

emit_common() {
  emit state_schema_version "$schema_version"
  emit stable_state_root "$state_root"
  emit legacy_state_count "$legacy_count"
  emit conflict_count "$conflict_count"
  emit compatibility_bridge_state "$bridge_state"
}

stop_with() {
  state=$1
  message=$2
  emit_common
  emit state_migration_state "$state"
  case "$state" in
    conflict) emit next_action_code resolve_state_migration_conflict ;;
    *) emit next_action_code resolve_state_migration_blocker ;;
  esac
  printf 'state-migration: ERROR: %s\n' "$message" >&2
  exit 1
}

case "$apply" in
  0|1) ;;
  *) stop_with blocked "HOME_EDGE_STATE_APPLY must be 0 or 1" ;;
esac

validate_logical_root() {
  name=$1
  value=$2
  case "$value" in
    /jffs/?*) ;;
    *) stop_with blocked "$name must be one path below /jffs" ;;
  esac
  case "$value" in
    *[!A-Za-z0-9_./-]*|*'/../'*|*/..|*'/./'*|*/.|*'//'*)
      stop_with blocked "$name contains an unsupported path segment"
      ;;
  esac
}

validate_logical_root HOME_EDGE_STATE_ROOT "$state_root"
validate_logical_root HOME_EDGE_INSTALL_DIR "$install_dir"
validate_logical_root HOME_EDGE_SCRIPT_DIR "$script_dir"
[ "$state_root" != "$install_dir" ] || stop_with blocked "state and install roots must differ"
case "$state_root/" in
  "$install_dir/"*) stop_with blocked "state root must not be inside the replaceable kit" ;;
esac

if [ -n "$fixture_root" ]; then
  case "$fixture_root" in
    /*) ;;
    *) stop_with blocked "HOME_EDGE_STATE_FIXTURE_ROOT must be absolute" ;;
  esac
  [ -d "$fixture_root" ] && [ ! -L "$fixture_root" ] || stop_with blocked "fixture root must be a real directory"
fi

physical() {
  printf '%s%s\n' "$fixture_root" "$1"
}

install_path=$(physical "$install_dir")
state_path=$(physical "$state_root")
script_path=$(physical "$script_dir")
legacy_subscription="$install_path/SUBSCRIPTION.local"
stable_subscription="$state_path/SUBSCRIPTION.local"
legacy_install_policy="$install_path/policy.local"
legacy_script_policy="$script_path/home-edge-policy.local"
stable_policy="$state_path/policy.local"
metadata_path="$state_path/lifecycle/state.env"
bridge_path="$legacy_script_policy"

for root_path in "$install_path" "$state_path" "$script_path"; do
  [ ! -L "$root_path" ] || stop_with blocked "managed root is a symbolic link: $root_path"
  [ ! -e "$root_path" ] || [ -d "$root_path" ] || stop_with blocked "managed root has an unexpected type: $root_path"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-state-migration.XXXXXX") || stop_with blocked "cannot create temporary work directory"
cleanup() {
  rm -rf "$work"
}
trap cleanup EXIT HUP INT TERM

expected_bridge="$work/bridge.expected"
cat >"$expected_bridge" <<EOF
# home-edge-bootstrap-owned: stable-state-compatibility/v1
SUBSCRIPTION_FILE=$state_root/SUBSCRIPTION.local
SUBSCRIPTION_CACHE=$state_root/cache/subscription.yaml
SUBSCRIPTION_BACKUP_DIR=$state_root/backups/subscription
[ ! -r $state_root/policy.local ] || . $state_root/policy.local
EOF

expected_metadata="$work/state.expected"
cat >"$expected_metadata" <<EOF
state_schema_version=1
adapter=merlin
stable_state_root=$state_root
EOF

check_regular_or_absent() {
  path=$1
  label=$2
  [ ! -L "$path" ] || stop_with blocked "$label is a symbolic link: $path"
  [ ! -e "$path" ] || [ -f "$path" ] || stop_with blocked "$label has an unexpected type: $path"
}

check_regular_or_absent "$legacy_subscription" "legacy subscription"
check_regular_or_absent "$stable_subscription" "stable subscription"
check_regular_or_absent "$legacy_install_policy" "legacy install policy"
check_regular_or_absent "$legacy_script_policy" "legacy script policy"
check_regular_or_absent "$stable_policy" "stable policy"
check_regular_or_absent "$metadata_path" "state metadata"

script_policy_is_bridge=0
if [ -f "$legacy_script_policy" ]; then
  if cmp -s "$legacy_script_policy" "$expected_bridge"; then
    script_policy_is_bridge=1
    bridge_state=ready
  elif grep -Fxq '# home-edge-bootstrap-owned: stable-state-compatibility/v1' "$legacy_script_policy"; then
    stop_with blocked "compatibility bridge bytes drifted: $legacy_script_policy"
  fi
fi

if [ -f "$legacy_subscription" ]; then
  legacy_count=$((legacy_count + 1))
  if [ -f "$stable_subscription" ]; then
    if ! cmp -s "$legacy_subscription" "$stable_subscription"; then
      conflict_count=$((conflict_count + 1))
      stop_with conflict "subscription source and stable destination differ"
    fi
  else
    needed=1
  fi
fi

policy_source=
if [ -f "$legacy_install_policy" ]; then
  legacy_count=$((legacy_count + 1))
  policy_source=$legacy_install_policy
fi
if [ -f "$legacy_script_policy" ] && [ "$script_policy_is_bridge" = 0 ]; then
  legacy_count=$((legacy_count + 1))
  if [ -n "$policy_source" ] && ! cmp -s "$policy_source" "$legacy_script_policy"; then
    conflict_count=$((conflict_count + 1))
    stop_with conflict "legacy policy sources differ"
  fi
  [ -n "$policy_source" ] || policy_source=$legacy_script_policy
fi
if [ -n "$policy_source" ]; then
  if [ -f "$stable_policy" ]; then
    if ! cmp -s "$policy_source" "$stable_policy"; then
      conflict_count=$((conflict_count + 1))
      stop_with conflict "legacy policy and stable destination differ"
    fi
  else
    needed=1
  fi
fi

validate_tree() {
  tree=$1
  label=$2
  [ ! -L "$tree" ] || stop_with blocked "$label is a symbolic link: $tree"
  [ ! -e "$tree" ] || [ -d "$tree" ] || stop_with blocked "$label has an unexpected type: $tree"
  [ ! -d "$tree" ] || ! "$find_cmd" "$tree" -type l -print | tr -d '\r' | grep . >/dev/null 2>&1 || stop_with blocked "$label contains a symbolic link: $tree"
  [ ! -d "$tree" ] || ! "$find_cmd" "$tree" ! -type f ! -type d -print | tr -d '\r' | grep . >/dev/null 2>&1 || stop_with blocked "$label contains an unsupported file type: $tree"
}

preflight_merge() {
  source_dir=$1
  destination_dir=$2
  label=$3
  validate_tree "$source_dir" "$label source"
  validate_tree "$destination_dir" "$label destination"
  [ -d "$source_dir" ] || return 0
  legacy_count=$((legacy_count + 1))
  file_list="$work/merge.$legacy_count"
  (CDPATH= cd "$source_dir" && "$find_cmd" . -type f -print | tr -d '\r' | LC_ALL=C "$sort_cmd") >"$file_list"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    destination_file="$destination_dir/${rel#./}"
    [ ! -L "$destination_file" ] || stop_with blocked "$label destination contains a symbolic link: $destination_file"
    if [ -e "$destination_file" ]; then
      [ -f "$destination_file" ] || stop_with blocked "$label destination has an unexpected type: $destination_file"
      if ! cmp -s "$source_dir/${rel#./}" "$destination_file"; then
        conflict_count=$((conflict_count + 1))
        stop_with conflict "$label source and destination differ: $rel"
      fi
    else
      needed=1
    fi
  done <"$file_list"
}

legacy_cache="$install_path/cache"
stable_cache="$state_path/cache"
legacy_subscription_backups="$install_path/backups/subscription"
stable_subscription_backups="$state_path/backups/subscription"
legacy_runtime_backups="$install_path/backups/runtime"
stable_runtime_backups="$state_path/backups/runtime"

preflight_merge "$legacy_cache" "$stable_cache" cache
preflight_merge "$legacy_subscription_backups" "$stable_subscription_backups" subscription_backups
preflight_merge "$legacy_runtime_backups" "$stable_runtime_backups" runtime_backups

if [ -f "$metadata_path" ]; then
  cmp -s "$metadata_path" "$expected_metadata" || {
    conflict_count=$((conflict_count + 1))
    stop_with conflict "state metadata does not match schema 1"
  }
else
  needed=1
fi
if [ "$bridge_state" != ready ]; then
  needed=1
fi

emit_plan() {
  emit_common
  if [ "$needed" = 1 ]; then
    emit state_migration_state needed
    emit next_action_code apply_state_migration
  else
    emit state_migration_state ready
    emit next_action_code none
  fi
}

if [ "$apply" = 0 ]; then
  emit_plan
  exit 0
fi

mkdir -p "$state_path" "$state_path/cache" "$state_path/backups/subscription" "$state_path/backups/runtime" "$state_path/lifecycle" "$script_path"
chmod 700 "$state_path" "$state_path/cache" "$state_path/backups" "$state_path/backups/subscription" "$state_path/backups/runtime" "$state_path/lifecycle"

copy_atomic() {
  source_file=$1
  destination_file=$2
  secret_mode=$3
  [ -f "$source_file" ] && [ ! -L "$source_file" ] || stop_with blocked "migration source is no longer a regular file: $source_file"
  if [ -f "$destination_file" ]; then
    cmp -s "$source_file" "$destination_file" || stop_with conflict "migration destination changed after preflight: $destination_file"
    return 0
  fi
  mkdir -p "$(dirname "$destination_file")"
  temp_file="$destination_file.tmp.$$"
  cp -p "$source_file" "$temp_file" || stop_with blocked "cannot stage migrated file: $destination_file"
  cmp -s "$source_file" "$temp_file" || stop_with blocked "staged migration bytes differ: $destination_file"
  [ "$secret_mode" != 1 ] || chmod 600 "$temp_file"
  mv "$temp_file" "$destination_file" || stop_with blocked "cannot publish migrated file: $destination_file"
}

[ ! -f "$legacy_subscription" ] || copy_atomic "$legacy_subscription" "$stable_subscription" 1
[ -z "$policy_source" ] || copy_atomic "$policy_source" "$stable_policy" 1

merge_tree() {
  source_dir=$1
  destination_dir=$2
  [ -d "$source_dir" ] || return 0
  (CDPATH= cd "$source_dir" && "$find_cmd" . -type d -print | tr -d '\r' | LC_ALL=C "$sort_cmd") | while IFS= read -r rel; do
    [ "$rel" = . ] && continue
    mkdir -p "$destination_dir/${rel#./}"
  done
  (CDPATH= cd "$source_dir" && "$find_cmd" . -type f -print | tr -d '\r' | LC_ALL=C "$sort_cmd") | while IFS= read -r rel; do
    source_file="$source_dir/${rel#./}"
    destination_file="$destination_dir/${rel#./}"
    copy_atomic "$source_file" "$destination_file" 0
  done
}

merge_tree "$legacy_cache" "$stable_cache"
merge_tree "$legacy_subscription_backups" "$stable_subscription_backups"
merge_tree "$legacy_runtime_backups" "$stable_runtime_backups"

publish_static() {
  source_file=$1
  destination_file=$2
  mode=$3
  if [ -f "$destination_file" ] && cmp -s "$source_file" "$destination_file"; then
    return 0
  fi
  mkdir -p "$(dirname "$destination_file")"
  temp_file="$destination_file.tmp.$$"
  cp "$source_file" "$temp_file" || stop_with blocked "cannot stage static lifecycle file: $destination_file"
  chmod "$mode" "$temp_file"
  mv "$temp_file" "$destination_file" || stop_with blocked "cannot publish static lifecycle file: $destination_file"
}

publish_static "$expected_metadata" "$metadata_path" 600
publish_static "$expected_bridge" "$bridge_path" 600
bridge_state=ready

emit_common
emit state_migration_state ready
emit next_action_code none
