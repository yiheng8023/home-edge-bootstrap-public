param(
  [Parameter(Mandatory = $true)][string]$StageRoot,
  [Parameter(Mandatory = $true)][string]$SourceRoot
)
$ErrorActionPreference = "Stop"
$StageRoot = (Resolve-Path -LiteralPath $StageRoot).Path
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$MetadataPath = Join-Path $StageRoot "DEPLOYMENT-PROVENANCE.env"
$SumsPath = Join-Path $StageRoot "DEPLOYMENT-CONTENT-SHA256SUMS"
Remove-Item -LiteralPath $MetadataPath, $SumsPath -Force -ErrorAction SilentlyContinue

$SourceKind = "non_git"
$SourceCommit = "non-git"
$SourceTreeState = "not_applicable"
$SourceVersion = "unversioned"
& git -C $SourceRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -eq 0) {
  $SourceKind = "git"
  $SourceCommit = (& git -C $SourceRoot rev-parse HEAD).Trim()
  $Dirty = (& git -C $SourceRoot status --porcelain --untracked-files=no | Out-String).Trim()
  $SourceTreeState = $(if ($Dirty) { "dirty" } else { "clean" })
}
else {
  $VersionPath = Join-Path $SourceRoot "VERSION"
  if (Test-Path -LiteralPath $VersionPath -PathType Leaf) {
    $Candidate = (Get-Content -LiteralPath $VersionPath -TotalCount 1).Trim()
    if ($Candidate -match '^v[0-9]+\.[0-9]+\.[0-9]+$') {
      $SourceKind = "release"
      $SourceVersion = $Candidate
    }
  }
}

$Files = Get-ChildItem -LiteralPath $StageRoot -File -Recurse | Where-Object {
  $_.FullName -ne $MetadataPath -and $_.FullName -ne $SumsPath
} | Sort-Object { $_.FullName.Substring($StageRoot.Length).TrimStart('\', '/').Replace('\', '/') }
$Lines = foreach ($File in $Files) {
  $Relative = $File.FullName.Substring($StageRoot.Length).TrimStart('\', '/').Replace('\', '/')
  $Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $File.FullName).Hash.ToLowerInvariant()
  "$Hash  $Relative"
}
$Utf8NoBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText($SumsPath, (($Lines -join "`n") + "`n"), $Utf8NoBom)
$ContentId = (Get-FileHash -Algorithm SHA256 -LiteralPath $SumsPath).Hash.ToLowerInvariant()
$Metadata = @(
  "schema_version=1",
  "source_kind=$SourceKind",
  "source_commit=$SourceCommit",
  "source_tree_state=$SourceTreeState",
  "source_version=$SourceVersion",
  "content_id=$ContentId",
  "managed_file_count=$($Files.Count)"
) -join "`n"
[IO.File]::WriteAllText($MetadataPath, $Metadata + "`n", $Utf8NoBom)
