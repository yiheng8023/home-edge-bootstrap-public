# POSIX host adapter for physical directory identity and local registration paths.
home_edge_directory_identity() {
  command -v stat >/dev/null 2>&1 || { echo 'Missing stat: use the directory-local start.sh until it is available.' >&2; return 2; }
  case "$(uname -s)" in
    Darwin) stat -f 'unix-v1:%d:%i:%B' "$1" ;;
    *) stat -L -c 'unix-v1:%d:%i:%W' "$1" ;;
  esac
}

home_edge_registration_leaf() {
  leaf=$1
  [ ! -L "$leaf" ] || { echo "Registration link was not overwritten: $leaf" >&2; return 2; }
  if [ -e "$leaf" ]; then
    [ -f "$leaf" ] || { echo "Unexpected registration path type: $leaf" >&2; return 2; }
    case "$(uname -s)" in
      Darwin) links=$(stat -f '%l' "$leaf") || return 2 ;;
      *) links=$(stat -c '%h' "$leaf") || return 2 ;;
    esac
    [ "$links" = 1 ] || { echo "Registration file has multiple hard links; it was not overwritten: $leaf" >&2; return 2; }
  fi
}

home_edge_registration_paths() {
  registration=$1
  for relative in '' lib .home-edge-launcher-owned target.txt home-edge.command launch-tui.sh lib/project-location.sh lib/host-launcher.sh; do
    path=$registration${relative:+/}$relative
    [ ! -L "$path" ] || { echo "Registration link was not overwritten: $path" >&2; return 2; }
    if [ -e "$path" ]; then
      case "$relative" in ''|lib) [ -d "$path" ] || { echo "Unexpected registration path type: $path" >&2; return 2; } ;;
      *) home_edge_registration_leaf "$path" || return 2 ;; esac
    fi
  done
}

home_edge_acquire_launcher_lock() {
  home_edge_lock_dir=$1/.home-edge-launcher.lock
  [ ! -L "$home_edge_lock_dir" ] || { echo 'Launcher lock is a symbolic link; it was not changed.' >&2; return 2; }
  if ! mkdir "$home_edge_lock_dir" 2>/dev/null; then
    echo 'Launcher registration is busy or its lock is unavailable; retry after the other launcher/setup closes.' >&2
    printf 'Lock directory: %s\n' "$home_edge_lock_dir" >&2
    lock_owner_state=unknown
    if [ -d "$home_edge_lock_dir" ] && home_edge_registration_leaf "$home_edge_lock_dir/owner" && [ -f "$home_edge_lock_dir/owner" ]; then
      owner_header=$(sed -n '1p' "$home_edge_lock_dir/owner")
      owner_pid=$(sed -n '2p' "$home_edge_lock_dir/owner")
      case "$owner_pid" in ''|*[!0-9]*) ;; *)
        if [ "$owner_header" = home-edge-bootstrap/launcher-lock/v1 ]; then
          if kill -0 "$owner_pid" 2>/dev/null; then lock_owner_state=active; echo "Lock owner process is active: $owner_pid" >&2
          else lock_owner_state=not_confirmed; echo "Lock owner process is inactive or inaccessible: $owner_pid; its exit is not confirmed." >&2; fi
        fi ;;
      esac
    fi
    printf 'Lock owner state: %s. Close the other setup/launcher process and retry.\n' "$lock_owner_state" >&2
    echo 'For a leftover lock, confirm that its owner process has ended before manually removing that lock directory, or choose a new empty registration directory. The directory-local start.sh remains usable.' >&2
    return 2
  fi
  if ! printf 'home-edge-bootstrap/launcher-lock/v1\n%s\n' "$$" >"$home_edge_lock_dir/owner"; then
    rmdir "$home_edge_lock_dir" 2>/dev/null || :
    return 2
  fi
  home_edge_lock_owned=$$
}

home_edge_release_launcher_lock() {
  [ -n "${home_edge_lock_owned:-}" ] || return 0
  [ ! -L "$home_edge_lock_dir" ] && [ -d "$home_edge_lock_dir" ] && home_edge_registration_leaf "$home_edge_lock_dir/owner" || return 2
  [ "$(cat "$home_edge_lock_dir/owner")" = "$(printf 'home-edge-bootstrap/launcher-lock/v1\n%s' "$home_edge_lock_owned")" ] || { echo 'Launcher lock ownership changed; it was not removed.' >&2; return 2; }
  rm "$home_edge_lock_dir/owner" && rmdir "$home_edge_lock_dir" || return 2
  home_edge_lock_owned=''
}

home_edge_write_registration() {
  write_path=$1
  write_mode=${2:-600}
  home_edge_registration_leaf "$write_path" || return 2
  write_temporary=$(mktemp "$write_path.tmp.XXXXXX") || return 2
  if ! cat >"$write_temporary" || ! chmod "$write_mode" "$write_temporary" || ! home_edge_registration_leaf "$write_path" || ! mv -f "$write_temporary" "$write_path"; then
    rm -f "$write_temporary"
    return 2
  fi
}
