# Read-only Merlin project-installation inventory. Runtime presence is separate.
# Call with HOME_EDGE_INSTALLATION_DIR and (for isolated tests only) FIXTURE_ROOT.
home_edge_install_emit() {
  printf 'project_install_schema=1\nproject_install_router=%s\nproject_install_state=%s\nproject_install_reason=%s\nproject_install_path=%s\nproject_install_replace_allowed=%s\n' \
    "${HOME_EDGE_INSTALLATION_ROUTER:-unbound}" "$home_edge_install_state" \
    "$home_edge_install_reason" "$home_edge_install_dir" "$home_edge_install_replace_allowed"
}

home_edge_install_unknown() {
  home_edge_install_state=unknown
  home_edge_install_reason=$1
  home_edge_install_replace_allowed=0
}

home_edge_inspect_installation() {
  home_edge_install_dir=${HOME_EDGE_INSTALLATION_DIR:-/jffs/home-edge-bootstrap}
  home_edge_install_root=${HOME_EDGE_INSTALLATION_FIXTURE_ROOT:-}
  home_edge_install_state=unknown
  home_edge_install_reason=invalid_path
  home_edge_install_replace_allowed=0
  case "$home_edge_install_dir" in /jffs/?*) ;; *) home_edge_install_emit; return 0 ;; esac
  home_edge_install_leaf=${home_edge_install_dir#/jffs/}
  case "$home_edge_install_leaf" in ''|.|..|*/*|*[!A-Za-z0-9_.-]*) home_edge_install_emit; return 0 ;; esac
  case "$home_edge_install_root" in ''|/*) ;; *) home_edge_install_unknown invalid_fixture_root; home_edge_install_emit; return 0 ;; esac
  home_edge_install_jffs="$home_edge_install_root/jffs"
  home_edge_install_kit="$home_edge_install_root$home_edge_install_dir"
  home_edge_install_scripts="$home_edge_install_jffs/scripts"
  home_edge_install_stable="$home_edge_install_jffs/home-edge-bootstrap-state"
  home_edge_install_seen=0
  home_edge_install_owned=0
  home_edge_install_complete=0
  home_edge_install_stable_ready=0
  for home_edge_install_tool in grep cmp; do
    if ! which "$home_edge_install_tool" >/dev/null 2>&1; then
      home_edge_install_unknown observer_dependency_unavailable; home_edge_install_emit; return 0
    fi
  done
  if [ "$home_edge_install_dir" != /jffs/home-edge-bootstrap ] &&
     { [ -e "$home_edge_install_jffs/home-edge-bootstrap" ] || [ -L "$home_edge_install_jffs/home-edge-bootstrap" ]; }; then
    home_edge_install_unknown installation_path_mismatch; home_edge_install_emit; return 0
  fi

  # An inaccessible parent cannot establish absence. Never follow a symlink.
  for home_edge_install_parent in "$home_edge_install_jffs" "$home_edge_install_scripts" "$home_edge_install_kit" "$home_edge_install_stable" "${home_edge_install_kit}.prev"; do
    if [ -L "$home_edge_install_parent" ]; then
      home_edge_install_unknown symlink_path; home_edge_install_emit; return 0
    fi
    if [ -e "$home_edge_install_parent" ]; then
      if [ ! -d "$home_edge_install_parent" ]; then
        home_edge_install_unknown foreign_path; home_edge_install_emit; return 0
      fi
      if [ ! -r "$home_edge_install_parent" ] || [ ! -x "$home_edge_install_parent" ]; then
        home_edge_install_unknown unreadable_path; home_edge_install_emit; return 0
      fi
    fi
  done
  if [ ! -d "$home_edge_install_jffs" ]; then
    home_edge_install_unknown inaccessible_parent; home_edge_install_emit; return 0
  fi

  if [ -d "$home_edge_install_kit" ]; then
    home_edge_install_seen=1
    for home_edge_install_child in bootstrap.sh adapters adapters/merlin adapters/merlin/bootstrap.sh config config/policy.env scripts; do
      if [ -L "$home_edge_install_kit/$home_edge_install_child" ]; then
        home_edge_install_unknown symlink_path; home_edge_install_emit; return 0
      fi
    done
    if [ -r "$home_edge_install_kit/bootstrap.sh" ] &&
       [ -r "$home_edge_install_kit/adapters/merlin/bootstrap.sh" ] &&
       grep -Eq 'BOOTSTRAP_ADAPTER|Home Edge|home-edge-bootstrap' "$home_edge_install_kit/bootstrap.sh" &&
       grep -Fq 'Merlin adapter' "$home_edge_install_kit/adapters/merlin/bootstrap.sh"; then
      home_edge_install_owned=1
    else
      home_edge_install_unknown foreign_project_directory; home_edge_install_emit; return 0
    fi
  fi
  if [ -d "${home_edge_install_kit}.prev" ]; then
    home_edge_install_seen=1
    # A backup is not proof of current installation, nor permission to delete it.
  fi
  for home_edge_install_residue in "${home_edge_install_kit}".tmp.* "${home_edge_install_kit}".failed.* "${home_edge_install_kit}".runtime-failed.*; do
    [ -e "$home_edge_install_residue" ] || [ -L "$home_edge_install_residue" ] || continue
    home_edge_install_seen=1
    if [ -L "$home_edge_install_residue" ]; then
      home_edge_install_unknown symlink_path; home_edge_install_emit; return 0
    fi
  done
  for home_edge_install_file in "$home_edge_install_scripts"/home-edge-*; do
    [ -e "$home_edge_install_file" ] || [ -L "$home_edge_install_file" ] || continue
    home_edge_install_seen=1
    if [ -L "$home_edge_install_file" ]; then
      home_edge_install_unknown symlink_path; home_edge_install_emit; return 0
    fi
    if [ ! -f "$home_edge_install_file" ] || [ ! -r "$home_edge_install_file" ]; then
      home_edge_install_unknown unreadable_artifact; home_edge_install_emit; return 0
    fi
    # Keep exact empty historical policy backups as unowned residue. They are
    # neither active configuration nor proof of installation ownership.
    case "${home_edge_install_file##*/}" in
      home-edge-policy.local.bak.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9])
        [ -s "$home_edge_install_file" ] || continue
        ;;
    esac
    # A familiar filename alone does not establish project ownership.
    case "${home_edge_install_file##*/}" in
      home-edge-policy.env) home_edge_install_signature='HEAL_GROUP|HEAL_DRY_RUN' ;;
      home-edge-self-heal.sh) home_edge_install_signature='HEAL_DRY_RUN|selector self-heal' ;;
      home-edge-update-sub.sh) home_edge_install_signature='SUBSCRIPTION_POLICY_FILE|validated Mihomo/Clash YAML' ;;
      *) home_edge_install_signature='HOME_EDGE|home-edge|home_edge|ShellCrash|SUBSCRIPTION_' ;;
    esac
    home_edge_install_identified=0
    if grep -Eq "$home_edge_install_signature" "$home_edge_install_file"; then home_edge_install_identified=1; fi
    # These shipped helpers have no textual ownership marker. Match their bytes
    # against the recognized current kit instead of guessing from the filename.
    case "${home_edge_install_file##*/}" in
      home-edge-subscription-tools.sh|home-edge-subscription-merge.jq)
        home_edge_install_source=${home_edge_install_file##*/}
        home_edge_install_source="$home_edge_install_kit/scripts/${home_edge_install_source#home-edge-}"
        if [ ! -L "$home_edge_install_source" ] && [ -f "$home_edge_install_source" ] &&
           cmp -s "$home_edge_install_source" "$home_edge_install_file"; then home_edge_install_identified=1; fi
        ;;
    esac
    if [ "$home_edge_install_identified" != 1 ]; then
      home_edge_install_unknown foreign_active_artifact; home_edge_install_emit; return 0
    fi
  done
  home_edge_install_hook="$home_edge_install_scripts/services-start"
  if [ -L "$home_edge_install_hook" ]; then
    home_edge_install_unknown symlink_path; home_edge_install_emit; return 0
  fi
  if [ -e "$home_edge_install_hook" ]; then
    if [ ! -f "$home_edge_install_hook" ] || [ ! -r "$home_edge_install_hook" ]; then
      home_edge_install_unknown unreadable_artifact; home_edge_install_emit; return 0
    fi
    if grep -Fq '# BEGIN home-edge-bootstrap ' "$home_edge_install_hook"; then
      home_edge_install_seen=1
      home_edge_install_owned=1
    fi
  fi
  if [ -d "$home_edge_install_stable" ]; then
    home_edge_install_seen=1
    for home_edge_install_child in lifecycle lifecycle/state.env; do
      if [ -L "$home_edge_install_stable/$home_edge_install_child" ]; then
        home_edge_install_unknown symlink_path; home_edge_install_emit; return 0
      fi
    done
    home_edge_install_schema="$home_edge_install_stable/lifecycle/state.env"
    if [ -e "$home_edge_install_schema" ] && { [ ! -f "$home_edge_install_schema" ] || [ ! -r "$home_edge_install_schema" ]; }; then
      home_edge_install_unknown unreadable_artifact; home_edge_install_emit; return 0
    fi
    if [ -r "$home_edge_install_schema" ] &&
       grep -Fxq 'state_schema_version=1' "$home_edge_install_schema" &&
       grep -Fxq 'stable_state_root=/jffs/home-edge-bootstrap-state' "$home_edge_install_schema"; then
      home_edge_install_owned=1
      home_edge_install_stable_ready=1
    fi
  fi
  if [ -d "$home_edge_install_kit" ] && [ "$home_edge_install_owned" = 1 ] &&
     [ -s "$home_edge_install_kit/config/policy.env" ] &&
     [ -s "$home_edge_install_scripts/home-edge-policy.env" ] &&
     [ -s "$home_edge_install_scripts/home-edge-self-heal.sh" ] &&
     [ -s "$home_edge_install_scripts/home-edge-update-sub.sh" ]; then
    home_edge_install_complete=1
  fi
  if [ "$home_edge_install_complete" = 1 ] && [ "$home_edge_install_stable_ready" = 1 ]; then
    home_edge_install_state=installed; home_edge_install_reason=project_kit_and_active_scripts
  elif [ "$home_edge_install_complete" = 1 ]; then
    home_edge_install_state=partial; home_edge_install_reason=stable_state_incomplete
  elif [ "$home_edge_install_seen" = 1 ]; then
    home_edge_install_state=partial
    if [ -d "$home_edge_install_kit" ]; then home_edge_install_reason=project_active_scripts_incomplete
    else home_edge_install_reason=project_kit_missing; fi
  else
    home_edge_install_state=not_installed; home_edge_install_reason=no_project_artifacts
  fi
  home_edge_install_replace_allowed=$home_edge_install_owned
  home_edge_install_emit
}

# Reuse after acquiring the writer lock, before staging or deleting any kit.
home_edge_require_project_replacement() {
  case "$home_edge_install_state" in
    not_installed) return 0 ;;
    installed|partial)
      if [ "$home_edge_install_replace_allowed" = 1 ] && [ "$1" = 1 ] && [ "$2" = REPLACE ]; then return 0; fi
      echo 'deploy_guard_state=replacement_required' >&2
      ;;
    *) echo 'deploy_guard_state=unknown_installation' >&2 ;;
  esac
  return 1
}
