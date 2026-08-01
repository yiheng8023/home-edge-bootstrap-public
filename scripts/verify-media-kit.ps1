param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'lib\resolve-python.ps1')
$Python=Resolve-Python3
& $Python (Join-Path $PSScriptRoot 'verify-media-kit.py') $Root
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
