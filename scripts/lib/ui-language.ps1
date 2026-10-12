function Resolve-HomeEdgeUiLanguage {
  param([string]$ExplicitLanguage = "", [string]$HostLocale = [Globalization.CultureInfo]::CurrentUICulture.Name)
  if ($ExplicitLanguage) {
    if ($ExplicitLanguage -cnotin @("zh-CN", "en")) { throw "Invalid language. Use zh-CN or en." }
    return $ExplicitLanguage
  }
  if ($env:HOME_EDGE_LANGUAGE -cin @("zh-CN", "en")) { return $env:HOME_EDGE_LANGUAGE }
  if (-not $HostLocale -or $HostLocale -match '^zh') { return "zh-CN" }
  return "en"
}
function Get-HomeEdgeUiText {
  param([string]$Language, [string]$Chinese, [string]$English)
  if ($Language -ceq "en") { return $English }
  return $Chinese
}
