param(
  [switch]$SkipBuild,
  [ValidateSet("normal", "shorebird")]
  [string]$BuildType = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$DesktopDir = Join-Path $ProjectRoot "packages\nivio_desktop"

if (-not (Test-Path $DesktopDir)) {
  $DesktopDir = Join-Path $ProjectRoot "nivio_desktop"
}

if (-not (Test-Path $DesktopDir)) {
  throw "Desktop package directory not found."
}

Set-Location $DesktopDir

$TargetScript = Join-Path $DesktopDir "scripts\package_windows_installer.ps1"
$scriptParams = @{}
if ($SkipBuild) {
  $scriptParams["SkipBuild"] = $true
}
if (-not [string]::IsNullOrWhiteSpace($BuildType)) {
  $scriptParams["BuildType"] = $BuildType
}

& $TargetScript @scriptParams
