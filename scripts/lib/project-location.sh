# Shared structural identity check; no Git or network access is required.
home_edge_project_dir() {
  candidate=$1
  [ -n "$candidate" ] && [ -d "$candidate" ] || { echo 'Choose the complete cloned or extracted project folder.' >&2; return 2; }
  case "$candidate" in *"
"*|*"$(printf '\r')"*) echo 'Project paths cannot contain line breaks.' >&2; return 2 ;; esac
  candidate=$(CDPATH= cd "$candidate" && pwd -P) || return 2
  [ -f "$candidate/PROJECT" ] && [ "$(cat "$candidate/PROJECT")" = 'home-edge-bootstrap/project/v1' ] || { echo 'Not a Home Edge Bootstrap folder: PROJECT identity is missing or invalid.' >&2; return 2; }
  for required in README.md scripts/tui.sh scripts/launch-tui.sh scripts/lib/project-location.sh; do
    [ -f "$candidate/$required" ] || { echo "Incomplete project folder: missing $required. Extract the whole package or update the complete clone." >&2; return 2; }
  done
  printf '%s\n' "$candidate"
}
