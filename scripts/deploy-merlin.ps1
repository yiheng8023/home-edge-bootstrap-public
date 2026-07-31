param(
  [string]$Router = $env:ROUTER,
  [string]$RemoteDir = "/jffs/home-edge-bootstrap",
  [string]$KnownHostsFile = "C:\tmp\home-edge-bootstrap-known-hosts",
  [int]$SshConnectTimeoutSec = 8,
  [switch]$IncludeBundle,
  [switch]$InstallRuntime,
  [switch]$ReplaceRuntime,
  [switch]$ReplaceCore,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
if (-not $Router) {
  throw "Router is required. Pass -Router <ssh-user>@<router-ip> or set ROUTER."
}
if ($RemoteDir -notmatch '^/jffs/[A-Za-z0-9_.-]+$') {
  throw "RemoteDir must be one concrete directory below /jffs without traversal or unsupported characters: $RemoteDir"
}

foreach ($Name in @("BOOTSTRAP_INSTALL_RUNTIME", "BOOTSTRAP_REPLACE_RUNTIME", "BOOTSTRAP_REPLACE_CORE")) {
  $Value = [Environment]::GetEnvironmentVariable($Name)
  if ($Value -and $Value -notin @("0", "1")) {
    throw "$Name must be 0 or 1."
  }
}
$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BundleDir = if ($env:DEPLOY_BUNDLE_DIR) {
  [System.IO.Path]::GetFullPath($env:DEPLOY_BUNDLE_DIR)
} else {
  Join-Path $Repo "bundle"
}
$RuntimeRequested = ($InstallRuntime -or $env:BOOTSTRAP_INSTALL_RUNTIME -eq "1")
$ReplaceRequested = ($ReplaceRuntime -or $env:BOOTSTRAP_REPLACE_RUNTIME -eq "1")
$ReplaceCoreRequested = ($ReplaceCore -or $env:BOOTSTRAP_REPLACE_CORE -eq "1")

function Assert-LocalBundle {
  $Required = @("mihomo-linux-arm64", "ShellCrash.tar.gz", "SHA256SUMS", "MANIFEST.json")
  foreach ($Name in $Required) {
    $Path = Join-Path $BundleDir $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-Item -LiteralPath $Path).Length -le 0) {
      throw "Missing or empty bundle/$Name"
    }
  }

  foreach ($Line in Get-Content -LiteralPath (Join-Path $BundleDir "SHA256SUMS")) {
    if (-not $Line.Trim()) { continue }
    $Parts = $Line -split "\s+", 2
    if ($Parts.Count -ne 2) { throw "Malformed SHA256SUMS line" }
    $Expected = $Parts[0].ToLowerInvariant()
    $Name = $Parts[1].Trim()
    if ($Name -notmatch '^[A-Za-z0-9_.-]+$') { throw "Unsupported bundle path in SHA256SUMS: $Name" }
    $Path = Join-Path $BundleDir $Name
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing bundle/$Name" }
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected) { throw "SHA256 mismatch for bundle/$Name" }
  }
}

$RuntimePayloadBytes = [int64]0
$RuntimeSpaceRequiredKiB = [int64]0
if ($RuntimeRequested) {
  Assert-LocalBundle
  foreach ($File in Get-ChildItem -LiteralPath $BundleDir -File) {
    $RuntimePayloadBytes += [int64]$File.Length
  }
  if ($RuntimePayloadBytes -le 0) {
    throw "Runtime bundle size is zero"
  }
  $RuntimeSpaceRequiredKiB = [int64][Math]::Ceiling(($RuntimePayloadBytes * 2) / 1KB) + 16384
}

$IncludeBundleResolved = [bool]$IncludeBundle
if (-not $Apply) {
  Write-Host "deploy_state=plan"
  Write-Host "apply_required=1"
  Write-Host "router=$Router"
  Write-Host "remote_dir=$RemoteDir"
  Write-Host "include_bundle=$([int]$IncludeBundleResolved)"
  Write-Host "install_runtime=$([int]$RuntimeRequested)"
  Write-Host "runtime_bundle_transport=$(if ($RuntimeRequested) { 'temporary' } else { 'none' })"
  Write-Host "replace_runtime=$([int]$ReplaceRequested)"
  Write-Host "replace_core=$([int]$ReplaceCoreRequested)"
  Write-Host "next_action=rerun with -Apply after reviewing this plan"
  exit 0
}

$Mode = "BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0"
if ($RuntimeRequested) {
  $Mode += " BOOTSTRAP_RUNTIME_FOLLOWS=1"
}

$RemoteTemplate = @'
set -eu
remote_dir="__REMOTE_DIR__"
runtime_follows="__RUNTIME_FOLLOWS__"
staging="${remote_dir}.tmp.$$"
previous="${remote_dir}.prev"
lock_dir="/tmp/home-edge-bootstrap-write.lock"
failed_dir="${remote_dir}.failed.$(date +%Y%m%d%H%M%S).$$"
lock_held=0

for protected_path in "$remote_dir" "$staging" "$previous"; do
  [ ! -L "$protected_path" ] || {
    echo "deploy-merlin: refusing symbolic-link deployment path: $protected_path" >&2
    exit 1
  }
done

cleanup_deploy() {
  rm -rf "$staging" 2>/dev/null || true
  if [ "$lock_held" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
handle_deploy_signal() {
  cleanup_deploy
  trap - EXIT
  exit 130
}
trap cleanup_deploy EXIT
trap handle_deploy_signal HUP INT TERM

acquire_deploy_lock() {
  if ! mkdir "$lock_dir" 2>/dev/null; then
    owner_pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
      operation=$(cat "$lock_dir/operation" 2>/dev/null || echo unknown)
      echo "deploy-merlin: global write lock held by pid=$owner_pid operation=$operation" >&2
      exit 1
    fi
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || { echo "deploy-merlin: stale deployment lock cannot be cleared" >&2; exit 1; }
    mkdir "$lock_dir" 2>/dev/null || { echo "deploy-merlin: deployment lock was reacquired" >&2; exit 1; }
    echo "deploy-merlin: recovered stale deployment lock" >&2
  fi
  lock_held=1
  date +%s >"$lock_dir/started_at" || { echo "deploy-merlin: cannot record write lock start" >&2; exit 1; }
  printf "%s\n" "$$" >"$lock_dir/pid" || { echo "deploy-merlin: cannot record write lock owner" >&2; exit 1; }
  printf "%s\n" deploy >"$lock_dir/operation" || { echo "deploy-merlin: cannot record write operation" >&2; exit 1; }
}

preserve_local_state() {
  prev="$1"
  current="$2"
  [ -d "$prev" ] || return 0
  for item in SUBSCRIPTION.local policy.local; do
    [ -e "$prev/$item" ] || continue
    cp -p "$prev/$item" "$current/$item"
  done
  for dir in cache backups; do
    [ -d "$prev/$dir" ] || continue
    rm -rf "$current/$dir"
    cp -a "$prev/$dir" "$current/$dir"
  done
}

cleanup_first_install_active_state() {
  cru d home_edge_selfheal >/dev/null 2>&1 || true
  services_start=/jffs/scripts/services-start
  if [ -f "$services_start" ] && [ ! -L "$services_start" ]; then
    services_tmp="${services_start}.deploy-rollback.$$"
    if awk '
      $0 == "# BEGIN home-edge-bootstrap self-heal lifecycle" { managed=1; next }
      $0 == "# END home-edge-bootstrap self-heal lifecycle" && managed { managed=0; next }
      !managed { print }
    ' "$services_start" >"$services_tmp"; then
      chmod 700 "$services_tmp" 2>/dev/null || true
      mv "$services_tmp" "$services_start" || rm -f "$services_tmp"
    else
      rm -f "$services_tmp"
    fi
  fi
  for active_file in \
    home-edge-policy.env \
    home-edge-policy.local \
    home-edge-self-heal.sh \
    home-edge-update-sub.sh \
    home-edge-subscription-runtime-evidence.sh \
    home-edge-verify-bundle.sh \
    home-edge-reconcile-self-heal.sh \
    home-edge-self-heal-cron.sh \
    home-edge-secure-temp.sh \
    home-edge-configure-dns.sh \
    home-edge-prefetch-shellcrash-data.sh \
    home-edge-start-shellcrash.sh \
    home-edge-configure-service-rules.sh
  do
    rm -f "/jffs/scripts/$active_file" 2>/dev/null || true
  done
}

rollback_deploy() {
  restored=0
  [ -d "$remote_dir" ] && mv "$remote_dir" "$failed_dir"
  if [ -d "$previous" ]; then
    mv "$previous" "$remote_dir"
    restored=1
  else
    cleanup_first_install_active_state
  fi
  if [ -f "$remote_dir/bootstrap.sh" ]; then
    if ! HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "$remote_dir/bootstrap.sh" >/dev/null 2>&1; then
      echo "deploy-merlin: WARN previous kit was restored but its bootstrap replay failed" >&2
    fi
  fi
  [ "$restored" = "1" ] && rm -rf "$failed_dir"
}

acquire_deploy_lock
rm -rf "$staging"
mkdir -p "$staging"
decode_payload() {
  if which base64 >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | base64 -d
  elif which openssl >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A
  else
    echo "deploy-merlin: base64 or openssl is required to decode deployment payload" >&2
    return 1
  fi
}
decode_payload | tar -xzf - -C "$staging"
[ -s "$staging/bootstrap.sh" ] || { echo "deploy-merlin: staged kit is incomplete" >&2; exit 1; }
rm -rf "$previous"
[ ! -d "$remote_dir" ] || mv "$remote_dir" "$previous"
if ! mv "$staging" "$remote_dir"; then
  [ ! -d "$previous" ] || mv "$previous" "$remote_dir"
  exit 1
fi
if ! preserve_local_state "$previous" "$remote_dir"; then
  rollback_deploy
  echo "deploy-merlin: local state preservation failed; previous kit restored" >&2
  exit 1
fi
if [ "$runtime_follows" = "1" ]; then
  echo "deploy_state=staged"
  echo "runtime_stage_required=1"
  echo "rollback_available=$([ -d "$previous" ] && echo 1 || echo 0)"
  exit 0
fi
if ! (cd "$remote_dir" && HOME_EDGE_WRITE_LOCK_HELD=1 __MODE__ sh bootstrap.sh); then
  rollback_deploy
  echo "deploy-merlin: bootstrap failed; previous kit restored" >&2
  exit 1
fi
state_schema=/jffs/home-edge-bootstrap-state/lifecycle/state.env
if [ ! -f "$state_schema" ] ||
  ! grep -Fxq "state_schema_version=1" "$state_schema" ||
  ! grep -Fxq "stable_state_root=/jffs/home-edge-bootstrap-state" "$state_schema"; then
  rollback_deploy
  echo "deploy-merlin: stable state schema verification failed; previous kit restored" >&2
  exit 1
fi
echo "deploy_state=applied"
echo "rollback_available=$([ -d "$previous" ] && echo 1 || echo 0)"
'@

$Remote = $RemoteTemplate.Replace("__REMOTE_DIR__", $RemoteDir).
  Replace("__MODE__", $Mode).
  Replace("__RUNTIME_FOLLOWS__", [int]$RuntimeRequested)
$ArchiveItems = @("README.md", "README.zh-CN.md", "bootstrap.sh", "adapters", "config", "docs", "scripts")
if ($IncludeBundleResolved) {
  $ArchiveItems += "bundle"
}

$Archive = Join-Path $env:TEMP ("home-edge-bootstrap-" + [System.Guid]::NewGuid().ToString("N") + ".tgz")
$BundleArchive = Join-Path $env:TEMP ("home-edge-runtime-bundle-" + [System.Guid]::NewGuid().ToString("N") + ".tgz")
$SourceArchive = Join-Path $env:TEMP ("home-edge-bootstrap-source-" + [System.Guid]::NewGuid().ToString("N") + ".tar")
$Stage = Join-Path $env:TEMP ("home-edge-bootstrap-stage-" + [System.Guid]::NewGuid().ToString("N"))
$KnownHostsDir = Split-Path -Parent $KnownHostsFile
$SshArgs = @(
  "-o", "BatchMode=yes",
  "-o", "ConnectTimeout=$SshConnectTimeoutSec",
  "-o", "ConnectionAttempts=1",
  "-o", "StrictHostKeyChecking=accept-new",
  "-o", "UserKnownHostsFile=$KnownHostsFile",
  "--",
  $Router
)

try {
  New-Item -ItemType Directory -Force $KnownHostsDir | Out-Null
  if ($RuntimeRequested) {
    $RuntimeSpaceTemplate = @'
set -eu
required_kib=__REQUIRED_KIB__
payload_bytes=__PAYLOAD_BYTES__
available_kib=$(
  LC_ALL=C df -k /tmp 2>/dev/null |
    awk 'NR > 1 && NF >= 4 && $4 ~ /^[0-9]+$/ { available = $4 } END { if (available == "") exit 1; print available }'
) || {
  echo "runtime_space_preflight_state=unavailable"
  echo "runtime_bundle_payload_bytes=$payload_bytes"
  echo "runtime_space_required_kib=$required_kib"
  echo "deploy-merlin: cannot determine available /tmp space" >&2
  exit 1
}
case "$available_kib" in
  ""|*[!0-9]*)
    echo "runtime_space_preflight_state=unavailable"
    echo "runtime_bundle_payload_bytes=$payload_bytes"
    echo "runtime_space_required_kib=$required_kib"
    echo "deploy-merlin: invalid available /tmp space" >&2
    exit 1
    ;;
esac
echo "runtime_bundle_payload_bytes=$payload_bytes"
echo "runtime_space_required_kib=$required_kib"
echo "runtime_space_available_kib=$available_kib"
if [ "$available_kib" -lt "$required_kib" ]; then
  echo "runtime_space_preflight_state=insufficient"
  echo "deploy-merlin: insufficient /tmp space for temporary runtime bundle" >&2
  exit 1
fi
echo "runtime_space_preflight_state=ready"
'@
    $RuntimeSpaceRemote = $RuntimeSpaceTemplate.
      Replace("__REQUIRED_KIB__", $RuntimeSpaceRequiredKiB.ToString([Globalization.CultureInfo]::InvariantCulture)).
      Replace("__PAYLOAD_BYTES__", $RuntimePayloadBytes.ToString([Globalization.CultureInfo]::InvariantCulture))
    & ssh @SshArgs $RuntimeSpaceRemote
    if ($LASTEXITCODE -ne 0) {
      exit $LASTEXITCODE
    }
  }

  New-Item -ItemType Directory -Force $Stage | Out-Null
  & tar -C $Repo -cf $SourceArchive @ArchiveItems
  if ($LASTEXITCODE -ne 0) { throw "Failed to stage deployment source" }
  & tar -C $Stage -xf $SourceArchive
  if ($LASTEXITCODE -ne 0) { throw "Failed to extract deployment source" }
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "new-deployment-provenance.ps1") -StageRoot $Stage -SourceRoot $Repo
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $Stage "DEPLOYMENT-CONTENT-SHA256SUMS") -PathType Leaf)) {
    throw "Failed to generate deployment provenance"
  }
  & tar -C $Stage -czf $Archive .
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Archive -PathType Leaf)) {
    throw "Failed to create deployment archive"
  }

  $Payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($Archive))
  $Payload | ssh @SshArgs $Remote
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }

  if ($RuntimeRequested) {
    & tar -C $BundleDir -czf $BundleArchive .
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $BundleArchive -PathType Leaf)) {
      throw "Failed to create temporary runtime bundle archive"
    }

    $RuntimeTemplate = @'
set -eu
remote_dir="__REMOTE_DIR__"
runtime_stage="/tmp/home-edge-runtime-bundle.$$"

cleanup_runtime_stage() {
  case "$runtime_stage" in /tmp/home-edge-runtime-bundle.*) rm -rf "$runtime_stage" 2>/dev/null || true ;; esac
}
handle_runtime_signal() {
  cleanup_runtime_stage
  trap - EXIT
  exit 130
}
trap cleanup_runtime_stage EXIT
trap handle_runtime_signal HUP INT TERM

decode_payload() {
  if which base64 >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | base64 -d
  elif which openssl >/dev/null 2>&1; then
    tr -cd 'A-Za-z0-9+/=' | openssl base64 -d -A
  else
    echo "deploy-merlin: base64 or openssl is required to decode runtime payload" >&2
    return 1
  fi
}

[ ! -L "$runtime_stage" ] || { echo "deploy-merlin: refusing symbolic-link runtime stage" >&2; exit 1; }
mkdir -m 700 "$runtime_stage"
decode_payload | tar -xzf - -C "$runtime_stage"
[ -s "$runtime_stage/mihomo-linux-arm64" ] || { echo "deploy-merlin: temporary runtime bundle is missing Mihomo" >&2; exit 1; }
[ -s "$runtime_stage/ShellCrash.tar.gz" ] || { echo "deploy-merlin: temporary runtime bundle is missing ShellCrash" >&2; exit 1; }
[ -s "$runtime_stage/SHA256SUMS" ] || { echo "deploy-merlin: temporary runtime bundle is missing SHA256SUMS" >&2; exit 1; }
(cd "$remote_dir" && \
  BOOTSTRAP_APPLY=1 \
  BOOTSTRAP_INSTALL_RUNTIME=1 \
  BOOTSTRAP_BUNDLE_HOST_VERIFIED=1 \
  BOOTSTRAP_REPLACE_RUNTIME=__REPLACE_RUNTIME__ \
  BOOTSTRAP_REPLACE_CORE=__REPLACE_CORE__ \
  BOOTSTRAP_BUNDLE_DIR="$runtime_stage" \
  sh bootstrap.sh)
echo "runtime_deploy_state=applied"
'@
    $RuntimeRemote = $RuntimeTemplate.Replace("__REMOTE_DIR__", $RemoteDir).
      Replace("__REPLACE_RUNTIME__", [int]$ReplaceRequested).
      Replace("__REPLACE_CORE__", [int]$ReplaceCoreRequested)
    $RuntimeRollbackTemplate = @'
set -eu
remote_dir="__REMOTE_DIR__"
previous="${remote_dir}.prev"
failed="${remote_dir}.runtime-failed.$$"
lock_dir="/tmp/home-edge-bootstrap-write.lock"
lock_held=0

cleanup_rollback() {
  if [ "$lock_held" = "1" ]; then
    rm -f "$lock_dir/started_at" "$lock_dir/pid" "$lock_dir/operation" 2>/dev/null || true
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}
handle_rollback_signal() {
  cleanup_rollback
  trap - EXIT
  exit 130
}
trap cleanup_rollback EXIT
trap handle_rollback_signal HUP INT TERM

cleanup_first_install_active_state() {
  cru d home_edge_selfheal >/dev/null 2>&1 || true
  services_start=/jffs/scripts/services-start
  if [ -f "$services_start" ] && [ ! -L "$services_start" ]; then
    services_tmp="${services_start}.runtime-rollback.$$"
    if awk '
      $0 == "# BEGIN home-edge-bootstrap self-heal lifecycle" { managed=1; next }
      $0 == "# END home-edge-bootstrap self-heal lifecycle" && managed { managed=0; next }
      !managed { print }
    ' "$services_start" >"$services_tmp"; then
      chmod 700 "$services_tmp" 2>/dev/null || true
      mv "$services_tmp" "$services_start" || rm -f "$services_tmp"
    else
      rm -f "$services_tmp"
    fi
  fi
  for active_file in \
    home-edge-policy.env \
    home-edge-policy.local \
    home-edge-self-heal.sh \
    home-edge-update-sub.sh \
    home-edge-subscription-runtime-evidence.sh \
    home-edge-verify-bundle.sh \
    home-edge-reconcile-self-heal.sh \
    home-edge-self-heal-cron.sh \
    home-edge-secure-temp.sh \
    home-edge-configure-dns.sh \
    home-edge-prefetch-shellcrash-data.sh \
    home-edge-start-shellcrash.sh \
    home-edge-configure-service-rules.sh
  do
    rm -f "/jffs/scripts/$active_file" 2>/dev/null || true
  done
}

for protected_path in "$remote_dir" "$previous" "$failed"; do
  [ ! -L "$protected_path" ] || {
    echo "deploy-merlin: refusing symbolic-link rollback path: $protected_path" >&2
    exit 1
  }
done
mkdir "$lock_dir" 2>/dev/null || {
  echo "deploy-merlin: cannot acquire runtime rollback lock" >&2
  exit 1
}
lock_held=1
date +%s >"$lock_dir/started_at"
printf "%s\n" "$$" >"$lock_dir/pid"
printf "%s\n" runtime-rollback >"$lock_dir/operation"

[ ! -d "$failed" ] || rm -rf "$failed"
[ ! -d "$remote_dir" ] || mv "$remote_dir" "$failed"
if [ -d "$previous" ]; then
  mv "$previous" "$remote_dir"
  if [ -f "$remote_dir/bootstrap.sh" ]; then
    HOME_EDGE_WRITE_LOCK_HELD=1 BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "$remote_dir/bootstrap.sh" >/dev/null 2>&1 || {
      echo "deploy-merlin: restored control-plane bootstrap replay failed" >&2
      exit 1
    }
  fi
  rm -rf "$failed"
  echo "control_plane_rollback_state=restored"
else
  cleanup_first_install_active_state
  rm -rf "$failed"
  echo "control_plane_rollback_state=removed"
fi
'@
    $RuntimeRollbackRemote = $RuntimeRollbackTemplate.Replace("__REMOTE_DIR__", $RemoteDir)
    $RuntimePayload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($BundleArchive))
    $RuntimePayload | ssh @SshArgs $RuntimeRemote
    if ($LASTEXITCODE -ne 0) {
      $RuntimeExitCode = $LASTEXITCODE
      Write-Warning "Runtime stage failed; restoring the prior staged control plane."
      & ssh @SshArgs $RuntimeRollbackRemote
      if ($LASTEXITCODE -ne 0) {
        throw "Runtime stage failed and control-plane rollback could not be verified."
      }
      exit $RuntimeExitCode
    }
  }
}
finally {
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $BundleArchive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $SourceArchive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
}
