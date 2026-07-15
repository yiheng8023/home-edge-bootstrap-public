#!/bin/sh
# Merlin adapter. Default is plan mode; set BOOTSTRAP_APPLY=1 to write router state.
set -eu
umask 077

adapter_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
kit_root=$(CDPATH= cd "$adapter_dir/../.." && pwd)

apply="${BOOTSTRAP_APPLY:-0}"
jffs_dir="${BOOTSTRAP_JFFS_DIR:-/jffs}"
install_dir="${BOOTSTRAP_INSTALL_DIR:-/jffs/home-edge-bootstrap}"
router_script_dir="${BOOTSTRAP_SCRIPT_DIR:-/jffs/scripts}"
shellcrash_dir="${BOOTSTRAP_SHELLCRASH_DIR:-/jffs/ShellCrash}"
runtime_install="${BOOTSTRAP_INSTALL_RUNTIME:-0}"
replace_runtime="${BOOTSTRAP_REPLACE_RUNTIME:-0}"
replace_core="${BOOTSTRAP_REPLACE_CORE:-0}"
host_bundle_verified="${BOOTSTRAP_BUNDLE_HOST_VERIFIED:-0}"
runtime_arch="${BOOTSTRAP_ARCH_OVERRIDE:-$(uname -m 2>/dev/null || echo unknown)}"
policy_src="$kit_root/config/policy.env"
policy_dst="$router_script_dir/home-edge-policy.env"
self_heal_src="$kit_root/scripts/self-heal.sh"
update_sub_src="$kit_root/scripts/update-sub.sh"
runtime_evidence_src="$kit_root/scripts/subscription-runtime-evidence.sh"
verify_bundle_src="$kit_root/scripts/verify-bundle.sh"
reconcile_src="$kit_root/scripts/reconcile-self-heal-registration.sh"
self_heal_dst="$router_script_dir/home-edge-self-heal.sh"
update_sub_dst="$router_script_dir/home-edge-update-sub.sh"
runtime_evidence_dst="$router_script_dir/home-edge-subscription-runtime-evidence.sh"
verify_bundle_dst="$router_script_dir/home-edge-verify-bundle.sh"
reconcile_dst="$router_script_dir/home-edge-reconcile-self-heal.sh"
wrapper_dst="$router_script_dir/home-edge-self-heal-cron.sh"
bundle_dir="$kit_root/bundle"
runtime_backup_dir="$install_dir/backups/runtime"
runtime_tmp="${BOOTSTRAP_RUNTIME_TMP_DIR:-/tmp/home-edge-shellcrash.$$}"
runtime_max_backups="${BOOTSTRAP_RUNTIME_MAX_BACKUPS:-3}"

runtime_init_fixture="${BOOTSTRAP_RUNTIME_INIT_FIXTURE:-0}"
write_lock_dir="${HOME_EDGE_WRITE_LOCK_DIR:-/tmp/home-edge-bootstrap-write.lock}"
write_lock_stale_sec="${HOME_EDGE_WRITE_LOCK_STALE_SEC:-1800}"
write_lock_already_held="${HOME_EDGE_WRITE_LOCK_HELD:-0}"
write_lock_acquired=0

cleanup_runtime_tmp() {
  [ ! -d "$runtime_tmp" ] || rm -rf "$runtime_tmp"
}
release_write_lock() {
  if [ "$write_lock_acquired" = "1" ]; then
    rm -f "$write_lock_dir/started_at" "$write_lock_dir/pid" "$write_lock_dir/operation" 2>/dev/null || true
    rmdir "$write_lock_dir" 2>/dev/null || true
  fi
}
cleanup_all() {
  cleanup_runtime_tmp
  release_write_lock
}
handle_runtime_signal() {
  cleanup_all
  trap - EXIT
  exit 130
}


log() { echo "merlin-bootstrap: $*"; }

die() { echo "merlin-bootstrap: ERROR: $*" >&2; exit 1; }

acquire_write_lock() {
  [ "$apply" = "1" ] || return 0
  [ "$write_lock_already_held" != "1" ] || { log "inherited global write lock"; return 0; }
  case "$write_lock_dir" in /tmp/?*) ;; *) die "HOME_EDGE_WRITE_LOCK_DIR must be below /tmp" ;; esac
  case "$write_lock_dir" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "unsafe HOME_EDGE_WRITE_LOCK_DIR" ;; esac
  case "$write_lock_stale_sec" in ""|*[!0-9]*|0) write_lock_stale_sec=1800 ;; esac

  if ! mkdir "$write_lock_dir" 2>/dev/null; then
    owner_pid=$(cat "$write_lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$write_lock_dir/operation" 2>/dev/null || echo unknown)
      die "global write lock held by pid=$owner_pid operation=$operation"
    fi
    started=$(cat "$write_lock_dir/started_at" 2>/dev/null || true)
    now=$(date +%s)
    case "$started:$now" in *[!0-9:]*|:*|*:) age=0 ;; *) age=$((now - started)) ;; esac
    if [ -z "$owner_pid" ] && [ "$age" -le "$write_lock_stale_sec" ]; then
      die "global write lock has no verifiable owner and lease has not expired"
    fi
    rm -f "$write_lock_dir/started_at" "$write_lock_dir/pid" "$write_lock_dir/operation" 2>/dev/null || true
    rmdir "$write_lock_dir" 2>/dev/null || die "stale global write lock cannot be cleared"
    mkdir "$write_lock_dir" 2>/dev/null || die "global write lock was reacquired"
  fi
  write_lock_acquired=1
  date +%s >"$write_lock_dir/started_at" || die "cannot record write lock start"
  printf '%s\n' "$$" >"$write_lock_dir/pid" || die "cannot record write lock owner"
  printf '%s\n' merlin-bootstrap >"$write_lock_dir/operation" || die "cannot record write operation"
}

trap cleanup_all EXIT
trap handle_runtime_signal HUP INT TERM

validate_bool() {
  name="$1"
  value="$2"
  case "$value" in 0|1) ;; *) die "invalid boolean $name=$value; expected 0 or 1" ;; esac
}
validate_bool BOOTSTRAP_APPLY "$apply"
validate_bool BOOTSTRAP_INSTALL_RUNTIME "$runtime_install"
validate_bool BOOTSTRAP_REPLACE_RUNTIME "$replace_runtime"
validate_bool BOOTSTRAP_REPLACE_CORE "$replace_core"
validate_bool BOOTSTRAP_BUNDLE_HOST_VERIFIED "$host_bundle_verified"
validate_bool BOOTSTRAP_RUNTIME_INIT_FIXTURE "$runtime_init_fixture"
validate_bool HOME_EDGE_WRITE_LOCK_HELD "$write_lock_already_held"

case "$jffs_dir" in
  /) die "BOOTSTRAP_JFFS_DIR must not be the filesystem root" ;;
  */) jffs_dir=${jffs_dir%/} ;;
esac
case "$jffs_dir" in /*) ;; *) die "BOOTSTRAP_JFFS_DIR must be absolute" ;; esac
case "$jffs_dir" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "BOOTSTRAP_JFFS_DIR is unsafe: $jffs_dir" ;; esac

validate_jffs_child() {
  name="$1"
  value="$2"
  case "$value" in
    "$jffs_dir"/?*) ;;
    "$jffs_dir"|"$jffs_dir"/) die "$name must not be the JFFS root" ;;
    *) die "$name must be below $jffs_dir" ;;
  esac
  case "$value" in
    *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "$name is unsafe: $value" ;;
  esac
}

reject_overlap() {
  first_name="$1"
  first_path="$2"
  second_name="$3"
  second_path="$4"
  case "$first_path/" in "$second_path/"*) die "$first_name must not overlap $second_name" ;; esac
  case "$second_path/" in "$first_path/"*) die "$second_name must not overlap $first_name" ;; esac
}

validate_jffs_child BOOTSTRAP_INSTALL_DIR "$install_dir"
validate_jffs_child BOOTSTRAP_SCRIPT_DIR "$router_script_dir"
[ "$router_script_dir" = "$jffs_dir/scripts" ] || die "BOOTSTRAP_SCRIPT_DIR must equal BOOTSTRAP_JFFS_DIR/scripts"
validate_jffs_child BOOTSTRAP_SHELLCRASH_DIR "$shellcrash_dir"
reject_overlap BOOTSTRAP_INSTALL_DIR "$install_dir" BOOTSTRAP_SCRIPT_DIR "$router_script_dir"
reject_overlap BOOTSTRAP_INSTALL_DIR "$install_dir" BOOTSTRAP_SHELLCRASH_DIR "$shellcrash_dir"
reject_overlap BOOTSTRAP_SCRIPT_DIR "$router_script_dir" BOOTSTRAP_SHELLCRASH_DIR "$shellcrash_dir"

if [ "$apply" = "1" ]; then
  for protected_path in "$install_dir" "$router_script_dir" "$shellcrash_dir"; do
    [ ! -L "$protected_path" ] || die "managed path must not be a symbolic link: $protected_path"
  done
fi

case "$runtime_tmp" in /tmp/?*) ;; *) die "runtime temp directory must be a concrete path under /tmp: $runtime_tmp" ;; esac
case "$runtime_tmp" in *[!A-Za-z0-9_./-]*|*/../*|*/..|*/./*|*/.) die "runtime temp directory contains unsupported characters: $runtime_tmp" ;; esac

run() {
  if [ "$apply" = "1" ]; then
    "$@"
  else
    printf 'PLAN:'
    for arg in "$@"; do printf ' %s' "$arg"; done
    printf '\n'
  fi
}

[ -d "$jffs_dir" ] || die "Merlin JFFS directory not found: $jffs_dir"
[ -r "$policy_src" ] || die "missing $policy_src"
[ -r "$self_heal_src" ] || die "missing $self_heal_src"
[ -r "$update_sub_src" ] || die "missing $update_sub_src"
[ -r "$runtime_evidence_src" ] || die "missing $runtime_evidence_src"
[ -r "$verify_bundle_src" ] || die "missing $verify_bundle_src"
[ -r "$reconcile_src" ] || die "missing $reconcile_src"

which curl >/dev/null 2>&1 || log "WARN curl not found; ShellClash usually provides it"
which jq >/dev/null 2>&1 || log "WARN jq not found; self-heal requires it"
which cru >/dev/null 2>&1 || log "WARN cru not found; cron install will be skipped"

if [ "$runtime_install" = "1" ]; then
  case "$runtime_arch" in
    aarch64|arm64) ;;
    *) die "bundled mihomo-linux-arm64 requires aarch64/arm64; detected $runtime_arch" ;;
  esac
  [ -s "$bundle_dir/mihomo-linux-arm64" ] || die "missing bundled Mihomo arm64 binary"
  [ -s "$bundle_dir/ShellCrash.tar.gz" ] || die "missing bundled ShellCrash archive"
  if [ "$apply" = "1" ]; then
    if ! which sha256sum >/dev/null 2>&1 && [ "$host_bundle_verified" != "1" ]; then
      die "router lacks sha256sum and host bundle verification was not attested"
    fi
    BUNDLE_DIGEST_HOST_VERIFIED="$host_bundle_verified" sh "$verify_bundle_src" "$bundle_dir" || die "offline bundle verification failed"
  fi
fi

acquire_write_lock
log "mode=$([ "$apply" = "1" ] && echo apply || echo plan)"
log "kit_root=$kit_root"
log "install_dir=$install_dir"
log "script_dir=$router_script_dir"
log "shellcrash_dir=$shellcrash_dir"
log "runtime_install=$runtime_install"
log "replace_runtime=$replace_runtime"
log "replace_core=$replace_core"

run mkdir -p "$install_dir" "$router_script_dir" "$install_dir/cache" "$install_dir/backups/subscription"
run cp "$policy_src" "$policy_dst"
run cp "$self_heal_src" "$self_heal_dst"
run cp "$update_sub_src" "$update_sub_dst"
run cp "$runtime_evidence_src" "$runtime_evidence_dst"
run cp "$verify_bundle_src" "$verify_bundle_dst"
run cp "$reconcile_src" "$reconcile_dst"
run chmod 600 "$policy_dst"
run chmod 755 "$self_heal_dst" "$update_sub_dst" "$runtime_evidence_dst" "$verify_bundle_dst" "$reconcile_dst"


set_shellcrash_config() {
  key="$1"
  value="$2"
  cfg="$shellcrash_dir/configs/ShellCrash.cfg"
  cfg_tmp="${cfg}.tmp.$$"
  mkdir -p "$shellcrash_dir/configs"
  [ -f "$cfg" ] || echo '#ShellCrash config managed by Home Edge Bootstrap when offline runtime install is enabled.' > "$cfg"
  if ! sed "/^${key}=.*/d" "$cfg" >"$cfg_tmp"; then
    rm -f "$cfg_tmp"
    die "cannot stage ShellCrash config: $key"
  fi
  if ! printf '%s=%s\n' "$key" "$value" >>"$cfg_tmp"; then
    rm -f "$cfg_tmp"
    die "cannot update ShellCrash config: $key"
  fi
  mv "$cfg_tmp" "$cfg" || { rm -f "$cfg_tmp"; die "cannot commit ShellCrash config: $key"; }
}
prune_runtime_backups() {
  case "$runtime_max_backups" in ""|*[!0-9]*|0) runtime_max_backups=3 ;; esac
  case "$runtime_backup_dir" in */backups/runtime) ;; *) die "invalid runtime backup directory: $runtime_backup_dir" ;; esac
  for pattern in 'ShellCrash.*' 'CrashCore.*' 'nat-start.*'; do
    count=0
    for candidate in $(ls -1dr "$runtime_backup_dir"/$pattern 2>/dev/null); do
      count=$((count + 1))
      [ "$count" -le "$runtime_max_backups" ] || rm -rf "$candidate"
    done
  done
}


install_offline_runtime() {
  if [ "$apply" != "1" ]; then
    log "PLAN: verify offline bundle at $bundle_dir"
    log "PLAN: install or refresh ShellCrash runtime at $shellcrash_dir from offline bundle"
    return 0
  fi

  runtime_existed=0
  [ -d "$shellcrash_dir" ] && runtime_existed=1
  mkdir -p "$runtime_backup_dir"

  if [ -d "$shellcrash_dir" ] && [ "$replace_runtime" != "1" ]; then
    log "existing ShellCrash runtime found at $shellcrash_dir; leaving scripts in place (set BOOTSTRAP_REPLACE_RUNTIME=1 to replace)"
  else
    ts=$(date +%Y%m%d%H%M%S)
    previous_runtime=""
    [ -d "$shellcrash_dir" ] && previous_runtime="$runtime_backup_dir/ShellCrash.$ts.$$"
    [ -f "$router_script_dir/nat-start" ] && cp "$router_script_dir/nat-start" "$runtime_backup_dir/nat-start.$ts.$$"
    cleanup_runtime_tmp
    mkdir -p "$runtime_tmp"
    tar -xzf "$bundle_dir/ShellCrash.tar.gz" -C "$runtime_tmp" || die "extract ShellCrash.tar.gz failed"
    [ -s "$runtime_tmp/init.sh" ] || { cleanup_runtime_tmp; die "ShellCrash archive missing init.sh"; }
    patched_init="$runtime_tmp/init.home-edge.sh"
    sed "s#/tmp/SC_tmp#$runtime_tmp#g" "$runtime_tmp/init.sh" >"$patched_init" || { cleanup_runtime_tmp; die "patching ShellCrash init temp path failed"; }
    chmod 755 "$patched_init"
    [ -n "$previous_runtime" ] && mv "$shellcrash_dir" "$previous_runtime"
    runtime_init_ok=0
    if [ "$runtime_init_fixture" = "1" ]; then
      mkdir -p "$shellcrash_dir"
      cp -a "$runtime_tmp"/. "$shellcrash_dir"/ && runtime_init_ok=1
    elif CRASHDIR="$shellcrash_dir" sh "$patched_init"; then
      runtime_init_ok=1
    fi
    if [ "$runtime_init_ok" != "1" ]; then
      cleanup_runtime_tmp
      rm -rf "$shellcrash_dir"
      if [ -n "$previous_runtime" ] && [ -d "$previous_runtime" ]; then
        mv "$previous_runtime" "$shellcrash_dir" || die "ShellCrash init failed and previous runtime restore failed"
      fi
      die "ShellCrash offline init failed; previous runtime restored"
    fi
    cleanup_runtime_tmp
  fi

  [ -d "$shellcrash_dir" ] || die "ShellCrash runtime directory missing after offline install: $shellcrash_dir"
  core_path="$shellcrash_dir/CrashCore.gz"
  if [ "$runtime_existed" = "1" ] && [ "$replace_runtime" != "1" ] && [ -s "$core_path" ] && [ "$replace_core" != "1" ]; then
    log "existing Mihomo core preserved (set BOOTSTRAP_REPLACE_CORE=1 to replace it explicitly)"
  else
    core_tmp="${core_path}.tmp.$$"
    ts=$(date +%Y%m%d%H%M%S)
    if [ -s "$core_path" ]; then
      cp -p "$core_path" "$runtime_backup_dir/CrashCore.$ts.$$.gz" || die "existing CrashCore backup failed"
    fi
    if ! gzip -c "$bundle_dir/mihomo-linux-arm64" >"$core_tmp"; then
      rm -f "$core_tmp"
      die "staging Mihomo CrashCore.gz failed"
    fi
    chmod 600 "$core_tmp" || { rm -f "$core_tmp"; die "securing Mihomo CrashCore.gz failed"; }
    mv "$core_tmp" "$core_path" || { rm -f "$core_tmp"; die "activating Mihomo CrashCore.gz failed"; }

    set_shellcrash_config crashcore meta
    set_shellcrash_config custcorelink ""
    core_v=$("$bundle_dir/mihomo-linux-arm64" -v 2>/dev/null | head -n 1 | sed 's/ linux.*//;s/.* //' || true)
    [ -n "$core_v" ] && set_shellcrash_config core_v "$core_v"
    log "offline runtime staged: ShellCrash=$shellcrash_dir Mihomo=${core_v:-unknown}"
  fi
  prune_runtime_backups
}

if [ "$runtime_install" = "1" ]; then
  install_offline_runtime
else
  if [ -s "$bundle_dir/mihomo-linux-arm64" ] && [ -s "$bundle_dir/ShellCrash.tar.gz" ]; then
    log "offline bundle present; set BOOTSTRAP_INSTALL_RUNTIME=1 to install or refresh runtime"
  else
    log "offline bundle incomplete; configuring existing ShellCrash/Mihomo runtime only"
  fi
fi

if [ "$apply" = "1" ]; then
cat > "$wrapper_dst" <<EOF
#!/bin/sh
for f in "$policy_dst" "$router_script_dir/home-edge-policy.local"; do
  [ -r "\$f" ] && . "\$f"
done
self_heal="$self_heal_dst"
HEAL_DRY_RUN="\${HEAL_CRON_DRY_RUN:-1}" exec sh "\$self_heal"
EOF
  chmod 755 "$wrapper_dst"
else
  log "PLAN: create $wrapper_dst"
fi

if [ "$apply" = "1" ]; then
  HOME_EDGE_RECONCILE_ROOT="${BOOTSTRAP_RECONCILE_ROOT:-}" \
    HOME_EDGE_WRITE_LOCK_DIR="$write_lock_dir" HOME_EDGE_WRITE_LOCK_STALE_SEC="$write_lock_stale_sec" \
    HOME_EDGE_WRITE_LOCK_HELD=1 \
    sh "$reconcile_dst" --install || die "self-heal lifecycle registration failed"
else
  log "PLAN: install persistent services-start hook and reconcile self-heal cron"
fi

if [ "$apply" = "1" ]; then
  log "running DRY-RUN self-heal verification"
  if ! HEAL_DRY_RUN=1 sh "$self_heal_dst"; then
    if [ "$runtime_install" = "1" ]; then
      log "WARN self-heal dry-run failed after offline runtime install; import/start a subscription, then rerun status checks"
    else
      die "self-heal dry-run failed; see /tmp/self-heal.log"
    fi
  fi
  tail -n 5 /tmp/self-heal.log 2>/dev/null || true
else
  log "plan complete; rerun with BOOTSTRAP_APPLY=1 to install"
fi
