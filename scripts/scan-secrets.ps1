param(
  [string]$Repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path,
  [string[]]$ScanPath = @()
)

$ErrorActionPreference = "Stop"

$Findings = New-Object System.Collections.Generic.List[string]
$Checked = 0
$Skipped = 0

function Add-Finding {
  param(
    [string]$Path,
    [int]$Line,
    [string]$Label
  )
  $Findings.Add("secret_finding=$Path`:$Line`:$Label") | Out-Null
}

function Get-RelativeDisplayPath {
  param([string]$Path)
  $Full = [System.IO.Path]::GetFullPath($Path)
  $Root = [System.IO.Path]::GetFullPath($Repo).TrimEnd('\')
  if ($Full.StartsWith($Root, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $Full.Substring($Root.Length).TrimStart('\') -replace '\\', '/'
  }
  return $Full -replace '\\', '/'
}

function Should-SkipFile {
  param([System.IO.FileInfo]$File)
  $Display = Get-RelativeDisplayPath $File.FullName
  if ($Display -match '(^|/)\.git(/|$)') { return $true }
  if ($Display -match '(^|/)(cache|backups|node_modules)(/|$)') { return $true }
  if ($Display -match '(?i)\.(zip|gz|tgz|tar|bin|exe|dll|so|dylib|png|jpg|jpeg|webp|ico|pdf)$') { return $true }
  if ($File.Length -gt 2MB) { return $true }
  return $false
}

function Get-DefaultFiles {
  Push-Location -LiteralPath $Repo
  try {
    $Files = & git ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
      throw "git ls-files failed"
    }
    foreach ($Rel in $Files) {
      $Path = Join-Path $Repo $Rel
      if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Get-Item -LiteralPath $Path
      }
    }
  }
  finally {
    Pop-Location
  }
}

function Get-ScanFiles {
  if ($ScanPath.Count -eq 0) {
    Get-DefaultFiles
    return
  }
  foreach ($Item in $ScanPath) {
    $Resolved = Resolve-Path -LiteralPath $Item -ErrorAction Stop
    foreach ($Path in $Resolved) {
      if (Test-Path -LiteralPath $Path.Path -PathType Leaf) {
        Get-Item -LiteralPath $Path.Path
      }
      elseif (Test-Path -LiteralPath $Path.Path -PathType Container) {
        Get-ChildItem -LiteralPath $Path.Path -Recurse -File
      }
    }
  }
}

$FilenameDenyList = @(
  '(?i)(^|/)SUBSCRIPTION\.local$',
  '(?i)(^|/)subscription.*\.(txt|local|yaml|yml)$',
  '(?i)(^|/)nodes.*\.ya?ml$',
  '(?i)\.(key|pem)$',
  '(?i)(^|/)\.env$'
)

$ContentRules = @(
  @{ Label = "private_key"; Pattern = "-----BEGIN [A-Z ]*PRIVATE KEY-----" },
  @{ Label = "proxy_uri"; Pattern = "(?i)\b(vmess|vless|trojan|hysteria2?|ssr?)://[^\s`"'<>]{8,}" },
  @{ Label = "secret_assignment"; Pattern = "(?i)(^|[^A-Za-z0-9_-])(subscription(_url)?|password|passwd|token|secret|authorization|api[-_ ]?key)\s*[:=]\s*[`"']?(?![\$<{]|REDACTED)[^\s`"']{12,}" },
  @{ Label = "uuid_assignment"; Pattern = "(?i)(^|[^A-Za-z0-9_-])uuid\s*[:=]\s*[`"']?(?![\$<{]|REDACTED)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}" },
  @{ Label = "openai_key"; Pattern = "\b(sk-proj-|sk-)[A-Za-z0-9_-]{20,}" },
  @{ Label = "github_token"; Pattern = "\b(ghp_|github_pat_)[A-Za-z0-9_]{20,}" },
  @{ Label = "aws_access_key"; Pattern = "\bAKIA[0-9A-Z]{16}\b" },
  @{ Label = "google_api_key"; Pattern = "\bAIza[0-9A-Za-z_-]{20,}\b" }
)

foreach ($File in Get-ScanFiles) {
  $Display = Get-RelativeDisplayPath $File.FullName
  $SensitiveName = $false
  foreach ($Rule in $FilenameDenyList) {
    if ($Display -match $Rule) {
      Add-Finding $Display 0 "sensitive_filename"
      $SensitiveName = $true
    }
  }
  if (-not $SensitiveName -and (Should-SkipFile $File)) {
    $Skipped++
    continue
  }
  $Checked++
  $Text = [System.IO.File]::ReadAllText($File.FullName, [System.Text.Encoding]::UTF8)
  $Lines = $Text -split "`r?`n"
  for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
    foreach ($Rule in $ContentRules) {
      if ($Lines[$Index] -match $Rule.Pattern) {
        Add-Finding $Display ($Index + 1) $Rule.Label
      }
    }
  }
}

Write-Host "# Secret Scan"
Write-Host ""
if ($Findings.Count) {
  Write-Host "secret_scan_state=failed"
  foreach ($Finding in $Findings) {
    Write-Host $Finding
  }
  Write-Host "checked_files=$Checked"
  Write-Host "skipped_files=$Skipped"
  exit 1
}

Write-Host "secret_scan_state=ready"
Write-Host "checked_files=$Checked"
Write-Host "skipped_files=$Skipped"
