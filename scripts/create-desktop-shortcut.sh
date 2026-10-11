#!/bin/sh
# Native desktop integration; copied launchers remain usable after a repo moves.
set -eu
umask 077
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
. "$repo/scripts/lib/project-location.sh"
. "$repo/scripts/lib/host-launcher.sh"
repo=$(home_edge_project_dir "$repo") || exit 2
desktop=''; launcher=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --directory) [ "$#" -ge 2 ] || exit 2; desktop=$2; shift 2 ;;
    --launcher-dir) [ "$#" -ge 2 ] || exit 2; launcher=$2; shift 2 ;;
    *) echo 'usage: create-desktop-shortcut.sh [--directory <desktop-folder>] [--launcher-dir <application-folder>]' >&2; exit 2 ;;
  esac
done
platform=$(uname -s)
case "$platform" in
  MINGW*|MSYS*|CYGWIN*)
    shell=''
    for candidate_shell in powershell.exe pwsh.exe; do
      if command -v "$candidate_shell" >/dev/null 2>&1; then shell=$candidate_shell; break; fi
    done
    [ -n "$shell" ] && command -v cygpath >/dev/null 2>&1 || { echo 'Windows PowerShell or cygpath is unavailable; open create-desktop-shortcut.cmd from the project folder.' >&2; exit 2; }
    script=$(cygpath -w "$repo/scripts/create-desktop-shortcut.ps1")
    set -- -NoProfile -ExecutionPolicy Bypass -File "$script"
    [ -z "$desktop" ] || set -- "$@" -DestinationDirectory "$(cygpath -w "$desktop")"
    [ -z "$launcher" ] || set -- "$@" -LauncherDirectory "$(cygpath -w "$launcher")"
    exec "$shell" "$@"
    ;;
esac
for tool in mkdir cp chmod cat sed tr stat find wc mktemp mv rm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool; use directory-local start.sh until it is available." >&2; exit 2; }
done
directory_identity=$(home_edge_directory_identity "$repo") || exit 2
case "$platform" in
  Darwin)
    for tool in ln readlink; do command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool; use directory-local start.command." >&2; exit 2; }; done
    [ -n "$desktop" ] || desktop="$HOME/Desktop"
    [ -n "$launcher" ] || launcher="$HOME/Library/Application Support/HomeEdgeBootstrap/launcher"
    entry="$desktop/Home Edge Bootstrap.command"
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      [ -L "$entry" ] || { echo 'Unrelated desktop file was not changed.' >&2; exit 2; }
      old_target=$(readlink "$entry")
      [ "${old_target##*/}" = home-edge.command ] || { echo 'Unrelated desktop link was not changed.' >&2; exit 2; }
      [ -f "$(dirname "$old_target")/.home-edge-launcher-owned" ] && [ "$(cat "$(dirname "$old_target")/.home-edge-launcher-owned")" = 'home-edge-bootstrap/registered-launcher/v1' ] || { echo 'Unrelated desktop link was not changed.' >&2; exit 2; }
    fi
    ;;
  Linux)
    command -v base64 >/dev/null 2>&1 || { echo 'Missing base64; use directory-local start.sh.' >&2; exit 2; }
    if [ -z "$desktop" ]; then
      if command -v xdg-user-dir >/dev/null 2>&1; then desktop=$(xdg-user-dir DESKTOP); else desktop="$HOME/Desktop"; fi
    fi
    [ -n "$launcher" ] || launcher="${XDG_DATA_HOME:-$HOME/.local/share}/home-edge-bootstrap/launcher"
    entry="$desktop/home-edge-bootstrap.desktop"
    home_edge_registration_leaf "$entry" || exit 2
    if [ -e "$entry" ] || [ -L "$entry" ]; then
      [ ! -L "$entry" ] && grep -Fxq 'X-HomeEdgeBootstrap-Managed=true' "$entry" || { echo 'Unrelated desktop entry was not changed.' >&2; exit 2; }
    fi
    ;;
  *) echo "Desktop integration is unavailable for $platform; keep using the directory-local start.sh when its prerequisites are available." >&2; exit 2 ;;
esac
[ -n "$desktop" ] && [ "$desktop" != "$HOME" ] && [ -d "$desktop" ] || { echo 'No desktop folder is available. The directory-local start.sh remains usable.' >&2; exit 2; }
desktop=$(CDPATH= cd "$desktop" && pwd -P)
case "$launcher" in /*) ;; *) launcher="$(pwd -P)/$launcher" ;; esac
case "$platform" in Darwin) entry="$desktop/Home Edge Bootstrap.command" ;; Linux) entry="$desktop/home-edge-bootstrap.desktop" ;; esac
home_edge_registration_paths "$launcher" || exit 2
if [ -d "$launcher" ]; then
  if [ -f "$launcher/.home-edge-launcher-owned" ]; then
    [ "$(cat "$launcher/.home-edge-launcher-owned")" = 'home-edge-bootstrap/registered-launcher/v1' ] || { echo 'Another ownership marker was not overwritten.' >&2; exit 2; }
  elif [ -n "$(find "$launcher" -mindepth 1 ! -type d ! -path "$launcher/.home-edge-launcher.lock/owner" -print)" ] || [ -n "$(find "$launcher" -mindepth 1 -type d ! -path "$launcher/lib" ! -path "$launcher/.home-edge-launcher.lock" -print)" ]; then
    echo 'Unowned nonempty launcher directory was not overwritten. Choose an empty folder or keep using start.sh.' >&2; exit 2
  fi
fi
if [ "$platform" = Linux ]; then
  if ! encoded=$(printf '%s' "$launcher/launch-tui.sh" | base64); then echo 'base64 failed; directory-local start.sh remains usable.' >&2; exit 2; fi
  encoded=$(printf '%s' "$encoded" | tr -d '\r\n')
  [ -n "$encoded" ] || { echo 'Empty encoded launcher path; no desktop entry was installed.' >&2; exit 2; }
fi
mkdir -p "$launcher"
home_edge_acquire_launcher_lock "$launcher" || exit 2
trap 'home_edge_release_launcher_lock' 0
trap 'exit 2' HUP INT TERM
home_edge_registration_paths "$launcher" || exit 2
if [ "$platform" = Linux ]; then home_edge_registration_leaf "$entry" || exit 2; fi
mkdir -p "$launcher/lib"
printf 'home-edge-bootstrap/registered-launcher/v1\n' | home_edge_write_registration "$launcher/.home-edge-launcher-owned"
home_edge_write_registration "$launcher/launch-tui.sh" 700 <"$repo/scripts/launch-tui.sh"
home_edge_write_registration "$launcher/lib/project-location.sh" <"$repo/scripts/lib/project-location.sh"
home_edge_write_registration "$launcher/lib/host-launcher.sh" <"$repo/scripts/lib/host-launcher.sh"
printf 'home-edge-bootstrap/target/v2\n%s\n%s\n' "$repo" "$directory_identity" | home_edge_write_registration "$launcher/target.txt"
home_edge_write_registration "$launcher/home-edge.command" 700 <<'EOF'
#!/bin/sh
# home-edge-bootstrap/registered-launcher/v1
set -eu
script=$0
links=0
while [ -L "$script" ]; do
  links=$((links + 1))
  [ "$links" -le 40 ] || { echo 'Desktop entry has a symbolic-link cycle.' >&2; exit 2; }
  target=$(readlink "$script")
  case "$target" in /*) script=$target ;; *) script="$(dirname "$script")/$target" ;; esac
done
launcher=$(CDPATH= cd "$(dirname "$script")" && pwd -P)
exec sh "$launcher/launch-tui.sh" "$@"
EOF
if [ "$platform" = Darwin ]; then
  shortcut_temporary=$(mktemp "$desktop/.home-edge-shortcut.XXXXXX")
  rm "$shortcut_temporary"
  if ! ln -s "$launcher/home-edge.command" "$shortcut_temporary" || ! mv -f "$shortcut_temporary" "$entry"; then
    rm -f "$shortcut_temporary"
    exit 2
  fi
else
  # Exec stays ASCII; decoding produces one quoted filename, never shell code.
  sed "s|@PATH64@|$encoded|" <<'EOF' | home_edge_write_registration "$entry" 700
[Desktop Entry]
Type=Application
Name=Home Edge Bootstrap
Comment=Open the validated project guide
Terminal=true
Exec=/bin/sh -c "exec /bin/sh \\"\\$(echo @PATH64@ | base64 -d)\\""
Icon=utilities-terminal
Categories=Network;Utility;
X-HomeEdgeBootstrap-Managed=true
EOF
  echo 'If the desktop requests trust, use its Allow Launching action after checking this project. No trust setting was changed.'
fi
home_edge_release_launcher_lock || exit 2
trap - 0 HUP INT TERM
echo 'shortcut_state=created'
if [ "$platform" = Linux ]; then echo 'desktop_trust_state=not_changed'; fi
printf 'desktop_entry=%s\nregistered_project=%s\n' "$entry" "$repo"
