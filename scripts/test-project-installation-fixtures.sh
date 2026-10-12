#!/bin/sh
# Isolated observations and real lock-time deployment guards; never contact SSH.
set -eu
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
tmp_parent=${TMPDIR:-/tmp}
tmp=$(mktemp -d "${tmp_parent%/}/home-edge-installation-test.XXXXXX")
# Test paths passed into strict router consumers must have neither doubled
# separators nor host aliases such as macOS /var -> /private/var.
tmp=$(CDPATH= cd "$tmp" && pwd -P) || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail() { echo "project_installation_fixture_tests=failed: $*" >&2; exit 1; }
. "$repo/adapters/merlin/lib/installation-state.sh"
export HOME_EDGE_INSTALLATION_ROUTER=user@router
export KNOWN_HOSTS_FILE="$tmp/known_hosts"
observe() {
  # Bash 3.2 function-prefix assignments can retain the earlier custom path.
  # Bind each ordinary observation explicitly instead of inheriting that probe.
  HOME_EDGE_INSTALLATION_DIR=/jffs/home-edge-bootstrap HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$1" home_edge_inspect_installation >"$tmp/observation"
  grep -Fxq "project_install_state=$2" "$tmp/observation" || { cat "$tmp/observation" >&2; fail "expected $2"; }
}
owned_kit() {
  mkdir -p "$1/jffs/home-edge-bootstrap/adapters/merlin" "$1/jffs/home-edge-bootstrap/config"
  cp "$repo/bootstrap.sh" "$1/jffs/home-edge-bootstrap/bootstrap.sh"
  cp "$repo/adapters/merlin/bootstrap.sh" "$1/jffs/home-edge-bootstrap/adapters/merlin/bootstrap.sh"
  cp "$repo/config/policy.env" "$1/jffs/home-edge-bootstrap/config/policy.env"
  mkdir -p "$1/jffs/home-edge-bootstrap/scripts"
  cp "$repo/scripts/subscription-tools.sh" "$repo/scripts/subscription-merge.jq" "$1/jffs/home-edge-bootstrap/scripts/"
  mkdir -p "$1/jffs/home-edge-bootstrap-state/lifecycle"
  printf 'state_schema_version=1\nstable_state_root=/jffs/home-edge-bootstrap-state\n' >"$1/jffs/home-edge-bootstrap-state/lifecycle/state.env"
}
fresh="$tmp/fresh"; mkdir -p "$fresh/jffs/ShellCrash" "$fresh/jffs/scripts"
printf 'user-runtime\n' >"$fresh/jffs/ShellCrash/CrashCore.gz"
observe "$fresh" not_installed
home_edge_require_project_replacement 0 '' || fail 'fresh install was blocked by standalone runtime'

installed="$tmp/installed"; owned_kit "$installed"; mkdir -p "$installed/jffs/scripts"
cp "$repo/config/policy.env" "$installed/jffs/scripts/home-edge-policy.env"
cp "$repo/scripts/self-heal.sh" "$installed/jffs/scripts/home-edge-self-heal.sh"
cp "$repo/scripts/update-sub.sh" "$installed/jffs/scripts/home-edge-update-sub.sh"
cp "$repo/scripts/subscription-tools.sh" "$installed/jffs/scripts/home-edge-subscription-tools.sh"
cp "$repo/scripts/subscription-merge.jq" "$installed/jffs/scripts/home-edge-subscription-merge.jq"
before=$(sha256sum "$installed/jffs/scripts/home-edge-self-heal.sh")
observe "$installed" installed

# A historical empty policy backup is preserved, but is not an active script or
# evidence of project ownership. Only the exact timestamped filename is exempt.
policy_backup="$installed/jffs/scripts/home-edge-policy.local.bak.20260630102243"
: >"$policy_backup"
backup_before=$(sha256sum "$policy_backup")
observe "$installed" installed
[ -f "$policy_backup" ] && [ ! -s "$policy_backup" ] || fail 'empty historical backup was changed'
[ "$backup_before" = "$(sha256sum "$policy_backup")" ] || fail 'empty historical backup bytes changed'
if home_edge_require_project_replacement 0 '' 2>/dev/null; then fail 'empty backup bypassed installed replacement guard'; fi

printf 'operator-policy-backup\n' >"$policy_backup"
backup_before=$(sha256sum "$policy_backup")
observe "$installed" unknown
grep -Fxq 'project_install_reason=foreign_active_artifact' "$tmp/observation" || fail 'nonempty unidentified backup was exempted'
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'nonempty unidentified backup was overridden'; fi
[ "$backup_before" = "$(sha256sum "$policy_backup")" ] || fail 'nonempty historical backup bytes changed'
rm "$policy_backup"

for backup_name in \
  home-edge-policy.local.bak.2026063010224 \
  home-edge-policy.local.bak.202606301022430 \
  home-edge-policy.local.bak.20260630102243.extra \
  home-edge-policy.local.bak.abcdefghijklmn \
  home-edge-policy.local; do
  wrong_backup="$installed/jffs/scripts/$backup_name"
  : >"$wrong_backup"
  backup_before=$(sha256sum "$wrong_backup")
  observe "$installed" unknown
  if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'unrecognized empty backup was overridden'; fi
  [ -f "$wrong_backup" ] && [ "$backup_before" = "$(sha256sum "$wrong_backup")" ] || fail 'unrecognized empty backup changed'
  rm "$wrong_backup"
done

empty_target="$tmp/empty-policy-backup-target"
: >"$empty_target"
backup_before=$(sha256sum "$empty_target")
MSYS=winsymlinks:nativestrict ln -s "$empty_target" "$policy_backup"
backup_link_before=$(readlink "$policy_backup")
observe "$installed" unknown
grep -Fxq 'project_install_reason=symlink_path' "$tmp/observation" || fail 'historical backup symlink was exempted'
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'historical backup symlink was overridden'; fi
[ -L "$policy_backup" ] && [ "$backup_link_before" = "$(readlink "$policy_backup")" ] || fail 'historical backup symlink changed'
[ "$backup_before" = "$(sha256sum "$empty_target")" ] || fail 'historical backup symlink target bytes changed'
rm "$policy_backup"

backup_only="$tmp/backup-only"; mkdir -p "$backup_only/jffs/scripts"
: >"$backup_only/jffs/scripts/home-edge-policy.local.bak.20260630102243"
observe "$backup_only" partial
grep -Fxq 'project_install_replace_allowed=0' "$tmp/observation" || fail 'empty backup established project ownership'
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'empty backup authorized replacing unowned residue'; fi
observe "$installed" installed

if home_edge_require_project_replacement 0 '' 2>"$tmp/guard"; then fail 'installed default allows writing'; fi
[ "$before" = "$(sha256sum "$installed/jffs/scripts/home-edge-self-heal.sh")" ] || fail 'observation changed active bytes'
for confirmation in '' replace 'REPLACE ' yes; do
  if home_edge_require_project_replacement 1 "$confirmation" 2>/dev/null; then fail 'inexact confirmation allowed'; fi
done
home_edge_require_project_replacement 1 REPLACE || fail 'explicit owned replacement unavailable'
HOME_EDGE_INSTALLATION_DIR=/jffs/other HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$installed" home_edge_inspect_installation >"$tmp/path-mismatch"
grep -Fxq 'project_install_reason=installation_path_mismatch' "$tmp/path-mismatch" || fail 'different installation target was accepted'
observe "$installed" installed
rm "$installed/jffs/home-edge-bootstrap-state/lifecycle/state.env"
observe "$installed" partial
grep -Fxq 'project_install_reason=stable_state_incomplete' "$tmp/observation" || fail 'missing stable schema was concealed'
printf 'state_schema_version=1\nstable_state_root=/jffs/home-edge-bootstrap-state\n' >"$installed/jffs/home-edge-bootstrap-state/lifecycle/state.env"
observe "$installed" installed
rm "$installed/jffs/scripts/home-edge-update-sub.sh"
observe "$installed" partial
home_edge_require_project_replacement 1 REPLACE || fail 'owned partial replacement unavailable'

orphan="$tmp/orphan"; mkdir -p "$orphan/jffs/scripts"
printf 'foreign-or-unknown\n' >"$orphan/jffs/scripts/home-edge-self-heal.sh"
observe "$orphan" unknown
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'unproven ownership was overridden'; fi
cp "$repo/scripts/self-heal.sh" "$orphan/jffs/scripts/home-edge-self-heal.sh"
observe "$orphan" partial
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'partial kit ownership was inferred from one active script'; fi
foreign="$tmp/foreign"; mkdir -p "$foreign/jffs/home-edge-bootstrap"
printf 'user-data\n' >"$foreign/jffs/home-edge-bootstrap/operator"
observe "$foreign" unknown
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'foreign path was overridden'; fi
linked="$tmp/linked"; mkdir -p "$linked/jffs"; MSYS=winsymlinks:nativestrict ln -s "$installed/jffs/home-edge-bootstrap" "$linked/jffs/home-edge-bootstrap"
observe "$linked" unknown
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'symlink was overridden'; fi
residue="$tmp/residue"; mkdir -p "$residue/jffs/home-edge-bootstrap.tmp.old"
observe "$residue" partial
if home_edge_require_project_replacement 1 REPLACE 2>/dev/null; then fail 'unknown staging ownership was overridden'; fi

mkdir -p "$tmp/bin"
cat >"$tmp/bin/ssh" <<'EOF'
#!/bin/sh
case "${INSTALL_PROBE_MODE:-ready}" in
  fail) cat >/dev/null; exit 23 ;;
  malformed) cat >/dev/null; echo 'project_install_state=not_installed'; exit 0 ;;
esac
payload=$(cat)
payload=$(printf '%s\n' "$payload" | sed "s#HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''#HOME_EDGE_INSTALLATION_FIXTURE_ROOT='$INSTALL_PROBE_ROOT'#")
output=$(printf '%s\n' "$payload" | sh -s)
if [ "${INSTALL_PROBE_MODE:-ready}" = mismatch ]; then
  printf '%s\n' "$output" | sed 's/^project_install_router=.*/project_install_router=user@other/'
else printf '%s\n' "$output"; fi
EOF
chmod 755 "$tmp/bin/ssh"
export HOME_EDGE_SSH_COMMAND="$tmp/bin/ssh" INSTALL_PROBE_ROOT="$fresh"
sh "$repo/scripts/check-project-installation.sh" user@router >"$tmp/fresh-host"
grep -Fxq 'project_install_state=not_installed' "$tmp/fresh-host" || fail 'fresh host observation missing'
for mode in fail malformed mismatch; do
  if INSTALL_PROBE_MODE="$mode" sh "$repo/scripts/check-project-installation.sh" user@router >"$tmp/$mode"; then fail "$mode observation passed"; fi
  grep -Fxq 'project_install_state=unknown' "$tmp/$mode" || fail "$mode did not preserve unknown"
done

# Capture actual deploy template after a successful preflight, without executing it.
cat >"$tmp/bin/capture-ssh" <<'EOF'
#!/bin/sh
last=''; for arg in "$@"; do last=$arg; done
[ "$last" = 'sh -s' ] || exit 27
payload=$(cat)
case "$payload" in
  *"HOME_EDGE_INSTALLATION_DIR='"*) printf '%s\n' "$payload" | "$INSTALL_PROBE_SSH" "$@" ;;
  *) printf '%s\n' "$payload" >"$INSTALL_CAPTURE_COMMAND" ;;
esac
EOF
chmod 755 "$tmp/bin/capture-ssh"
export INSTALL_PROBE_SSH="$tmp/bin/ssh" HOME_EDGE_SSH_COMMAND="$tmp/bin/capture-ssh" INSTALL_CAPTURE_COMMAND="$tmp/deploy-command"
# Deploy still uses the host ssh command for archive transfer, so isolate PATH too.
cp "$tmp/bin/capture-ssh" "$tmp/bin/deploy-ssh"
mkdir -p "$tmp/capture-bin"; cp "$tmp/bin/capture-ssh" "$tmp/capture-bin/ssh"
PATH="$tmp/capture-bin:$PATH" APPLY=1 sh "$repo/scripts/deploy-merlin.sh" user@router >"$tmp/captured"
test -s "$tmp/deploy-command" || fail 'actual deployment template was not captured'

# Only replace the known fixture paths in the captured code. The probe retains its
# logical /jffs target; mutations are rooted in the isolated fixture after it passes.
race="$tmp/race"; owned_kit "$race"; mkdir -p "$race/jffs/scripts"
cp "$repo/config/policy.env" "$race/jffs/scripts/home-edge-policy.env"
cp "$repo/scripts/self-heal.sh" "$race/jffs/scripts/home-edge-self-heal.sh"
cp "$repo/scripts/update-sub.sh" "$race/jffs/scripts/home-edge-update-sub.sh"
sed -e "s#remote_dir=\"/jffs/home-edge-bootstrap\"#remote_dir=\"$race/jffs/home-edge-bootstrap\"#" \
  -e 's#HOME_EDGE_INSTALLATION_DIR="$remote_dir"#HOME_EDGE_INSTALLATION_DIR="/jffs/home-edge-bootstrap"#' \
  -e "s#HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''#HOME_EDGE_INSTALLATION_FIXTURE_ROOT='$race'#" \
  -e "s#lock_dir=\"/tmp/home-edge-bootstrap-write.lock\"#lock_dir=\"$race/write.lock\"#" \
  "$tmp/deploy-command" >"$tmp/race-command"
if HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$race" sh "$tmp/race-command" </dev/null >"$tmp/race-out" 2>"$tmp/race-err"; then fail 'lock-time race allowed overwrite'; fi
grep -Fxq 'project_install_state=installed' "$tmp/race-out" || fail 'lock-time probe did not observe new installation'
grep -Fxq 'deploy_guard_state=replacement_required' "$tmp/race-err" || fail 'race was not stopped by replacement guard'
test -f "$race/jffs/home-edge-bootstrap/bootstrap.sh" || fail 'race mutated project kit'

# Exercise the actual remote transaction with a synthetic kit and local paths.
# The kit's bootstrap only installs fixture files; it never invokes a real adapter.
apply_root="$tmp/apply"; mkdir -p "$apply_root/jffs/ShellCrash" "$tmp/kit/adapters/merlin" "$tmp/kit/config"
printf 'operator-core\n' >"$apply_root/jffs/ShellCrash/CrashCore.gz"
cp "$repo/config/policy.env" "$tmp/kit/config/policy.env"
printf '# Merlin adapter fixture\n' >"$tmp/kit/adapters/merlin/bootstrap.sh"
cat >"$tmp/kit/bootstrap.sh" <<'EOF'
#!/bin/sh
# home-edge-bootstrap synthetic project; no router operations.
set -eu
mkdir -p "$INSTALL_APPLY_ROOT/jffs/home-edge-bootstrap-state/lifecycle" "$INSTALL_APPLY_ROOT/jffs/scripts"
printf 'state_schema_version=1\nstable_state_root=/jffs/home-edge-bootstrap-state\n' >"$INSTALL_APPLY_ROOT/jffs/home-edge-bootstrap-state/lifecycle/state.env"
cp config/policy.env "$INSTALL_APPLY_ROOT/jffs/scripts/home-edge-policy.env"
printf 'HEAL_DRY_RUN=1\n' >"$INSTALL_APPLY_ROOT/jffs/scripts/home-edge-self-heal.sh"
printf 'SUBSCRIPTION_POLICY_FILE=fixture\n' >"$INSTALL_APPLY_ROOT/jffs/scripts/home-edge-update-sub.sh"
EOF
tar -C "$tmp/kit" -czf "$tmp/kit.tgz" .
with_fixture_archive() {
  # Keep the actual heredoc/decoder transaction; substitute only the archive
  # bytes with a synthetic kit whose effects remain inside this fixture.
  base64 <"$1" >"$tmp/fixture.base64"
  awk -v payload_file="$tmp/fixture.base64" '
    /^decode_payload <<.* | tar -xzf/ {
      print; while ((getline payload_line < payload_file) > 0) print payload_line
      close(payload_file); payload=1; next
    }
    /^HOME_EDGE_ARCHIVE_BASE64$/ { payload=0 }
    !payload { print }
  '
}
rewrite_transaction() {
  sed -e "s#remote_dir=\"/jffs/home-edge-bootstrap\"#remote_dir=\"$apply_root/jffs/home-edge-bootstrap\"#" \
    -e 's#HOME_EDGE_INSTALLATION_DIR="$remote_dir"#HOME_EDGE_INSTALLATION_DIR="/jffs/home-edge-bootstrap"#' \
    -e "s#HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''#HOME_EDGE_INSTALLATION_FIXTURE_ROOT='$apply_root'#" \
    -e "s#lock_dir=\"/tmp/home-edge-bootstrap-write.lock\"#lock_dir=\"$apply_root/write.lock\"#" \
    -e "s#state_schema=/jffs/home-edge-bootstrap-state/lifecycle/state.env#state_schema=$apply_root/jffs/home-edge-bootstrap-state/lifecycle/state.env#" \
    "$tmp/deploy-command" | with_fixture_archive "$tmp/kit.tgz" >"$tmp/apply-command"
}
rewrite_transaction
HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$apply_root" INSTALL_APPLY_ROOT="$apply_root" sh "$tmp/apply-command" <"$tmp/kit.tgz" >"$tmp/apply-out" 2>"$tmp/apply-err" || { cat "$tmp/apply-err" >&2; fail 'fresh isolated transaction failed'; }
grep -Fxq 'deploy_state=applied' "$tmp/apply-out" || fail 'fresh transaction did not apply'
observe "$apply_root" installed
before=$(sha256sum "$apply_root/jffs/home-edge-bootstrap/bootstrap.sh")
if HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$apply_root" INSTALL_APPLY_ROOT="$apply_root" sh "$tmp/apply-command" <"$tmp/kit.tgz" >"$tmp/repeat-out" 2>"$tmp/repeat-err"; then fail 'repeat transaction overwrote without permission'; fi
[ "$before" = "$(sha256sum "$apply_root/jffs/home-edge-bootstrap/bootstrap.sh")" ] || fail 'repeat transaction changed project bytes'
BOOTSTRAP_REPLACE_PROJECT=1 BOOTSTRAP_PROJECT_CONFIRMATION=REPLACE APPLY=1 sh "$repo/scripts/deploy-merlin.sh" --project-only user@router >"$tmp/replace-capture"
rewrite_transaction
HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$apply_root" INSTALL_APPLY_ROOT="$apply_root" sh "$tmp/apply-command" <"$tmp/kit.tgz" >"$tmp/replace-out" 2>"$tmp/replace-err" || { cat "$tmp/replace-err" >&2; fail 'explicit owned transaction failed'; }
test -f "$apply_root/jffs/home-edge-bootstrap.prev/bootstrap.sh" || fail 'explicit replacement has no previous kit'
test "$(cat "$apply_root/jffs/ShellCrash/CrashCore.gz")" = operator-core || fail 'project transaction changed independent runtime core'

# Foreign .prev is protected even with explicit project replacement.
printf 'user-backup\n' >"$apply_root/jffs/home-edge-bootstrap.prev/operator"
rm "$apply_root/jffs/home-edge-bootstrap.prev/adapters/merlin/bootstrap.sh"
if HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$apply_root" INSTALL_APPLY_ROOT="$apply_root" sh "$tmp/apply-command" <"$tmp/kit.tgz" >"$tmp/foreign-prev-out" 2>"$tmp/foreign-prev-err"; then fail 'foreign previous backup was deleted'; fi
test "$(cat "$apply_root/jffs/home-edge-bootstrap.prev/operator")" = user-backup || fail 'foreign backup bytes changed'

# Execute the actual Merlin adapter through a captured custom-target transaction.
# Only self-heal observation and host/cron tools are stubbed; adapter path binding,
# installation, stable-state migration and lifecycle registration remain real.
custom_root="$tmp/custom-adapter"; custom_kit="$tmp/custom-kit"
mkdir -p "$custom_root/jffs/scripts" "$custom_root/jffs/ShellCrash" "$custom_kit/adapters/merlin" "$custom_kit/config" "$custom_kit/scripts" "$tmp/adapter-bin"
cp "$repo/bootstrap.sh" "$custom_kit/bootstrap.sh"
cp "$repo/adapters/merlin/bootstrap.sh" "$custom_kit/adapters/merlin/bootstrap.sh"
cp "$repo/config/policy.env" "$custom_kit/config/policy.env"
cp -a "$repo/scripts/." "$custom_kit/scripts/"
printf '#!/bin/sh\n# HEAL_DRY_RUN fixture; no network observation.\nexit 0\n' >"$custom_kit/scripts/self-heal.sh"
printf '#!/bin/sh\nexit 22\n' >"$tmp/adapter-bin/curl"
cat >"$tmp/adapter-bin/cru" <<'EOF'
#!/bin/sh
set -eu
case "${1:-}" in
  l) cat "$CRU_STATE" ;;
  d) grep -Fv "#${2:?}#" "$CRU_STATE" >"$CRU_STATE.next" || true; mv "$CRU_STATE.next" "$CRU_STATE" ;;
  a) printf '%s #%s#\n' "${3:?}" "${2:?}" >>"$CRU_STATE" ;;
  *) exit 2 ;;
esac
EOF
chmod 755 "$tmp/adapter-bin/curl" "$tmp/adapter-bin/cru"
: >"$tmp/custom-cru"
tar -C "$custom_kit" -czf "$tmp/custom-kit.tgz" .
REMOTE_DIR=/jffs/custom APPLY=1 sh "$repo/scripts/deploy-merlin.sh" --project-only user@router >"$tmp/custom-capture"
sed -e "s#remote_dir=\"/jffs/custom\"#remote_dir=\"$custom_root/jffs/custom\"#" \
  -e 's#HOME_EDGE_INSTALLATION_DIR="$remote_dir"#HOME_EDGE_INSTALLATION_DIR="/jffs/custom"#' \
  -e "s#HOME_EDGE_INSTALLATION_FIXTURE_ROOT=''#HOME_EDGE_INSTALLATION_FIXTURE_ROOT='$custom_root'#" \
  -e "s#lock_dir=\"/tmp/home-edge-bootstrap-write.lock\"#lock_dir=\"$custom_root/write.lock\"#" \
  -e "s#state_schema=/jffs/home-edge-bootstrap-state/lifecycle/state.env#state_schema=$custom_root/jffs/home-edge-bootstrap-state/lifecycle/state.env#" \
  "$tmp/deploy-command" | with_fixture_archive "$tmp/custom-kit.tgz" >"$tmp/custom-command"
run_custom_adapter_transaction() {
  # The captured deploy template owns the physical scratch lock. The adapter and
  # reconciler inherit held=1 and validate a logical router /tmp path without
  # touching it; host TMPDIR may be /var/folders on macOS.
  BOOTSTRAP_ADAPTER=merlin BOOTSTRAP_JFFS_DIR="$custom_root/jffs" \
    BOOTSTRAP_SCRIPT_DIR="$custom_root/jffs/scripts" BOOTSTRAP_SHELLCRASH_DIR="$custom_root/jffs/ShellCrash" \
    BOOTSTRAP_STATE_ROOT="$custom_root/jffs/home-edge-bootstrap-state" BOOTSTRAP_STATE_FIXTURE_ROOT="$custom_root" \
    BOOTSTRAP_RECONCILE_ROOT="$custom_root" HOME_EDGE_WRITE_LOCK_DIR=/tmp/home-edge-custom-fixture.lock \
    CRU_STATE="$tmp/custom-cru" PATH="$tmp/adapter-bin:$PATH" \
    sh "$1" <"$tmp/custom-kit.tgz"
}
run_custom_adapter_transaction "$tmp/custom-command" >"$tmp/custom-out" 2>"$tmp/custom-err" || { cat "$tmp/custom-err" >&2; fail 'actual adapter custom transaction failed'; }
grep -Fq "install_dir=$custom_root/jffs/custom" "$tmp/custom-out" || fail 'actual adapter received an unbound install directory'
test ! -e "$custom_root/jffs/home-edge-bootstrap" || fail 'custom adapter created the default project directory'
HOME_EDGE_INSTALLATION_DIR=/jffs/custom HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$custom_root" home_edge_inspect_installation >"$tmp/custom-observation"
grep -Fxq 'project_install_state=installed' "$tmp/custom-observation" || { cat "$tmp/custom-observation" >&2; fail 'custom installation cannot be observed after deployment'; }
# A default residue or another default installation remains protected and unknown.
mkdir "$custom_root/jffs/home-edge-bootstrap"
HOME_EDGE_INSTALLATION_DIR=/jffs/custom HOME_EDGE_INSTALLATION_FIXTURE_ROOT="$custom_root" home_edge_inspect_installation >"$tmp/custom-conflict"
grep -Fxq 'project_install_reason=installation_path_mismatch' "$tmp/custom-conflict" || fail 'default/custom path conflict was adopted'
test -d "$custom_root/jffs/home-edge-bootstrap" || fail 'observer deleted the old default residue'

echo 'project_installation_fixture_tests=ok'
