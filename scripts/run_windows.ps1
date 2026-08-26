$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
$DesktopDir = Join-Path $RootDir "packages\nivio_desktop"

# Ensure packages/nivio_core/lib is a junction on Windows
$CoreLibPath = Join-Path $RootDir "packages\nivio_core\lib"
if (Test-Path $CoreLibPath -PathType Leaf) {
  Remove-Item $CoreLibPath -Force
  New-Item -ItemType Junction -Path $CoreLibPath -Target (Join-Path $RootDir "lib") | Out-Null
} elseif (-not (Test-Path $CoreLibPath)) {
  New-Item -ItemType Junction -Path $CoreLibPath -Target (Join-Path $RootDir "lib") | Out-Null
}

# Ensure tools are in PATH
$ExtraPaths = @(
  "$env:USERPROFILE\.cargo\bin",
  "$env:USERPROFILE\flutter\bin",
  "C:\flutter\bin",
  "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
  "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
)

foreach ($p in $ExtraPaths) {
  if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
    $env:PATH = "$p;$env:PATH"
  }
}

if (-not $env:FLUTTER_ROOT) {
  $FlutterRootCandidates = @(
    "$env:USERPROFILE\flutter",
    "C:\flutter",
    "C:\src\flutter"
  )
  foreach ($Candidate in $FlutterRootCandidates) {
    if (Test-Path "$Candidate\bin\flutter.bat") {
      $env:FLUTTER_ROOT = $Candidate
      break
    }
  }
}

$FlutterCmd = "flutter"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  $Candidates = @(
    "$env:USERPROFILE\flutter\bin\flutter.bat",
    "C:\flutter\bin\flutter.bat",
    "C:\src\flutter\bin\flutter.bat"
  )
  foreach ($Candidate in $Candidates) {
    if (Test-Path $Candidate) {
      $FlutterCmd = $Candidate
      break
    }
  }
}

$DartCmd = "dart"
if (-not (Get-Command dart -ErrorAction SilentlyContinue)) {
  $Candidates = @(
    "$env:USERPROFILE\flutter\bin\dart.bat",
    "C:\flutter\bin\dart.bat",
    "C:\src\flutter\bin\dart.bat"
  )
  foreach ($Candidate in $Candidates) {
    if (Test-Path $Candidate) {
      $DartCmd = $Candidate
      break
    }
  }
}

Write-Host "Applying C++ compatibility patches..." -ForegroundColor Cyan
Set-Location $DesktopDir
& $DartCmd run tool/patch_window_manager_windows.dart

Write-Host "Running Nivio Desktop on Windows (live debug mode with console logs)..." -ForegroundColor Green
& $FlutterCmd run -d windows @args
