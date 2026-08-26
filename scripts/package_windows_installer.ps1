param(
  [switch]$SkipBuild
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
if ($SkipBuild) {
  & $TargetScript -SkipBuild
} else {
  & $TargetScript
}
