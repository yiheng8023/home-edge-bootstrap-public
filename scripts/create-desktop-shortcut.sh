#!/bin/sh
# Native desktop integration; copied launchers remain usable after a repo moves.
set -eu
umask 077
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
. "$repo/scripts/lib/project-location.sh"
. "$repo/scripts/lib/host-launcher.sh"
repo=$(home_edge_project_dir "$repo") || exit 2
desktop=''; launcher=''; replace_registration=0; registration_confirmation=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --directory) [ "$#" -ge 2 ] || exit 2; desktop=$2; shift 2 ;;
    --launcher-dir) [ "$#" -ge 2 ] || exit 2; launcher=$2; shift 2 ;;
    --replace-registration) replace_registration=1; shift ;;
    --registration-confirmation) [ "$#" -ge 2 ] || exit 2; registration_confirmation=$2; shift 2 ;;
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
    [ "$replace_registration" = 0 ] || set -- "$@" -ReplaceRegistration
    [ -z "$registration_confirmation" ] || set -- "$@" -RegistrationConfirmation "$registration_confirmation"
    exec "$shell" "$@"
    ;;
esac
for tool in mkdir cp chmod cat sed tr stat find wc mktemp mv rm cmp grep; do
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
linux_desktop_entry() {
  # Use one template for both reuse verification and publication.
  sed "s|@PATH64@|$encoded|" <<'EOF'
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
}
mkdir -p "$launcher"
home_edge_acquire_launcher_lock "$launcher" || exit 2
trap 'home_edge_release_launcher_lock' 0
trap 'exit 2' HUP INT TERM
home_edge_registration_paths "$launcher" || exit 2
if [ "$platform" = Linux ]; then home_edge_registration_leaf "$entry" || exit 2; fi
registration_state=not_registered
existing_project=''
if [ -f "$launcher/.home-edge-launcher-owned" ]; then
  registration_state=partial
  if [ -f "$launcher/target.txt" ] && [ "$(wc -l <"$launcher/target.txt" | tr -d ' ')" = 3 ] &&
      [ "$(sed -n '1p' "$launcher/target.txt")" = home-edge-bootstrap/target/v2 ]; then
    existing_project=$(sed -n '2p' "$launcher/target.txt")
    existing_identity=$(sed -n '3p' "$launcher/target.txt")
    if [ -n "$existing_project" ] && [ -n "$existing_identity" ]; then
      registration_state=different_target
      if [ "$existing_project" = "$repo" ] && [ "$existing_identity" = "$directory_identity" ]; then registration_state=same_target; fi
    fi
  fi
fi
printf 'registration_state=%s\nrequested_project=%s\n' "$registration_state" "$repo"
[ -z "$existing_project" ] || printf 'registered_project=%s\n' "$existing_project"
entry_ready=0
case "$platform" in
  Darwin)
    if [ -L "$entry" ] && [ "$(readlink "$entry")" = "$launcher/home-edge.command" ]; then entry_ready=1; fi
    ;;
  Linux)
    if [ -f "$entry" ] && linux_desktop_entry | cmp -s - "$entry"; then entry_ready=1; fi
    ;;
esac
if [ "$registration_state" = same_target ] && [ "$replace_registration" = 0 ] && [ -z "$registration_confirmation" ] && [ "$entry_ready" = 1 ] && [ -f "$launcher/home-edge.command" ] &&
    cmp -s "$repo/scripts/launch-tui.sh" "$launcher/launch-tui.sh" &&
    cmp -s "$repo/scripts/lib/project-location.sh" "$launcher/lib/project-location.sh" &&
    cmp -s "$repo/scripts/lib/host-launcher.sh" "$launcher/lib/host-launcher.sh"; then
  echo 'shortcut_state=reused'
  echo 'Existing launcher already uses this project; no registration files were replaced.'
  exit 0
fi
if [ "$registration_state" != not_registered ]; then
  echo "This updates this computer's copied launcher and saved project location; it does not reinstall the router."
  if [ "$replace_registration" = 0 ]; then
    printf 'Existing registration found. Type REPLACE to choose an update; anything else cancels: '
    if ! IFS= read -r confirmation || [ "$confirmation" != REPLACE ]; then echo 'shortcut_state=cancelled'; exit 0; fi
  fi
  if [ -z "$registration_confirmation" ]; then
    printf 'Confirm the displayed project target. Type APPLY to replace this owned registration: '
    IFS= read -r registration_confirmation || registration_confirmation=''
  fi
  [ "$registration_confirmation" = APPLY ] || { echo 'shortcut_state=cancelled'; exit 0; }
elif [ "$replace_registration" != 0 ] || [ -n "$registration_confirmation" ]; then
  echo 'Replacement flags require an existing project-owned registration.' >&2; exit 2
fi
current_source=$(home_edge_project_dir "$repo") || exit 2
current_source_identity=$(home_edge_directory_identity "$current_source") || exit 2
if [ "$current_source" != "$repo" ] || [ "$current_source_identity" != "$directory_identity" ]; then
  echo 'The selected project directory changed during confirmation. Restart setup from the intended complete folder.' >&2
  exit 2
fi
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
  linux_desktop_entry | home_edge_write_registration "$entry" 700
  echo 'If the desktop requests trust, use its Allow Launching action after checking this project. No trust setting was changed.'
fi
home_edge_release_launcher_lock || exit 2
trap - 0 HUP INT TERM
echo 'shortcut_state=created'
if [ "$platform" = Linux ]; then echo 'desktop_trust_state=not_changed'; fi
printf 'desktop_entry=%s\nregistered_project=%s\n' "$entry" "$repo"
