param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$Python=$null
foreach($Name in @('python','python3')){$C=Get-Command $Name -ErrorAction SilentlyContinue;if($C){& $C.Source -c 'import sys;raise SystemExit(0 if sys.version_info[0]==3 else 1)';if($LASTEXITCODE -eq 0){$Python=$C.Source;break}}}
if(-not $Python){throw 'Python 3 is required'}
& $Python (Join-Path $PSScriptRoot 'verify-media-kit.py') $Root
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
