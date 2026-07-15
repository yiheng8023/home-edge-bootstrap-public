$ErrorActionPreference = "Stop"
$Output = ""; $PayloadDir = ""; $Lock = ""; $Manifest = ""; $MihomoUrl = ""; $ShellCrashUrl = ""
$GoCommand = ""; $GoWorkRoot = ""; $GoArchive = ""; $GoProxy = "https://proxy.golang.org"
$FixtureOs = ""; $FixtureArch = ""; $AllowDirectGoFallback = $false; $FixtureMode = $false; $MaxModules = 2000
for ($Index = 0; $Index -lt $args.Count; $Index++) {
  $Option = [string]$args[$Index]
  if ($Option -in @("--allow-direct-go-fallback", "-AllowDirectGoFallback")) { $AllowDirectGoFallback = $true; continue }
  if ($Option -in @("--fixture-mode", "-FixtureMode")) { $FixtureMode = $true; continue }
  if ($Index + 1 -ge $args.Count) { throw "missing value for argument: $Option" }
  $Value = [string]$args[++$Index]
  switch -CaseSensitive ($Option) {
    { $_ -in @("--output", "-Output") } { $Output = $Value; break }
    { $_ -in @("--payload-dir", "-PayloadDir") } { $PayloadDir = $Value; break }
    { $_ -in @("--lock", "-Lock") } { $Lock = $Value; break }
    { $_ -in @("--manifest", "-Manifest") } { $Manifest = $Value; break }
    { $_ -in @("--mihomo-url", "-MihomoUrl") } { $MihomoUrl = $Value; break }
    { $_ -in @("--shellcrash-url", "-ShellCrashUrl") } { $ShellCrashUrl = $Value; break }
    { $_ -in @("--go-command", "-GoCommand") } { $GoCommand = $Value; break }
    { $_ -in @("--go-work-root", "-GoWorkRoot") } { $GoWorkRoot = $Value; break }
    { $_ -in @("--go-archive", "-GoArchive") } { $GoArchive = $Value; break }
    { $_ -in @("--go-proxy", "-GoProxy") } { $GoProxy = $Value; break }
    { $_ -in @("--fixture-os", "-FixtureOs") } { $FixtureOs = $Value.ToLowerInvariant(); break }
    { $_ -in @("--fixture-arch", "-FixtureArch") } { $FixtureArch = $Value.ToLowerInvariant(); break }
    { $_ -in @("--max-modules", "-MaxModules") } {
      $Parsed = 0
      if (-not [int]::TryParse($Value, [ref]$Parsed) -or $Parsed -lt 1 -or $Parsed -gt 5000) { throw "invalid module limit" }
      $MaxModules = $Parsed
      break
    }
    default { throw "unknown argument: $Option" }
  }
}
if (-not $Output -or -not $PayloadDir) { throw "required: --output and --payload-dir" }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
if (-not $Lock) { $Lock = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path "config\third-party-lock.json" }

function Get-Python3 {
  foreach ($Name in @("python3", "python")) {
    $Command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $Command) { continue }
    & $Command.Source -c 'import sys; raise SystemExit(0 if sys.version_info[0] == 3 else 1)'
    if ($LASTEXITCODE -eq 0) { return [string]$Command.Source }
  }
  throw "Python 3 is required"
}

function Invoke-Checked([string]$Program, [string[]]$Arguments, [string]$Failure) {
  & $Program @Arguments
  if ($LASTEXITCODE -ne 0) { throw "$Failure (exit $LASTEXITCODE)" }
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-SourceLocator([string]$Locator, [bool]$IsFixture) {
  if ($IsFixture) {
    if (-not (Test-Path -LiteralPath $Locator -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $Locator ".git") -PathType Container)) { throw "fixture source must be a local Git repository" }
    return
  }
  if ($Locator -notmatch '^https://') { throw "production source URL must use credential-free HTTPS" }
  $Uri = [uri]$Locator
  if ($Uri.UserInfo -or $Uri.Query -or $Uri.Fragment) { throw "credential-bearing or decorated source URL is forbidden" }
}

function Get-ToolchainPlatform([bool]$IsFixture, [string]$RequestedOs, [string]$RequestedArch) {
  if ($IsFixture) {
    if (-not $RequestedOs -or -not $RequestedArch) { throw "fixture platform requires --fixture-os and --fixture-arch" }
    return [pscustomobject]@{ Os = $RequestedOs; Arch = $RequestedArch }
  }
  if ($RequestedOs -or $RequestedArch) { throw "platform override is forbidden outside fixture mode" }
  $Runtime = [System.Runtime.InteropServices.RuntimeInformation]
  if ($Runtime::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) { $DetectedOs = "windows" }
  elseif ($Runtime::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Linux)) { $DetectedOs = "linux" }
  elseif ($Runtime::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::OSX)) { $DetectedOs = "darwin" }
  else { throw "unsupported source-preparation operating system" }
  $Architecture = $Runtime::OSArchitecture.ToString().ToLowerInvariant()
  if ($Architecture -eq "x64") { $DetectedArch = "amd64" }
  elseif ($Architecture -eq "arm64") { $DetectedArch = "arm64" }
  else { throw "unsupported source-preparation architecture: $Architecture" }
  return [pscustomobject]@{ Os = $DetectedOs; Arch = $DetectedArch }
}

function Copy-TrackedTree([string]$Python, [string]$Repository, [string]$Destination) {
  $Code = @'
import pathlib, subprocess, sys
repo,dest=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]); dest.mkdir(parents=True)
records=subprocess.check_output(['git','-C',str(repo),'ls-files','--stage','-z']).split(b'\0'); count=0
for raw in records:
    if not raw: continue
    head,path=raw.split(b'\t',1); mode=head.split(b' ',1)[0]
    if mode not in (b'100644',b'100755'): raise SystemExit(f'unsupported tracked source mode: {mode.decode()}: {path.decode()}')
    rel=path.decode('utf-8'); target=dest/pathlib.PurePosixPath(rel); target.parent.mkdir(parents=True,exist_ok=True)
    target.write_bytes(subprocess.check_output(['git','-C',str(repo),'show','HEAD:'+rel])); count+=1
if not count: raise SystemExit('upstream tree has no tracked files')
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    & $Python $Driver $Repository $Destination
    if ($LASTEXITCODE -ne 0) { throw "tracked Git blob export failed" }
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
}

function Resolve-GoCommand {
  if ($GoCommand) {
    $Resolved = Get-Command $GoCommand -ErrorAction SilentlyContinue
    if ($null -ne $Resolved) { return [string]$Resolved.Source }
    if (Test-Path -LiteralPath $GoCommand -PathType Leaf) { return [System.IO.Path]::GetFullPath($GoCommand) }
    throw "configured Go command does not exist: $GoCommand"
  }
  $Resolved = Get-Command go -ErrorAction SilentlyContinue
  if ($null -eq $Resolved) { throw "Go toolchain is required for Mihomo complete corresponding source" }
  return [string]$Resolved.Source
}

function Expand-GoToolchain([string]$Python, [string]$Archive, [string]$Destination) {
  $Code = @'
import os,pathlib,shutil,stat,sys,tarfile,zipfile
archive,dest=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]); dest.mkdir(parents=True)
def target(name):
    name=name.replace('\\','/'); parts=pathlib.PurePosixPath(name).parts
    if not name or name.startswith('/') or any(x in ('','.','..') for x in parts) or (parts and ':' in parts[0]): raise SystemExit('unsafe Go toolchain archive path')
    return dest.joinpath(*parts)
if zipfile.is_zipfile(archive):
    with zipfile.ZipFile(archive) as z:
        for m in z.infolist():
            out=target(m.filename)
            if m.is_dir(): out.mkdir(parents=True,exist_ok=True); continue
            mode=(m.external_attr>>16)&0xffff
            if stat.S_ISLNK(mode): raise SystemExit('unsafe Go toolchain archive entry')
            out.parent.mkdir(parents=True,exist_ok=True)
            with z.open(m) as src, out.open('wb') as dst: shutil.copyfileobj(src,dst)
            if mode: os.chmod(out,mode&0o777)
elif tarfile.is_tarfile(archive):
    with tarfile.open(archive,'r:*') as t:
        for m in t.getmembers():
            out=target(m.name)
            if m.issym() or m.islnk() or m.isdev(): raise SystemExit('unsafe Go toolchain archive entry')
            if m.isdir(): out.mkdir(parents=True,exist_ok=True); continue
            if not m.isfile(): raise SystemExit('unsupported Go toolchain archive entry')
            out.parent.mkdir(parents=True,exist_ok=True)
            with t.extractfile(m) as src, out.open('wb') as dst: shutil.copyfileobj(src,dst)
            os.chmod(out,m.mode&0o777)
else: raise SystemExit('unsupported Go toolchain archive')
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    & $Python $Driver $Archive $Destination
    if ($LASTEXITCODE -ne 0) { throw "Go toolchain archive extraction failed" }
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
  foreach ($Candidate in @("go\bin\go.exe", "go\bin\go.cmd", "go\bin\go.bat", "go\bin\go")) {
    $Path = Join-Path $Destination $Candidate
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return [System.IO.Path]::GetFullPath($Path) }
  }
  throw "verified Go toolchain archive does not contain go/bin/go"
}

function Assert-SafeArchive([string]$Python, [string]$Archive) {
  $Code = @'
import pathlib, sys, tarfile, zipfile
p = pathlib.Path(sys.argv[1])
def safe(name):
    name = name.replace("\\", "/")
    parts = pathlib.PurePosixPath(name).parts
    return bool(name) and not name.startswith("/") and not any(x in ("", ".", "..") for x in parts) and not (len(parts) and ":" in parts[0])
if tarfile.is_tarfile(p):
    with tarfile.open(p, "r:*") as a:
        for m in a.getmembers():
            if not safe(m.name) or m.issym() or m.islnk() or m.isdev(): raise SystemExit("unsafe archive path or entry")
elif zipfile.is_zipfile(p):
    with zipfile.ZipFile(p) as a:
        for m in a.infolist():
            if not safe(m.filename): raise SystemExit("unsafe archive path")
else:
    raise SystemExit("unsupported archive")
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    & $Python $Driver $Archive
    if ($LASTEXITCODE -ne 0) { throw "unsafe or invalid archive: $Archive" }
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
}

function New-CanonicalArchive([string]$Go, [string]$Helper, [string]$Source, [string]$Archive, [string]$Prefix, [long]$Epoch, [string]$GoRoot) {
  $Names = @("GOMODCACHE", "GOCACHE", "GOPATH", "GOENV", "GOTOOLCHAIN", "GOFLAGS", "GOPROXY", "GOSUMDB", "GOPRIVATE", "GONOPROXY", "GONOSUMDB")
  $Prior = @{}
  foreach ($Name in $Names) { $Prior[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
  try {
    $env:GOMODCACHE = Join-Path $GoRoot "modcache"
    $env:GOCACHE = Join-Path $GoRoot "buildcache"
    $env:GOPATH = Join-Path $GoRoot "gopath"
    $env:GOENV = "off"
    $env:GOTOOLCHAIN = "local"
    $env:GOFLAGS = "-modcacherw"
    $env:GOPROXY = "off"
    $env:GOSUMDB = "off"
    $env:GOPRIVATE = ""
    $env:GONOPROXY = ""
    $env:GONOSUMDB = ""
    & $Go run $Helper $Source $Archive $Prefix ([string]$Epoch)
    if ($LASTEXITCODE -ne 0) { throw "canonical source archive creation failed" }
  }
  finally { foreach ($Name in $Names) { [Environment]::SetEnvironmentVariable($Name, $Prior[$Name], "Process") } }
  if (-not (Test-Path -LiteralPath $Archive -PathType Leaf)) { throw "canonical source archive was not created: $Archive" }
}

function Convert-GoDownloadLog([string]$Python, [string]$InputPath, [string]$OutputPath, [int]$Limit) {
  $Code = @'
import json, pathlib, sys
source,target,limit=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),int(sys.argv[3])
text=source.read_text(encoding="utf-8-sig"); decoder=json.JSONDecoder(); pos=0; modules=[]
while pos < len(text):
    while pos < len(text) and text[pos].isspace(): pos += 1
    if pos >= len(text): break
    item,pos=decoder.raw_decode(text,pos)
    if item.get("Error"): raise SystemExit(f"Go module download error: {item.get('Path','unknown')}: {item['Error']}")
    if item.get("Path") and item.get("Version"):
        modules.append({k:item[k] for k in ("Path","Version","Sum","GoModSum") if item.get(k)})
if not modules: raise SystemExit("Go module download returned zero modules")
if len(modules) > limit: raise SystemExit(f"Go module count exceeds limit: {len(modules)} > {limit}")
modules.sort(key=lambda x:(x["Path"],x["Version"]))
target.write_text(json.dumps({"schema_version":1,"module_count":len(modules),"modules":modules},indent=2)+"\n",encoding="utf-8",newline="\n")
print(len(modules))
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    $Count = (& $Python $Driver $InputPath $OutputPath $Limit).Trim()
    if ($LASTEXITCODE -ne 0 -or $Count -notmatch '^[0-9]+$') { throw "Go module download log validation failed" }
    return [int]$Count
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
}

function Write-VendorManifest([string]$Python, [string]$DownloadManifest, [string]$VendorRoot, [string]$OutputPath) {
  $Code = @'
import json,pathlib,sys
download_path,vendor,target=map(pathlib.Path,sys.argv[1:4])
download=json.loads(download_path.read_text(encoding='utf-8'))
known={(m['Path'],m['Version']) for m in download['modules']}
lines=(vendor/'modules.txt').read_text(encoding='utf-8').splitlines(); modules=[]; current=None
for line in lines:
    if line.startswith('# ') and not line.startswith('## '):
        parts=line[2:].split()
        if len(parts)<2 or not parts[1].startswith('v'): current=None; continue
        current={'Path':parts[0],'Version':parts[1],'Packages':[]}
        if '=>' in parts:
            i=parts.index('=>')
            if len(parts)<=i+2: raise SystemExit('invalid vendor replacement identity')
            current.update({'ReplacementPath':parts[i+1],'ReplacementVersion':parts[i+2]})
            identity=(parts[i+1],parts[i+2])
        else: identity=(parts[0],parts[1])
        if identity not in known: raise SystemExit(f'vendored module absent from verified download log: {identity[0]} {identity[1]}')
        modules.append(current); continue
    if current is not None and line and not line.startswith('#'):
        package=line.strip(); package_dir=vendor/pathlib.PurePosixPath(package)
        if not package_dir.is_dir() or not any(p.is_file() for p in package_dir.rglob('*')): raise SystemExit(f'vendored package source missing: {package}')
        current['Packages'].append(package)
if not modules or not any(m['Packages'] for m in modules): raise SystemExit('Mihomo vendored module source is incomplete')
target.write_text(json.dumps({'schema_version':1,'module_count':len(modules),'package_count':sum(len(m['Packages']) for m in modules),'modules':modules},indent=2)+'\n',encoding='utf-8',newline='\n')
print(len(modules))
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    $Count = (& $Python $Driver $DownloadManifest $VendorRoot $OutputPath).Trim()
    if ($LASTEXITCODE -ne 0 -or $Count -notmatch '^[0-9]+$') { throw "Mihomo vendor manifest reconciliation failed" }
    return [int]$Count
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
}

function Write-SourceMetadata([string]$Python, [string]$Path, [string]$ComponentId, [string]$Version, [string]$Repository, [string]$Commit, [long]$Epoch, [string]$Workflow, [string]$GoVersion = "", [string]$Proxy = "", [int]$ModuleCount = 0) {
  $Code = @'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); data={'schema_version':1,'component_id':sys.argv[2],'version':sys.argv[3],'source_repository':sys.argv[4],'source_commit':sys.argv[5],'source_commit_epoch':int(sys.argv[6]),'build_workflow':sys.argv[7]}
if sys.argv[8] != '__NONE__':
    data.update({'go_version':sys.argv[8]})
    data.update({'go_proxy':sys.argv[9],'go_sumdb':'sum.golang.org','go_private':'','go_max_procs':4,'module_count':int(sys.argv[10])})
path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8',newline='\n')
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    $GoArg = $GoVersion; if (-not $GoArg) { $GoArg = "__NONE__" }
    $ProxyArg = $Proxy; if (-not $ProxyArg) { $ProxyArg = "__NONE__" }
    & $Python $Driver $Path $ComponentId $Version $Repository $Commit $Epoch $Workflow $GoArg $ProxyArg $ModuleCount
    if ($LASTEXITCODE -ne 0) { throw "source metadata generation failed: $ComponentId" }
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
}

function Write-PreparationMetadata([string]$Python, [string]$Path, [string]$ComponentId, [string]$Version, [string]$Repository, [string]$Commit, [string]$GoVersion, [string]$HostOs, [string]$HostArch, [string]$ToolchainArchive, [string]$ToolchainSha, [string]$SourceArchive, [string]$SourceSha) {
  $Code = @'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); data={'schema_version':1,'component_id':sys.argv[2],'component_version':sys.argv[3],'source_repository':sys.argv[4],'source_commit':sys.argv[5],'go_version':sys.argv[6],'host_os':sys.argv[7],'host_arch':sys.argv[8],'go_toolchain_archive':sys.argv[9],'go_toolchain_archive_sha256':sys.argv[10],'complete_source_archive':sys.argv[11],'complete_source_sha256':sys.argv[12]}
path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8',newline='\n')
'@
  $Driver = [System.IO.Path]::GetTempFileName() + ".py"
  try {
    [System.IO.File]::WriteAllText($Driver, $Code, $Utf8NoBom)
    & $Python $Driver $Path $ComponentId $Version $Repository $Commit $GoVersion $HostOs $HostArch $ToolchainArchive $ToolchainSha $SourceArchive $SourceSha
    if ($LASTEXITCODE -ne 0) { throw "source preparation metadata generation failed: $ComponentId" }
  }
  finally { Remove-Item -LiteralPath $Driver -Force -ErrorAction SilentlyContinue }
}

$LockPath = [System.IO.Path]::GetFullPath($Lock)
$PayloadRoot = [System.IO.Path]::GetFullPath($PayloadDir)
$OutputPath = [System.IO.Path]::GetFullPath($Output)
$ManifestPath = if ($Manifest) { [System.IO.Path]::GetFullPath($Manifest) } else { Join-Path $PayloadRoot "MANIFEST.json" }
if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf)) { throw "third-party lock not found: $LockPath" }
if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) { throw "payload directory not found: $PayloadRoot" }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "payload manifest not found: $ManifestPath" }
if (Test-Path -LiteralPath $OutputPath) { throw "output already exists: $OutputPath" }

$LockData = Get-Content -Raw -LiteralPath $LockPath | ConvertFrom-Json
$Components = @($LockData.components)
if ($LockData.schema_version -ne 1 -or $Components.Count -ne 2) { throw "invalid third-party lock structure" }
$Mihomo = @($Components | Where-Object { $_.id -ceq "mihomo-linux-arm64" })
$ShellCrash = @($Components | Where-Object { $_.id -ceq "shellcrash" })
if ($Mihomo.Count -ne 1 -or $ShellCrash.Count -ne 1) { throw "required component lock missing or duplicated" }
$Mihomo = $Mihomo[0]
$ShellCrash = $ShellCrash[0]
$SourceAcquisition = $LockData.source_acquisition
if ($null -ne $SourceAcquisition) {
  $SupportedPlatforms = @("windows/amd64", "windows/arm64", "linux/amd64", "linux/arm64", "darwin/amd64", "darwin/arm64")
  $Toolchains = @($SourceAcquisition.go_toolchains)
  $ToolchainKeys = @($Toolchains | ForEach-Object { "$($_.os)/$($_.arch)" })
  if ($Toolchains.Count -ne 6 -or @($ToolchainKeys | Sort-Object -Unique).Count -ne 6 -or @(Compare-Object ($SupportedPlatforms | Sort-Object) ($ToolchainKeys | Sort-Object)).Count -ne 0) { throw "Go toolchain platform lock is incomplete or duplicated" }
  foreach ($Toolchain in $Toolchains) {
    $Extension = if ([string]$Toolchain.os -ceq "windows") { "zip" } else { "tar.gz" }
    $ExpectedFilename = "$($SourceAcquisition.go_toolchain_version).$($Toolchain.os)-$($Toolchain.arch).$Extension"
    if ([string]$Toolchain.filename -cne $ExpectedFilename -or [string]$Toolchain.sha256 -notmatch '^[0-9a-f]{64}$') { throw "invalid Go toolchain platform lock: $($Toolchain.os)/$($Toolchain.arch)" }
  }
  $Platform = Get-ToolchainPlatform ([bool]$FixtureMode) $FixtureOs $FixtureArch
  $Selected = @($Toolchains | Where-Object { [string]$_.os -ceq [string]$Platform.Os -and [string]$_.arch -ceq [string]$Platform.Arch })
  if ($Selected.Count -ne 1) { throw "unsupported source-preparation platform: $($Platform.Os)/$($Platform.Arch)" }
  $SelectedToolchain = $Selected[0]
  if (-not $GoArchive -or -not (Test-Path -LiteralPath $GoArchive -PathType Leaf)) { throw "locked Go toolchain archive is required" }
  if ([System.IO.Path]::GetFileName($GoArchive) -cne [string]$SelectedToolchain.filename) { throw "Go toolchain archive filename mismatch for $($Platform.Os)/$($Platform.Arch)" }
  if ((Get-Sha256 ([System.IO.Path]::GetFullPath($GoArchive))) -cne [string]$SelectedToolchain.sha256) { throw "Go toolchain archive hash mismatch for $($Platform.Os)/$($Platform.Arch)" }
  if ($GoCommand) { throw "custom Go command is forbidden when a locked toolchain archive is configured" }
}
if (-not $MihomoUrl) { $MihomoUrl = [string]$Mihomo.source_repository }
if (-not $ShellCrashUrl) { $ShellCrashUrl = [string]$ShellCrash.source_repository }
Assert-SourceLocator $MihomoUrl ([bool]$FixtureMode)
Assert-SourceLocator $ShellCrashUrl ([bool]$FixtureMode)
if ($GoProxy -match '(?:^|,)direct(?:,|$)' -and -not $AllowDirectGoFallback) { throw "direct Go module fallback requires explicit opt-in" }
if ($AllowDirectGoFallback -and $GoProxy -notmatch '(?:^|,)direct(?:,|$)') { $GoProxy += ",direct" }

$Payloads = @{
  "mihomo-linux-arm64" = Join-Path $PayloadRoot "mihomo-linux-arm64"
  "shellcrash" = Join-Path $PayloadRoot "ShellCrash.tar.gz"
}
foreach ($Component in @($Mihomo, $ShellCrash)) {
  $Payload = $Payloads[[string]$Component.id]
  if (-not (Test-Path -LiteralPath $Payload -PathType Leaf)) { throw "payload missing: $($Component.id)" }
  if ((Get-Sha256 $Payload) -cne [string]$Component.payload_sha256) { throw "payload hash mismatch: $($Component.id)" }
}
$ManifestData = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$ManifestPayloads = @($ManifestData.payloads)
if ($ManifestData.schema -ne 1 -or $ManifestPayloads.Count -ne 2) { throw "invalid payload manifest structure" }
foreach ($Component in @($Mihomo, $ShellCrash)) {
  $Entry = @($ManifestPayloads | Where-Object { $_.id -ceq [string]$Component.id })
  if ($Entry.Count -ne 1) { throw "payload manifest component missing or duplicated: $($Component.id)" }
  $ExpectedPath = if ($Component.id -ceq "mihomo-linux-arm64") { "mihomo-linux-arm64" } else { "ShellCrash.tar.gz" }
  $ExpectedRepository = ([uri][string]$Component.source_repository).AbsolutePath.Trim("/")
  if ($ExpectedRepository.EndsWith(".git", [StringComparison]::Ordinal)) { $ExpectedRepository = $ExpectedRepository.Substring(0, $ExpectedRepository.Length - 4) }
  if (([string]($Entry[0].version) -cne [string]$Component.version) -or ([string]($Entry[0].path) -cne $ExpectedPath) -or ([string]($Entry[0].sourceRepository) -cne $ExpectedRepository) -or ([string]($Entry[0].sha256) -cne [string]$Component.payload_sha256)) { throw "payload manifest drift: $($Component.id)" }
}
$Python = Get-Python3
Assert-SafeArchive $Python $Payloads.shellcrash

$Stage = $OutputPath + ".stage-" + [guid]::NewGuid().ToString("N")
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
try {
  $Repos = Join-Path $Stage ".acquire"
  New-Item -ItemType Directory -Force -Path $Repos | Out-Null
  $GitHome = Join-Path $Stage ".git-home"; New-Item -ItemType Directory -Force -Path $GitHome | Out-Null
  $EmptyGitConfig = Join-Path $GitHome "gitconfig"; New-Item -ItemType File -Force -Path $EmptyGitConfig | Out-Null
  $PriorGitEnv = @{}
  foreach ($Name in @("GIT_TERMINAL_PROMPT", "GCM_INTERACTIVE", "HOME", "XDG_CONFIG_HOME", "GIT_CONFIG_GLOBAL")) { $PriorGitEnv[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
  try {
    $env:GIT_TERMINAL_PROMPT = "0"; $env:GCM_INTERACTIVE = "Never"; $env:HOME = $GitHome; $env:XDG_CONFIG_HOME = $GitHome; $env:GIT_CONFIG_GLOBAL = $EmptyGitConfig
    foreach ($Pair in @(
      @{ Component = $Mihomo; Url = $MihomoUrl; Repo = (Join-Path $Repos "mihomo"); Tag = [string]$Mihomo.version },
      @{ Component = $ShellCrash; Url = $ShellCrashUrl; Repo = (Join-Path $Repos "shellcrash"); Tag = [string]$ShellCrash.version }
    )) {
      Invoke-Checked git @("-c", "credential.helper=", "-c", "credential.interactive=never", "-c", "core.askPass=", "-c", "http.extraHeader=", "clone", "--no-checkout", "--depth", "1", "--single-branch", "--branch", $Pair.Tag, $Pair.Url, $Pair.Repo) "upstream clone failed: $($Pair.Component.id)"
      Invoke-Checked git @("-C", $Pair.Repo, "checkout", "--detach", [string]$Pair.Component.source_commit) "upstream checkout failed: $($Pair.Component.id)"
      $Head = (& git -C $Pair.Repo rev-parse HEAD).Trim()
      if ($LASTEXITCODE -ne 0 -or $Head -cne [string]$Pair.Component.source_commit) { throw "source commit mismatch: $($Pair.Component.id)" }
      $TagCommit = (& git -C $Pair.Repo rev-list -n 1 $Pair.Tag).Trim()
      if ($LASTEXITCODE -ne 0 -or $TagCommit -cne $Head) { throw "tag commit mismatch: $($Pair.Component.id)" }
    }
  }
  finally {
    foreach ($Name in $PriorGitEnv.Keys) { [Environment]::SetEnvironmentVariable($Name, $PriorGitEnv[$Name], "Process") }
  }

  $ThirdParty = Join-Path $Stage "third-party"
  $MihomoTree = Join-Path $ThirdParty "mihomo\source"
  $ShellTree = Join-Path $ThirdParty "shellcrash\source"
  Copy-TrackedTree $Python (Join-Path $Repos "mihomo") $MihomoTree
  Copy-TrackedTree $Python (Join-Path $Repos "shellcrash") $ShellTree

  $MihomoLicense = Join-Path $MihomoTree "LICENSE"
  $ShellLicense = Join-Path $ShellTree "LICENSE.txt"
  if (-not (Test-Path -LiteralPath $MihomoLicense -PathType Leaf) -or -not (Test-Path -LiteralPath $ShellLicense -PathType Leaf)) { throw "upstream license missing" }
  if ((Get-Sha256 $MihomoLicense) -cne [string]$Mihomo.license_sha256) { throw "license mismatch: mihomo-linux-arm64" }
  if ((Get-Sha256 $ShellLicense) -cne [string]$ShellCrash.license_sha256) { throw "license mismatch: shellcrash" }
  $ShellRuntimeEvidence = Join-Path $ShellTree "ShellCrash.tar.gz"
  if (-not (Test-Path -LiteralPath $ShellRuntimeEvidence -PathType Leaf) -or (Get-Sha256 $ShellRuntimeEvidence) -cne [string]$ShellCrash.payload_sha256) { throw "ShellCrash runtime payload does not match tagged source evidence" }
  Copy-Item -LiteralPath $MihomoLicense -Destination (Join-Path $ThirdParty "mihomo\LICENSE")
  Copy-Item -LiteralPath $ShellLicense -Destination (Join-Path $ThirdParty "shellcrash\LICENSE.txt")
  Copy-Item -LiteralPath $Payloads["mihomo-linux-arm64"] -Destination (Join-Path $ThirdParty "mihomo\mihomo-linux-arm64")
  Copy-Item -LiteralPath $Payloads.shellcrash -Destination (Join-Path $ThirdParty "shellcrash\ShellCrash.tar.gz")

  if ($null -ne $SourceAcquisition) {
    $Go = Expand-GoToolchain $Python ([System.IO.Path]::GetFullPath($GoArchive)) (Join-Path $Stage ".go-toolchain")
  }
  elseif ($FixtureMode) { $Go = Resolve-GoCommand }
  else { throw "locked Go toolchain provenance is required" }
  if (-not $GoWorkRoot) { $GoWorkRoot = Join-Path $Stage ".go-work" }
  $GoRoot = [System.IO.Path]::GetFullPath($GoWorkRoot)
  New-Item -ItemType Directory -Force -Path $GoRoot | Out-Null
  $PriorEnv = @{}
  foreach ($Name in @("GOMODCACHE", "GOCACHE", "GOPATH", "GOENV", "GOTOOLCHAIN", "GOFLAGS", "GOPROXY", "GOSUMDB", "GOPRIVATE", "GONOPROXY", "GONOSUMDB", "GOMAXPROCS")) { $PriorEnv[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process") }
  try {
    $env:GOMODCACHE = Join-Path $GoRoot "modcache"
    $env:GOCACHE = Join-Path $GoRoot "buildcache"
    $env:GOPATH = Join-Path $GoRoot "gopath"
    $env:GOENV = "off"
    $env:GOTOOLCHAIN = "local"
    $env:GOFLAGS = "-modcacherw"
    $env:GOPROXY = $GoProxy
    $env:GOSUMDB = "sum.golang.org"
    $env:GOPRIVATE = ""
    $env:GONOPROXY = ""
    $env:GONOSUMDB = ""
    $env:GOMAXPROCS = "4"
    $GoVersionOutput = (& $Go version).Trim()
    if ($LASTEXITCODE -ne 0 -or $GoVersionOutput -notmatch '^go version (go[0-9]+\.[0-9]+(?:\.[0-9]+)?)') { throw "unable to record Go toolchain version" }
    $GoVersion = $Matches[1]
    if ($null -ne $SourceAcquisition -and $GoVersion -cne [string]$SourceAcquisition.go_toolchain_version) { throw "Go toolchain version mismatch" }
    Push-Location $MihomoTree
    try {
      $DownloadLog = Join-Path $GoRoot "module-download.jsonstream"
      & $Go mod download -json all 2>&1 | Out-File -LiteralPath $DownloadLog -Encoding utf8
      if ($LASTEXITCODE -ne 0) { throw "go mod download failed (exit $LASTEXITCODE)" }
      $DownloadedModules = Join-Path $GoRoot "downloaded-modules.json"
      $null = Convert-GoDownloadLog $Python $DownloadLog $DownloadedModules $MaxModules
      Invoke-Checked $Go @("mod", "verify") "go mod verify failed"
      Invoke-Checked $Go @("mod", "vendor") "go mod vendor failed"
      $ModuleCount = Write-VendorManifest $Python $DownloadedModules (Join-Path $MihomoTree "vendor") (Join-Path $MihomoTree "VENDORED-MODULES.json")
    }
    finally { Pop-Location }
  }
  finally {
    foreach ($Name in $PriorEnv.Keys) { [Environment]::SetEnvironmentVariable($Name, $PriorEnv[$Name], "Process") }
  }
  $VendorManifest = Join-Path $MihomoTree "vendor\modules.txt"
  $VendorSources = @(Get-ChildItem -LiteralPath (Join-Path $MihomoTree "vendor") -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -cne "modules.txt" })
  if (-not (Test-Path -LiteralPath $VendorManifest -PathType Leaf) -or $VendorSources.Count -eq 0) { throw "Mihomo vendored module source is incomplete" }

  $SourceDir = Join-Path $ThirdParty "sources"
  New-Item -ItemType Directory -Force -Path $SourceDir | Out-Null
  $MihomoEpoch = [long](& git -C (Join-Path $Repos "mihomo") show -s --format=%ct HEAD)
  $ShellEpoch = [long](& git -C (Join-Path $Repos "shellcrash") show -s --format=%ct HEAD)
  Write-SourceMetadata $Python (Join-Path $MihomoTree "SOURCE-BUILD.json") ([string]$Mihomo.id) ([string]$Mihomo.version) ([string]$Mihomo.source_repository) ([string]$Mihomo.source_commit) $MihomoEpoch "go mod download -json all; go mod verify; go mod vendor" $GoVersion $GoProxy $ModuleCount
  Write-SourceMetadata $Python (Join-Path $ShellTree "SOURCE-BUILD.json") ([string]$ShellCrash.id) ([string]$ShellCrash.version) ([string]$ShellCrash.source_repository) ([string]$ShellCrash.source_commit) $ShellEpoch "full tagged Git source tree including build and install scripts"
  $MihomoArchive = Join-Path $SourceDir "mihomo-v1.19.28-complete-source.tar.gz"
  $ShellArchive = Join-Path $SourceDir "shellcrash-1.9.4-complete-source.tar.gz"
  $CanonicalArchiver = Join-Path $PSScriptRoot "canonical-source-archive.go"
  if (-not (Test-Path -LiteralPath $CanonicalArchiver -PathType Leaf)) { throw "canonical source archiver is missing" }
  New-CanonicalArchive $Go $CanonicalArchiver $MihomoTree $MihomoArchive "mihomo-v1.19.28-source" $MihomoEpoch $GoRoot
  New-CanonicalArchive $Go $CanonicalArchiver $ShellTree $ShellArchive "shellcrash-1.9.4-source" $ShellEpoch $GoRoot
  $MihomoArchiveSha = Get-Sha256 $MihomoArchive
  Write-PreparationMetadata $Python (Join-Path $ThirdParty "mihomo\SOURCE-PREPARATION.json") ([string]$Mihomo.id) ([string]$Mihomo.version) ([string]$Mihomo.source_repository) ([string]$Mihomo.source_commit) $GoVersion ([string]$SelectedToolchain.os) ([string]$SelectedToolchain.arch) ([string]$SelectedToolchain.filename) ([string]$SelectedToolchain.sha256) ([System.IO.Path]::GetFileName($MihomoArchive)) $MihomoArchiveSha
  Remove-Item -LiteralPath $Repos -Recurse -Force
  if (Test-Path -LiteralPath $GitHome) { Remove-Item -LiteralPath $GitHome -Recurse -Force }
  if ((Join-Path $Stage ".go-work") -ceq $GoRoot -and (Test-Path -LiteralPath $GoRoot)) { Remove-Item -LiteralPath $GoRoot -Recurse -Force }
  $ToolchainRoot = Join-Path $Stage ".go-toolchain"
  if (Test-Path -LiteralPath $ToolchainRoot) { Remove-Item -LiteralPath $ToolchainRoot -Recurse -Force }
  [System.IO.Directory]::Move($Stage, $OutputPath)
  Write-Host "third_party_source_state=ready"
  Write-Host "mihomo_source_commit=$($Mihomo.source_commit)"
  Write-Host "mihomo_source_sha256=$(Get-Sha256 (Join-Path $OutputPath 'third-party\sources\mihomo-v1.19.28-complete-source.tar.gz'))"
  Write-Host "shellcrash_source_commit=$($ShellCrash.source_commit)"
  Write-Host "shellcrash_source_sha256=$(Get-Sha256 (Join-Path $OutputPath 'third-party\sources\shellcrash-1.9.4-complete-source.tar.gz'))"
}
catch {
  if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
  throw
}
