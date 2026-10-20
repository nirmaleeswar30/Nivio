param(
  [ValidateSet("normal", "shorebird")]
  [string]$BuildType = ""
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

# Ensure packages/nivio_core/lib is a junction on Windows
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $RootDir)
$CoreLibPath = Join-Path $ProjectRoot "packages\nivio_core\lib"
if (Test-Path $CoreLibPath -PathType Leaf) {
  Remove-Item $CoreLibPath -Force
  New-Item -ItemType Junction -Path $CoreLibPath -Target (Join-Path $ProjectRoot "lib") | Out-Null
} elseif (-not (Test-Path $CoreLibPath)) {
  New-Item -ItemType Junction -Path $CoreLibPath -Target (Join-Path $ProjectRoot "lib") | Out-Null
}

# Ensure tools are in PATH
$ExtraPaths = @(
  "$env:USERPROFILE\.cargo\bin",
  "C:\Program Files\Rust stable MSVC 1.98\bin",
  "$env:USERPROFILE\flutter\bin",
  "C:\flutter\bin",
  "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
  "$env:LOCALAPPDATA\Programs\Inno Setup 6",
  "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
)

foreach ($p in $ExtraPaths) {
  if ((Test-Path $p) -and ($env:PATH -notlike "*$p*")) {
    $env:PATH = "$p;$env:PATH"
  }
}

# Ensure FLUTTER_ROOT is set
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

# Locate Flutter binary
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

# Locate Dart binary
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

# Helper to load .env file if present
function Load-EnvFile($Path) {
  if (Test-Path $Path) {
    Get-Content $Path | ForEach-Object {
      $line = $_.Trim()
      if ($line -and -not $line.StartsWith("#") -and $line.Contains("=")) {
        $parts = $line.Split("=", 2)
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        if (-not [Environment]::GetEnvironmentVariable($key)) {
          [Environment]::SetEnvironmentVariable($key, $val, "Process")
        }
      }
    }
  }
}

Load-EnvFile (Join-Path $RootDir ".env")
Load-EnvFile (Join-Path (Split-Path -Parent (Split-Path -Parent $RootDir)) ".env")

# Fallbacks for variables if not set
if (-not $env:TMDB_API_KEY) { $env:TMDB_API_KEY = "d39245e111947eb92b947e3a8aacc89f" }
if (-not $env:LOG_LEVEL) { $env:LOG_LEVEL = "info" }

$Defines = @()
if ($env:TMDB_API_KEY) { $Defines += "--dart-define=TMDB_API_KEY=$env:TMDB_API_KEY" }
if ($env:TMDB_READ_ACCESS_TOKEN) { $Defines += "--dart-define=TMDB_READ_ACCESS_TOKEN=$env:TMDB_READ_ACCESS_TOKEN" }
if ($env:ANILIST_API_URL) { $Defines += "--dart-define=ANILIST_API_URL=$env:ANILIST_API_URL" }
if ($env:SUPABASE_URL) { $Defines += "--dart-define=SUPABASE_URL=$env:SUPABASE_URL" }
if ($env:SUPABASE_ANON_KEY) { $Defines += "--dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY" }
if ($env:IPTV_PLAYLIST_URL) { $Defines += "--dart-define=IPTV_PLAYLIST_URL=$env:IPTV_PLAYLIST_URL" }
if ($env:IPTV_EPG_URL) { $Defines += "--dart-define=IPTV_EPG_URL=$env:IPTV_EPG_URL" }
if ($env:FIREBASE_WEB_API_KEY) { $Defines += "--dart-define=FIREBASE_WEB_API_KEY=$env:FIREBASE_WEB_API_KEY" }
if ($env:FIREBASE_PROJECT_ID) { $Defines += "--dart-define=FIREBASE_PROJECT_ID=$env:FIREBASE_PROJECT_ID" }
if ($env:FIREBASE_GOOGLE_CLIENT_ID) { $Defines += "--dart-define=FIREBASE_GOOGLE_CLIENT_ID=$env:FIREBASE_GOOGLE_CLIENT_ID" }
if ($env:AUTH_EXCHANGE_URL) { $Defines += "--dart-define=AUTH_EXCHANGE_URL=$env:AUTH_EXCHANGE_URL" }
if ($env:FIREBASE_APP_ID) { $Defines += "--dart-define=FIREBASE_APP_ID=$env:FIREBASE_APP_ID" }
if ($env:FIREBASE_MESSAGING_SENDER_ID) { $Defines += "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$env:FIREBASE_MESSAGING_SENDER_ID" }
if ($env:FIREBASE_STORAGE_BUCKET) { $Defines += "--dart-define=FIREBASE_STORAGE_BUCKET=$env:FIREBASE_STORAGE_BUCKET" }
if ($env:API_BASE_URL) { $Defines += "--dart-define=API_BASE_URL=$env:API_BASE_URL" }
if ($env:IMAGE_PROXY_URL) { $Defines += "--dart-define=IMAGE_PROXY_URL=$env:IMAGE_PROXY_URL" }
if ($env:LOG_LEVEL) { $Defines += "--dart-define=LOG_LEVEL=$env:LOG_LEVEL" }
if ($env:DESKTOP_UPDATE_REPO_OWNER) { $Defines += "--dart-define=DESKTOP_UPDATE_REPO_OWNER=$env:DESKTOP_UPDATE_REPO_OWNER" }
if ($env:DESKTOP_UPDATE_REPO_NAME) { $Defines += "--dart-define=DESKTOP_UPDATE_REPO_NAME=$env:DESKTOP_UPDATE_REPO_NAME" }
if ($env:DESKTOP_UPDATE_ASSET_PATTERN) { $Defines += "--dart-define=DESKTOP_UPDATE_ASSET_PATTERN=$env:DESKTOP_UPDATE_ASSET_PATTERN" }

# Interactive Prompt for Build Type if not passed via parameter
if ([string]::IsNullOrWhiteSpace($BuildType)) {
  Write-Host ""
  Write-Host "Select Windows Release Type:" -ForegroundColor Cyan
  Write-Host "  [1] Normal Release (Standard Flutter AOT build)" -ForegroundColor Yellow
  Write-Host "  [2] Shorebird Release (Enables Over-the-Air Dart code pushes)" -ForegroundColor Green
  $selection = Read-Host "Enter choice [1 or 2] (Default: 1)"
  if ($selection -eq "2") {
    $BuildType = "shorebird"
  } else {
    $BuildType = "normal"
  }
}

if ($BuildType -eq "shorebird") {
  Write-Host ""
  Write-Host "Checking Shorebird CLI..." -ForegroundColor Yellow
  $ShorebirdCmd = Get-Command shorebird -ErrorAction SilentlyContinue
  if (-not $ShorebirdCmd) {
    $ShorebirdCandidates = @(
      "$env:USERPROFILE\.shorebird\bin\shorebird.ps1",
      "$env:USERPROFILE\.shorebird\bin\shorebird.bat"
    )
    foreach ($cand in $ShorebirdCandidates) {
      if (Test-Path $cand) {
        $ShorebirdCmd = $cand
        break
      }
    }
  }

  if (-not $ShorebirdCmd) {
    throw "Shorebird CLI was not found. Please install Shorebird (https://docs.shorebird.dev) to build Shorebird releases."
  }

  # Verify if logged in to Shorebird
  Write-Host "Verifying Shorebird credentials..." -ForegroundColor Yellow
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/c shorebird apps list"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $proc = [System.Diagnostics.Process]::Start($psi)
  $proc.WaitForExit()
  $appsOutput = $proc.StandardOutput.ReadToEnd() + " " + $proc.StandardError.ReadToEnd()

  if ($appsOutput -match "shorebird login" -or $appsOutput -match "rejected your stored credentials" -or $appsOutput -match "Failed to refresh credentials") {
    Write-Host ""
    Write-Host "Shorebird is not logged in or credentials have expired." -ForegroundColor Yellow
    Write-Host "Launching 'shorebird login'..." -ForegroundColor Cyan
    & cmd.exe /c shorebird login
    if ($LASTEXITCODE -ne 0) {
      throw "Shorebird login was unsuccessful. Cannot proceed with Shorebird release."
    }
  }
}

Write-Host "Running plugin C++ compatibility patch..."
& $DartCmd run tool/patch_window_manager_windows.dart
if ($LASTEXITCODE -ne 0) {
  Write-Warning "Plugin patch returned non-zero code ($LASTEXITCODE), continuing..."
}

if ($BuildType -eq "shorebird") {
  Write-Host "Building Shorebird Windows Release (OTA-enabled)..." -ForegroundColor Green
  & shorebird release windows @Defines
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
} else {
  Write-Host "Building Standard Flutter Windows Release..." -ForegroundColor Cyan
  & $FlutterCmd build windows --release @Defines
  if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
  }
}
