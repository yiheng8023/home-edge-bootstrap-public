param(
  [Parameter(Mandatory=$true)][string]$Router,
  [switch]$Apply,
  [switch]$ToolsOnly,
  [string]$PrebuiltBinary = $env:SERVICE_HEALTH_PREBUILT,
  [string]$ExpectedSha256 = $env:SERVICE_HEALTH_PREBUILT_SHA256,
  [string[]]$SshOptions
)
$ErrorActionPreference='Stop'
if ($Router -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]*@([A-Za-z0-9][A-Za-z0-9_.:-]*|\[[0-9A-Fa-f:]+\])$') { throw 'Router must be exact USER@ROUTER, without shell syntax.' }
$Repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $SshOptions) {
  $SshOptions=if ($env:SSH_OPTS) { @($env:SSH_OPTS -split '\s+' | Where-Object {$_}) } else { @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=yes') }
  $KnownHosts = if ($env:KNOWN_HOSTS_FILE) { $env:KNOWN_HOSTS_FILE } else { Join-Path $HOME ".ssh/known_hosts" }
  $SshOptions += @('-o', "UserKnownHostsFile=$KnownHosts")
}
foreach ($Tool in @('ssh','scp')) { if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {throw "Missing host tool: $Tool"} }
$Source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'enable-service-health.sh'))
function Section([string]$Name) {
  $Match=[regex]::Match($Source,"(?ms)^# BEGIN SERVICE_HEALTH_$Name\r?`n(.*?)^# END SERVICE_HEALTH_$Name")
  if (-not $Match.Success) {throw 'Missing shared remote adapter section'}
  return $Match.Groups[1].Value.Replace("`r",'')
}
$LocalStage=Join-Path ([IO.Path]::GetTempPath()) ('home-edge-service-host.'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($LocalStage)
if ([Environment]::OSVersion.Platform -ne 'Win32NT') { & chmod 700 $LocalStage; if ($LASTEXITCODE -ne 0) {throw 'Cannot secure host stage'} }
$StageId=[guid]::NewGuid().ToString('N')
$Stage="/tmp/home-edge-service-enable.$StageId"
$RemoteOwned=$false
$RemoteActive=$false
try {
  $ArchOutput=@(& ssh @SshOptions -- $Router 'set -eu; for f in /jffs/scripts/home-edge-configure-service-health.sh /jffs/scripts/home-edge-service-health.sh /jffs/scripts/home-edge-service-health-preflight.sh; do [ -f "$f" ] && [ ! -L "$f" ] || { echo "service_health_enable=deploy_project_helpers_first" >&2; exit 1; }; done; uname -m')
  if ($LASTEXITCODE -ne 0) {throw 'Deploy current project helpers first; router capability check failed'}
  $Arch=($ArchOutput -join "`n").Trim()
  switch -Regex ($Arch) { '^(aarch64|arm64)$' {$Arch='arm64';break} '^(x86_64|amd64)$' {$Arch='amd64';break} default {throw 'Unsupported router architecture'} }
  $Binary=Join-Path $LocalStage 'yamlbridge'
  if ($PrebuiltBinary) {
    $Item=Get-Item -LiteralPath $PrebuiltBinary
    if ($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {throw 'A regular prebuilt binary and expected SHA256 are required'}
    if ((Get-FileHash -LiteralPath $Item.FullName -Algorithm SHA256).Hash -ne $ExpectedSha256) {throw 'Prebuilt SHA256 mismatch'}
    [IO.File]::Copy($Item.FullName,$Binary)
  } else {
    if (-not (Get-Command go -CommandType Application -ErrorAction SilentlyContinue)) {throw 'Go is missing. Provide Go on the host, or -PrebuiltBinary plus -ExpectedSha256. No compiler is installed automatically.'}
    $EnvKeys=@('GOTOOLCHAIN','CGO_ENABLED','GOOS','GOARCH');$Saved=@{}
    foreach ($Key in $EnvKeys) {$Saved[$Key]=[Environment]::GetEnvironmentVariable($Key,'Process')}
    Push-Location (Join-Path $Repo 'tools/yamlbridge')
    try {
      $env:GOTOOLCHAIN='local'
      $env:GOOS=$null;$env:GOARCH=$null
      & go mod verify; if ($LASTEXITCODE -ne 0) {throw 'Go module verification failed'}
      & go test ./...; if ($LASTEXITCODE -ne 0) {throw 'Go tests failed'}
      $env:CGO_ENABLED='0';$env:GOOS='linux';$env:GOARCH=$Arch
      & go build -buildvcs=false -trimpath '-ldflags=-s -w -buildid=' -o $Binary .
      if ($LASTEXITCODE -ne 0) {throw 'Static Linux helper build failed'}
    } finally { Pop-Location; foreach ($Key in $EnvKeys) {[Environment]::SetEnvironmentVariable($Key,$Saved[$Key],'Process')} }
  }
  $Digest=(Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash.ToLowerInvariant()
  $Archive=Join-Path $LocalStage 'yamlbridge.gz'
  $Output=[IO.File]::Create($Archive)
  try {$Zip=[IO.Compression.GZipStream]::new($Output,[IO.Compression.CompressionMode]::Compress,$true);try {$Input=[IO.File]::OpenRead($Binary);try {$Input.CopyTo($Zip)} finally {$Input.Dispose()}} finally {$Zip.Dispose()}} finally {$Output.Dispose()}
  $DigestFile=Join-Path $LocalStage 'yamlbridge.sha256'
  [IO.File]::WriteAllText($DigestFile,$Digest+"`n",[Text.UTF8Encoding]::new($false))
  & ssh @SshOptions -- $Router "set -eu; umask 077; [ ! -e '$Stage' ] && [ ! -L '$Stage' ]; mkdir '$Stage'; printf '%s\n' '$StageId' >'$Stage/owner'"
  if ($LASTEXITCODE -ne 0) {throw 'Cannot allocate private remote stage'}
  $RemoteOwned=$true
  & scp -O @SshOptions -- $Archive "${Router}:$Stage/yamlbridge.gz";if ($LASTEXITCODE -ne 0) {throw 'Helper transfer failed'}
  & scp -O @SshOptions -- $DigestFile "${Router}:$Stage/yamlbridge.sha256";if ($LASTEXITCODE -ne 0) {throw 'Digest transfer failed'}
  $ApplyValue=if ($Apply) {'1'} else {'0'}
  $ToolsOnlyValue=if($ToolsOnly){'1'}else{'0'}
  $Payload="stage='$Stage'`nstage_id='$StageId'`napply='$ApplyValue'`ntools_only='$ToolsOnlyValue'`n"+(Section 'REMOTE')
  $RemoteActive=$true
  $Payload | & ssh @SshOptions -- $Router 'tr -d "\r" | sh -s'
  if ($LASTEXITCODE -ne 0) {throw 'Service-health installation stopped; inspect the reported boundary and retained recovery receipt'}
  $RemoteActive=$false
} finally {
  if ($RemoteOwned -and -not $RemoteActive) {
    try { $Cleanup="stage='$Stage'; stage_id='$StageId'; "+(Section 'CLEANUP'); & ssh @SshOptions -- $Router $Cleanup | Out-Null; if ($LASTEXITCODE -ne 0) {Write-Warning 'Remote stage cleanup was not confirmed.'} } catch {Write-Warning 'Remote stage cleanup was not confirmed; its owner token remains in the private stage.'}
  }
  if ($RemoteActive) {Write-Warning 'Remote outcome is unknown; the private remote stage was retained for inspection.'}
  foreach ($File in @('yamlbridge','yamlbridge.gz','yamlbridge.sha256')) { $Path=Join-Path $LocalStage $File; if (Test-Path -LiteralPath $Path) {Remove-Item -LiteralPath $Path -Force} }
  if (Test-Path -LiteralPath $LocalStage) {Remove-Item -LiteralPath $LocalStage}
}
