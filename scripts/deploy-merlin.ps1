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
$BundleDir = Join-Path $Repo "bundle"
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

if ($RuntimeRequested) {
  Assert-LocalBundle
}

$IncludeBundleResolved = ($IncludeBundle -or $RuntimeRequested)
if (-not $Apply) {
  Write-Host "deploy_state=plan"
  Write-Host "apply_required=1"
  Write-Host "router=$Router"
  Write-Host "remote_dir=$RemoteDir"
  Write-Host "include_bundle=$([int]$IncludeBundleResolved)"
  Write-Host "install_runtime=$([int]$RuntimeRequested)"
  Write-Host "replace_runtime=$([int]$ReplaceRequested)"
  Write-Host "replace_core=$([int]$ReplaceCoreRequested)"
  Write-Host "next_action=rerun with -Apply after reviewing this plan"
  exit 0
}

$ModeParts = @("BOOTSTRAP_APPLY=1")
if ($RuntimeRequested) {
  $ModeParts += "BOOTSTRAP_INSTALL_RUNTIME=1"
  $ModeParts += "BOOTSTRAP_BUNDLE_HOST_VERIFIED=1"
}
if ($ReplaceRequested) {
  $ModeParts += "BOOTSTRAP_REPLACE_RUNTIME=1"
}
if ($ReplaceCoreRequested) {
  $ModeParts += "BOOTSTRAP_REPLACE_CORE=1"
}
$Mode = $ModeParts -join " "

$RemoteTemplate = @'
set -eu
remote_dir="__REMOTE_DIR__"
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

rollback_deploy() {
  restored=0
  [ -d "$remote_dir" ] && mv "$remote_dir" "$failed_dir"
  if [ -d "$previous" ]; then
    mv "$previous" "$remote_dir"
    restored=1
  fi
  if [ -f "$remote_dir/bootstrap.sh" ]; then
    if ! BOOTSTRAP_APPLY=1 BOOTSTRAP_INSTALL_RUNTIME=0 sh "$remote_dir/bootstrap.sh" >/dev/null 2>&1; then
      echo "deploy-merlin: WARN previous kit was restored but its bootstrap replay failed" >&2
    fi
  fi
  [ "$restored" = "1" ] && rm -rf "$failed_dir"
}

acquire_deploy_lock
rm -rf "$staging"
mkdir -p "$staging"
base64 -d | tar -xzf - -C "$staging"
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
if ! (cd "$remote_dir" && HOME_EDGE_WRITE_LOCK_HELD=1 __MODE__ sh bootstrap.sh); then
  rollback_deploy
  echo "deploy-merlin: bootstrap failed; previous kit restored" >&2
  exit 1
fi
echo "deploy_state=applied"
echo "rollback_available=$([ -d "$previous" ] && echo 1 || echo 0)"
'@

$Remote = $RemoteTemplate.Replace("__REMOTE_DIR__", $RemoteDir).Replace("__MODE__", $Mode)
$ArchiveItems = @("README.md", "README.zh-CN.md", "bootstrap.sh", "adapters", "config", "docs", "scripts")
if ($IncludeBundleResolved) {
  $ArchiveItems += "bundle"
}

$Archive = Join-Path $env:TEMP ("home-edge-bootstrap-" + [System.Guid]::NewGuid().ToString("N") + ".tgz")
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
}
finally {
  Remove-Item -LiteralPath $Archive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $SourceArchive -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
}
