#!/bin/sh
# Host entry: build/verify tools independently of subscription automation.
set -eu
router=${1:-}
[ "$#" -eq 1 ] && printf '%s\n' "$router" | grep -Eq '^[A-Za-z0-9_][A-Za-z0-9_.-]*@([A-Za-z0-9][A-Za-z0-9_.:-]*|\[[0-9A-Fa-f:]+\])$' || {
  echo 'usage: [APPLY=1] [TOOLS_ONLY=1] sh enable-service-health.sh USER@ROUTER' >&2; exit 2;
}
case ${APPLY:-0} in 0|1) apply=${APPLY:-0} ;; *) exit 2 ;; esac
case ${TOOLS_ONLY:-0} in 0|1) tools_only=${TOOLS_ONLY:-0} ;; *) exit 2 ;; esac
repo=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
opts=${SSH_OPTS:-'-o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=yes'}
known_hosts=${KNOWN_HOSTS_FILE:-"${HOME:?HOME is required}/.ssh/known_hosts"}
for tool in ssh scp openssl gzip mktemp; do which "$tool" >/dev/null 2>&1 || { echo "service_health_enable=missing_$tool" >&2; exit 1; }; done
local_stage=$(mktemp -d "${TMPDIR:-/tmp}/home-edge-service-host.XXXXXX")
stage_id=$(openssl rand -hex 16)
case "$stage_id" in ''|*[!0-9a-f]*) exit 1 ;; esac
stage=/tmp/home-edge-service-enable.$stage_id
remote_owned=0
remote_active=0
cleanup() {
  if [ "$remote_owned" = 1 ] && [ "$remote_active" = 0 ]; then
    ssh $opts -o "UserKnownHostsFile=$known_hosts" -- "$router" "stage='$stage'; stage_id='$stage_id'; $(sed -n '/^# BEGIN SERVICE_HEALTH_CLEANUP$/,/^# END SERVICE_HEALTH_CLEANUP$/p' "$repo/scripts/enable-service-health.sh")" >/dev/null 2>&1 || echo 'service_health_enable=private_stage_cleanup_unconfirmed' >&2
  fi
  [ "$remote_active" = 0 ] || echo 'service_health_enable=remote_outcome_unknown; private stage retained for inspection' >&2
  for file in yamlbridge yamlbridge.gz yamlbridge.sha256 remote.sh; do rm -f "$local_stage/$file"; done
  rmdir "$local_stage" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
arch=$(ssh $opts -o "UserKnownHostsFile=$known_hosts" -- "$router" 'set -eu; for f in /jffs/scripts/home-edge-configure-service-health.sh /jffs/scripts/home-edge-service-health.sh /jffs/scripts/home-edge-service-health-preflight.sh; do [ -f "$f" ] && [ ! -L "$f" ] || { echo "service_health_enable=deploy_project_helpers_first" >&2; exit 1; }; done; uname -m')
case "$arch" in aarch64|arm64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; *) echo 'service_health_enable=unsupported_router_arch' >&2; exit 1 ;; esac
prebuilt=${SERVICE_HEALTH_PREBUILT:-}
if [ -n "$prebuilt" ]; then
  expected=${SERVICE_HEALTH_PREBUILT_SHA256:-}
  [ -f "$prebuilt" ] && [ ! -L "$prebuilt" ] || exit 1
  printf '%s\n' "$expected" | grep -Eq '^[a-fA-F0-9]{64}$' || { echo 'service_health_enable=prebuilt_digest_required' >&2; exit 1; }
  digest=$(openssl dgst -sha256 "$prebuilt" | awk '{print $NF}')
  [ "$digest" = "$(printf '%s' "$expected" | tr A-F a-f)" ] || { echo 'service_health_enable=prebuilt_digest_mismatch' >&2; exit 1; }
  cp "$prebuilt" "$local_stage/yamlbridge"
else
  which go >/dev/null 2>&1 || { echo 'service_health_enable=go_missing' >&2; echo 'next_step=provide Go on the host, or SERVICE_HEALTH_PREBUILT plus SERVICE_HEALTH_PREBUILT_SHA256; no compiler is installed automatically' >&2; exit 1; }
  (cd "$repo/tools/yamlbridge"; unset GOOS GOARCH; GOTOOLCHAIN=local go mod verify; GOTOOLCHAIN=local go test ./...; CGO_ENABLED=0 GOTOOLCHAIN=local GOOS=linux GOARCH=$arch go build -buildvcs=false -trimpath -ldflags='-s -w -buildid=' -o "$local_stage/yamlbridge" .)
  digest=$(openssl dgst -sha256 "$local_stage/yamlbridge" | awk '{print $NF}')
fi
gzip -n -c "$local_stage/yamlbridge" >"$local_stage/yamlbridge.gz"
printf '%s\n' "$digest" >"$local_stage/yamlbridge.sha256"
ssh $opts -o "UserKnownHostsFile=$known_hosts" -- "$router" "set -eu; umask 077; [ ! -e '$stage' ] && [ ! -L '$stage' ]; mkdir '$stage'; printf '%s\\n' '$stage_id' >'$stage/owner'"
remote_owned=1
scp -O $opts -o "UserKnownHostsFile=$known_hosts" -- "$local_stage/yamlbridge.gz" "$router:$stage/yamlbridge.gz"
scp -O $opts -o "UserKnownHostsFile=$known_hosts" -- "$local_stage/yamlbridge.sha256" "$router:$stage/yamlbridge.sha256"
{
  printf "stage='%s'\nstage_id='%s'\napply='%s'\ntools_only='%s'\n" "$stage" "$stage_id" "$apply" "$tools_only"
  sed -n '/^# BEGIN SERVICE_HEALTH_REMOTE$/,/^# END SERVICE_HEALTH_REMOTE$/p' "$repo/scripts/enable-service-health.sh"
} >"$local_stage/remote.sh"
remote_active=1
ssh $opts -o "UserKnownHostsFile=$known_hosts" -- "$router" 'tr -d "\r" | sh -s' <"$local_stage/remote.sh"
remote_active=0
exit 0

# BEGIN SERVICE_HEALTH_CLEANUP
case "$stage:$stage_id" in /tmp/home-edge-service-enable.*:*) ;; *) exit 1 ;; esac
[ ! -L "$stage" ] && [ -f "$stage/owner" ] && [ ! -L "$stage/owner" ] && [ "$(cat "$stage/owner" 2>/dev/null)" = "$stage_id" ] || exit 1
for file in owner yamlbridge.gz yamlbridge.sha256 yamlbridge old-raw help; do
  [ ! -L "$stage/$file" ] || exit 1
done
for file in yamlbridge.gz yamlbridge.sha256 yamlbridge old-raw help; do rm -f "$stage/$file" || exit 1; done
rm -f "$stage/owner"
rmdir "$stage"
# END SERVICE_HEALTH_CLEANUP

# BEGIN SERVICE_HEALTH_REMOTE
set -eu
umask 077
state=/jffs/home-edge-bootstrap-state
runtime=$state/runtime
prev=$runtime/service-health-tools-prev
lock=/tmp/home-edge-bootstrap-write.lock
owned_lock=0
pending_tools=0
fail() { echo "service_health_enable=$1" >&2; exit 1; }
safe_path() {
  p=$1
  while [ "$p" != / ]; do [ ! -L "$p" ] || return 1; p=$(dirname "$p"); done
}
sha() { openssl dgst -sha256 "$1" | awk '{print $NF}'; }
identity() {
  if [ -f /tmp/ShellCrash/shellcrash.pid ] && [ ! -L /tmp/ShellCrash/shellcrash.pid ]; then pid=$(cat /tmp/ShellCrash/shellcrash.pid); else pid=$(pidof CrashCore); fi
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  exe=$(readlink "/proc/$pid/exe") || return 1
  case "$exe" in /tmp/ShellCrash/CrashCore|'/tmp/ShellCrash/CrashCore (deleted)') ;; *) return 1 ;; esac
  started=$(awk '{print $22}' "/proc/$pid/stat") || return 1
  case "$started" in ''|*[!0-9]*) return 1 ;; esac
  printf '%s:%s\n' "$pid" "$started"
}
regular_or_absent() { [ ! -L "$1" ] && { [ ! -e "$1" ] || [ -f "$1" ]; }; }
restore_tools() {
  if [ "$before" = present ]; then [ "$(sha "$prev/yamlbridge.gz")" = "$old_archive_hash" ] && [ "$(sha "$prev/yamlbridge.sha256")" = "$old_digest_hash" ] || return 1; fi
  for name in yamlbridge.gz yamlbridge.sha256; do
    target=$runtime/$name
    regular_or_absent "$target" || return 1
    current=$(if [ -f "$target" ]; then sha "$target"; else echo absent; fi)
    old=$(if [ -f "$prev/$name" ]; then sha "$prev/$name"; else echo absent; fi)
    new=$(sha "$stage/$name")
    [ "$current" = "$old" ] || [ "$current" = "$new" ] || return 1
  done
  for name in yamlbridge.gz yamlbridge.sha256; do
    if [ "$before" = present ]; then cp "$prev/$name" "$runtime/$name.service-new.$stage_id" && chmod 600 "$runtime/$name.service-new.$stage_id" && mv -f "$runtime/$name.service-new.$stage_id" "$runtime/$name" || return 1
    else rm -f "$runtime/$name" || return 1; fi
  done
  rm -f "$prev/pending"
}
release_lock() {
  if [ "$owned_lock" = 1 ] && [ ! -L "$lock" ] && [ "$(cat "$lock/pid" 2>/dev/null)" = "$$" ] && [ "$(cat "$lock/operation" 2>/dev/null)" = "service-health-tools:$stage_id" ]; then
    rm -f "$lock/pid" "$lock/operation" "$lock/started_at"; rmdir "$lock" || return 1; owned_lock=0
  fi
}
finish() {
  if [ "$pending_tools" = 1 ]; then restore_tools || echo 'service_health_enable=tools_recovery_unresolved' >&2; fi
  for name in yamlbridge.gz yamlbridge.sha256; do
    temporary=$runtime/$name.service-new.$stage_id
    if [ -f "$temporary" ] && [ ! -L "$temporary" ]; then rm -f "$temporary"; fi
  done
  release_lock || true
}
trap finish EXIT
trap 'exit 130' HUP INT TERM
case "$stage_id" in ''|*[!a-f0-9]*) fail invalid_owner ;; esac
[ ${#stage_id} -eq 32 ] && [ "$stage" = "/tmp/home-edge-service-enable.$stage_id" ] || fail invalid_stage
safe_path "$stage" && [ -d "$stage" ] && [ -f "$stage/owner" ] && [ ! -L "$stage/owner" ] && [ "$(cat "$stage/owner")" = "$stage_id" ] || fail stage_ownership_unknown
for f in yamlbridge.gz yamlbridge.sha256; do [ -f "$stage/$f" ] && [ ! -L "$stage/$f" ] || fail invalid_stage_file; done
digest=$(cat "$stage/yamlbridge.sha256")
printf '%s\n' "$digest" | grep -Eq '^[a-f0-9]{64}$' || fail invalid_digest
[ ! -e "$stage/yamlbridge" ] && [ ! -L "$stage/yamlbridge" ] || fail foreign_stage_binary
gzip -dc "$stage/yamlbridge.gz" >"$stage/yamlbridge"
[ "$(sha "$stage/yamlbridge")" = "$digest" ] || fail native_digest_mismatch
chmod 700 "$stage/yamlbridge"
"$stage/yamlbridge" --help >"$stage/help" || fail native_execution_failed
grep -q 'service-health REQUEST' "$stage/help" || fail missing_service_health_capability
for f in /jffs/scripts/home-edge-configure-service-health.sh /jffs/scripts/home-edge-service-health.sh /jffs/scripts/home-edge-service-health-preflight.sh; do safe_path "$f" && [ -f "$f" ] || fail deploy_project_helpers_first; done
main_before=$(identity) || fail main_core_identity_unknown
case "$tools_only" in 0|1) ;; *) fail invalid_tools_only ;; esac
# Preview the exact choices APPLY will make; --plan itself remains read-only.
google_mode=auto; health_mode=auto
if [ "$tools_only" = 0 ]; then
  SERVICE_HEALTH_YAMLBRIDGE="$stage/yamlbridge" SERVICE_HEALTH_PROFILES=gemini SERVICE_HEALTH_GOOGLE_MODE="$google_mode" SERVICE_HEALTH_MODE="$health_mode" sh /jffs/scripts/home-edge-configure-service-health.sh --plan
else echo 'service_health_scope=tools_only; existing registration, routes and selections preserved'; fi
[ "$(identity)" = "$main_before" ] || fail main_core_changed
if [ "$apply" = 0 ]; then
  echo 'service_health_enable=planned'
  if [ "$tools_only" = 1 ]; then echo 'next_step=APPLY=1 TOOLS_ONLY=1 updates verified tools and preserves routing'; else echo 'next_step=APPLY=1 reruns validation and explicitly installs tools plus Google auto mode'; fi
  exit 0
fi
[ "$apply" = 1 ] || fail invalid_apply
safe_path "$runtime" && safe_path "$lock" || fail unsafe_protected_path
[ -d "$state" ] || fail project_state_missing
mkdir "$lock" 2>/dev/null || fail writer_busy
owned_lock=1
printf '%s\n' "$$" >"$lock/pid"; printf '%s\n' "service-health-tools:$stage_id" >"$lock/operation"; date +%s >"$lock/started_at"
mkdir -p "$runtime"; chmod 700 "$runtime"
for name in yamlbridge.gz yamlbridge.sha256; do regular_or_absent "$runtime/$name" || fail foreign_tools_file; done
before=absent
if [ -e "$runtime/yamlbridge.gz" ] || [ -e "$runtime/yamlbridge.sha256" ]; then
  [ -f "$runtime/yamlbridge.gz" ] && [ -f "$runtime/yamlbridge.sha256" ] || fail incomplete_existing_tools
  old_digest=$(cat "$runtime/yamlbridge.sha256")
  printf '%s\n' "$old_digest" | grep -Eq '^[a-f0-9]{64}$' || fail invalid_existing_digest
  gzip -dc "$runtime/yamlbridge.gz" >"$stage/old-raw"
  [ "$(sha "$stage/old-raw")" = "$old_digest" ] || fail existing_tools_hash_drift
  old_archive_hash=$(sha "$runtime/yamlbridge.gz"); old_digest_hash=$(sha "$runtime/yamlbridge.sha256")
  before=present
fi
if [ "$before" = present ] && [ "$old_digest" = "$digest" ]; then
  echo 'service_health_tools_state=reused'
else
  safe_path "$prev" || fail unsafe_tools_backup
  if [ -e "$prev" ]; then
    [ -d "$prev" ] && [ "$(cat "$prev/owner" 2>/dev/null)" = home-edge-service-tools-v1 ] && [ ! -e "$prev/pending" ] || fail tools_backup_requires_review
    for f in "$prev"/* "$prev"/.[!.]* "$prev"/..?*; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      case "$(basename "$f")" in owner|before-state|yamlbridge.gz|yamlbridge.sha256) [ -f "$f" ] && [ ! -L "$f" ] || fail foreign_tools_backup ;; *) fail foreign_tools_backup ;; esac
    done
    rm -f "$prev/before-state" "$prev/yamlbridge.gz" "$prev/yamlbridge.sha256"
  else mkdir "$prev"; printf '%s\n' home-edge-service-tools-v1 >"$prev/owner"; fi
  printf '%s\n' "$before" >"$prev/before-state"
  if [ "$before" = present ]; then cp "$runtime/yamlbridge.gz" "$prev/yamlbridge.gz"; cp "$runtime/yamlbridge.sha256" "$prev/yamlbridge.sha256"; fi
  if [ "$before" = present ]; then
    [ "$(sha "$prev/yamlbridge.gz")" = "$old_archive_hash" ] && [ "$(sha "$prev/yamlbridge.sha256")" = "$old_digest_hash" ] && [ "$(sha "$runtime/yamlbridge.gz")" = "$old_archive_hash" ] && [ "$(sha "$runtime/yamlbridge.sha256")" = "$old_digest_hash" ] || fail tools_changed_during_backup
  else [ ! -e "$runtime/yamlbridge.gz" ] && [ ! -e "$runtime/yamlbridge.sha256" ] || fail tools_changed_during_backup; fi
  printf '%s\n' "$stage_id" >"$prev/pending"; sync; pending_tools=1
  for name in yamlbridge.gz yamlbridge.sha256; do
    [ ! -e "$runtime/$name.service-new.$stage_id" ] && [ ! -L "$runtime/$name.service-new.$stage_id" ] || fail foreign_tools_stage
    cp "$stage/$name" "$runtime/$name.service-new.$stage_id"; chmod 600 "$runtime/$name.service-new.$stage_id"; mv -f "$runtime/$name.service-new.$stage_id" "$runtime/$name"
  done
  gzip -dc "$runtime/yamlbridge.gz" >"$stage/old-raw"
  [ "$(sha "$stage/old-raw")" = "$digest" ] && [ "$(cat "$runtime/yamlbridge.sha256")" = "$digest" ] || fail installed_tools_hash_drift
  sync; rm -f "$prev/pending"; pending_tools=0
  echo 'service_health_tools_state=installed'
fi
[ "$(identity)" = "$main_before" ] || fail main_core_changed
release_lock || fail lock_release_unresolved
if [ "$tools_only" = 1 ]; then echo 'service_health_enable=tools_updated'; exit 0; fi
SERVICE_HEALTH_YAMLBRIDGE="$stage/yamlbridge" SERVICE_HEALTH_PROFILES=gemini SERVICE_HEALTH_CONFIRM=APPLY SERVICE_HEALTH_GOOGLE_MODE=auto SERVICE_HEALTH_MODE=auto sh /jffs/scripts/home-edge-configure-service-health.sh --apply || { echo 'service_health_enable=tools_installed_setup_failed; setup recovery receipt and latest tools backup retained' >&2; exit 1; }
[ "$(identity)" = "$main_before" ] || fail main_core_changed
echo 'service_health_enable=applied'
echo 'verification_scope=configuration_only; account and client acceptance remain separate'
# END SERVICE_HEALTH_REMOTE
