param(
  [string]$MihomoVersion = "v1.19.28",
  [string]$ShellCrashVersion = "1.9.4",
  [string]$BundleDir = "",
  [switch]$Force,
  [switch]$KeepCompressedSource,
  [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"

$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $BundleDir) {
  $BundleDir = Join-Path $Repo "bundle"
}
$BundleDir = (New-Item -ItemType Directory -Force $BundleDir).FullName

$MihomoAsset = "mihomo-linux-arm64-$MihomoVersion.gz"
$ShellCrashAsset = "ShellCrash.tar.gz"
$MihomoUrl = "https://github.com/MetaCubeX/mihomo/releases/download/$MihomoVersion/$MihomoAsset"
$ShellCrashUrl = "https://github.com/juewuy/ShellCrash/releases/download/$ShellCrashVersion/$ShellCrashAsset"

$MihomoGz = Join-Path $BundleDir $MihomoAsset
$MihomoOut = Join-Path $BundleDir "mihomo-linux-arm64"
$ShellCrashOut = Join-Path $BundleDir $ShellCrashAsset
$ManifestOut = Join-Path $BundleDir "MANIFEST.json"
$ShaOut = Join-Path $BundleDir "SHA256SUMS"
$SbomOut = Join-Path $Repo "config\sbom.json"

function Download-File {
  param(
    [string]$Url,
    [string]$Path
  )
  if ((Test-Path -LiteralPath $Path) -and -not $Force) {
    Write-Host "Keeping existing $Path"
    return
  }
  Write-Host "Downloading $Url"
  Invoke-WebRequest -Uri $Url -OutFile $Path
}

function Expand-Gzip {
  param(
    [string]$Source,
    [string]$Destination
  )
  if ((Test-Path -LiteralPath $Destination) -and -not $Force) {
    Write-Host "Keeping existing $Destination"
    return
  }
  Write-Host "Expanding $Source -> $Destination"
  $inStream = [IO.File]::OpenRead($Source)
  try {
    $gzip = [IO.Compression.GzipStream]::new($inStream, [IO.Compression.CompressionMode]::Decompress)
    try {
      $outStream = [IO.File]::Create($Destination)
      try {
        $gzip.CopyTo($outStream)
      }
      finally {
        $outStream.Dispose()
      }
    }
    finally {
      $gzip.Dispose()
    }
  }
  finally {
    $inStream.Dispose()
  }
}

function Hash-File {
  param([string]$Path)
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

Download-File -Url $MihomoUrl -Path $MihomoGz
Download-File -Url $ShellCrashUrl -Path $ShellCrashOut
Expand-Gzip -Source $MihomoGz -Destination $MihomoOut

$mihomoHash = Hash-File $MihomoOut
$mihomoGzHash = Hash-File $MihomoGz
$shellCrashHash = Hash-File $ShellCrashOut

$shaLines = @(
  "$mihomoHash  mihomo-linux-arm64",
  "$shellCrashHash  ShellCrash.tar.gz"
)
[IO.File]::WriteAllText($ShaOut, ($shaLines -join "`n") + "`n", [Text.ASCIIEncoding]::new())

$manifest = [ordered]@{
  schema = 1
  generatedAt = (Get-Date).ToUniversalTime().ToString("o")
  sourcePolicy = "Pinned GitHub release assets; verify SHA256SUMS before offline use."
  payloads = @(
    [ordered]@{
      id = "mihomo-linux-arm64"
      path = "mihomo-linux-arm64"
      version = $MihomoVersion
      sourceRepository = "MetaCubeX/mihomo"
      sourceAsset = $MihomoAsset
      sourceUrl = $MihomoUrl
      sourceSha256 = $mihomoGzHash
      sha256 = $mihomoHash
      sizeBytes = (Get-Item -LiteralPath $MihomoOut).Length
    },
    [ordered]@{
      id = "shellcrash"
      path = "ShellCrash.tar.gz"
      version = $ShellCrashVersion
      sourceRepository = "juewuy/ShellCrash"
      sourceAsset = $ShellCrashAsset
      sourceUrl = $ShellCrashUrl
      sha256 = $shellCrashHash
      sizeBytes = (Get-Item -LiteralPath $ShellCrashOut).Length
    }
  )
}

$manifestJson = (($manifest | ConvertTo-Json -Depth 6) -replace "`r`n", "`n")
$utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($ManifestOut, $manifestJson + "`n", $utf8NoBom)

$sbom = [ordered]@{
  schema_version = 1
  format = "home-edge-sbom"
  generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
  scope = "offline-router-runtime-bundle"
  authority_boundary = "Local hashes prove checkout integrity only; upstream authenticity requires upstream release/signature/checksum review when available."
  components = @(
    [ordered]@{
      id = "mihomo-linux-arm64"
      name = "mihomo"
      type = "runtime-binary"
      version = $MihomoVersion
      target_arch = "linux-arm64"
      source_repository = "MetaCubeX/mihomo"
      source_asset = $MihomoAsset
      source_url = $MihomoUrl
      source_sha256 = $mihomoGzHash
      bundle_path = "bundle/mihomo-linux-arm64"
      bundle_sha256 = $mihomoHash
      bundle_size_bytes = (Get-Item -LiteralPath $MihomoOut).Length
      license = "upstream-reviewed-required"
      upstream_authenticity = "not_attested_by_this_repo"
      replacement_policy = "Replace only through scripts/prepare-bundle with reviewed release notes, regenerated MANIFEST/SHA256SUMS/SBOM, and passing local verification."
    },
    [ordered]@{
      id = "shellcrash"
      name = "ShellCrash"
      type = "router-runtime-manager-archive"
      version = $ShellCrashVersion
      target_arch = "router-shell"
      source_repository = "juewuy/ShellCrash"
      source_asset = $ShellCrashAsset
      source_url = $ShellCrashUrl
      source_sha256 = $shellCrashHash
      bundle_path = "bundle/ShellCrash.tar.gz"
      bundle_sha256 = $shellCrashHash
      bundle_size_bytes = (Get-Item -LiteralPath $ShellCrashOut).Length
      license = "upstream-reviewed-required"
      upstream_authenticity = "not_attested_by_this_repo"
      replacement_policy = "Replace only through scripts/prepare-bundle with reviewed release notes, regenerated MANIFEST/SHA256SUMS/SBOM, and passing local verification."
    }
  )
}
$sbomJson = (($sbom | ConvertTo-Json -Depth 8) -replace "`r`n", "`n")
[IO.File]::WriteAllText($SbomOut, $sbomJson + "`n", $utf8NoBom)

if (-not $KeepCompressedSource) {
  Remove-Item -LiteralPath $MihomoGz -Force -ErrorAction SilentlyContinue
}

if (-not $SkipVerify) {
  $verifyScript = Join-Path $Repo "scripts\verify-bundle.sh"
  if (Get-Command sh -ErrorAction SilentlyContinue) {
    $repoForSh = $Repo.Replace("\", "/")
    & sh -lc "cd '$repoForSh' && sh scripts/verify-bundle.sh"
    if ($LASTEXITCODE -ne 0) {
      throw "bundle verification failed"
    }
  } else {
    Write-Warning "sh not found; skipping scripts/verify-bundle.sh"
  }
}

Write-Host "Bundle ready: $BundleDir"
Write-Host "Remember: binaries are git-ignored by default; use git add -f bundle/mihomo-linux-arm64 bundle/ShellCrash.tar.gz when you intentionally want clone-and-go offline restore."
