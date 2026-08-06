$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$RequiredVars = @(
  "TMDB_API_KEY",
  "ANILIST_API_URL",
  "IMAGE_PROXY_URL",
  "IPTV_PLAYLIST_URL",
  "LOG_LEVEL",
  "FIREBASE_WEB_API_KEY",
  "FIREBASE_PROJECT_ID",
  "FIREBASE_GOOGLE_CLIENT_ID",
  "AUTH_EXCHANGE_URL"
)

$Missing = @()
foreach ($Key in $RequiredVars) {
  $Value = [Environment]::GetEnvironmentVariable($Key)
  if ([string]::IsNullOrWhiteSpace($Value)) {
    $Missing += $Key
  }
}

if ($Missing.Count -gt 0) {
  throw "Missing required release config: $($Missing -join ', ')"
}

if (-not [string]::IsNullOrWhiteSpace($env:FIREBASE_GOOGLE_CLIENT_SECRET) -or
    -not [string]::IsNullOrWhiteSpace($env:GOOGLE_CLIENT_SECRET)) {
  throw "Refusing to build: Google client secrets must not be compiled into the desktop app."
}

$Defines = @(
  "--dart-define=TMDB_API_KEY=$env:TMDB_API_KEY",
  "--dart-define=TMDB_READ_ACCESS_TOKEN=$env:TMDB_READ_ACCESS_TOKEN",
  "--dart-define=ANILIST_API_URL=$env:ANILIST_API_URL",
  "--dart-define=SUPABASE_URL=$env:SUPABASE_URL",
  "--dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY",
  "--dart-define=IPTV_PLAYLIST_URL=$env:IPTV_PLAYLIST_URL",
  "--dart-define=IPTV_EPG_URL=$env:IPTV_EPG_URL",
  "--dart-define=FIREBASE_WEB_API_KEY=$env:FIREBASE_WEB_API_KEY",
  "--dart-define=FIREBASE_PROJECT_ID=$env:FIREBASE_PROJECT_ID",
  "--dart-define=FIREBASE_GOOGLE_CLIENT_ID=$env:FIREBASE_GOOGLE_CLIENT_ID",
  "--dart-define=AUTH_EXCHANGE_URL=$env:AUTH_EXCHANGE_URL",
  "--dart-define=FIREBASE_APP_ID=$env:FIREBASE_APP_ID",
  "--dart-define=FIREBASE_MESSAGING_SENDER_ID=$env:FIREBASE_MESSAGING_SENDER_ID",
  "--dart-define=FIREBASE_STORAGE_BUCKET=$env:FIREBASE_STORAGE_BUCKET",
  "--dart-define=API_BASE_URL=$env:API_BASE_URL",
  "--dart-define=IMAGE_PROXY_URL=$env:IMAGE_PROXY_URL",
  "--dart-define=LOG_LEVEL=$env:LOG_LEVEL",
  "--dart-define=DESKTOP_UPDATE_REPO_OWNER=$env:DESKTOP_UPDATE_REPO_OWNER",
  "--dart-define=DESKTOP_UPDATE_REPO_NAME=$env:DESKTOP_UPDATE_REPO_NAME",
  "--dart-define=DESKTOP_UPDATE_ASSET_PATTERN=$env:DESKTOP_UPDATE_ASSET_PATTERN"
)

dart run tool/patch_window_manager_windows.dart

flutter build windows --release @Defines
