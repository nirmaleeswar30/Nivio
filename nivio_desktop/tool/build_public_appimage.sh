#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

required_vars=(
  TMDB_API_KEY
  ANILIST_API_URL
  IMAGE_PROXY_URL
  IPTV_PLAYLIST_URL
  LOG_LEVEL
  FIREBASE_WEB_API_KEY
  FIREBASE_PROJECT_ID
  FIREBASE_GOOGLE_CLIENT_ID
  AUTH_EXCHANGE_URL
)

missing=()
for key in "${required_vars[@]}"; do
  if [[ -z "${!key:-}" ]]; then
    missing+=("$key")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'Missing required release config: %s\n' "${missing[*]}" >&2
  exit 1
fi

if [[ -n "${FIREBASE_GOOGLE_CLIENT_SECRET:-}" || -n "${GOOGLE_CLIENT_SECRET:-}" ]]; then
  echo "Refusing to build: Google client secrets must not be compiled into the desktop app." >&2
  exit 1
fi

cd "$ROOT_DIR"

flutter build linux --release \
  --dart-define="TMDB_API_KEY=$TMDB_API_KEY" \
  --dart-define="TMDB_READ_ACCESS_TOKEN=${TMDB_READ_ACCESS_TOKEN:-}" \
  --dart-define="ANILIST_API_URL=$ANILIST_API_URL" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL:-}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}" \
  --dart-define="IPTV_PLAYLIST_URL=$IPTV_PLAYLIST_URL" \
  --dart-define="IPTV_EPG_URL=${IPTV_EPG_URL:-}" \
  --dart-define="FIREBASE_WEB_API_KEY=$FIREBASE_WEB_API_KEY" \
  --dart-define="FIREBASE_PROJECT_ID=$FIREBASE_PROJECT_ID" \
  --dart-define="FIREBASE_GOOGLE_CLIENT_ID=$FIREBASE_GOOGLE_CLIENT_ID" \
  --dart-define="AUTH_EXCHANGE_URL=$AUTH_EXCHANGE_URL" \
  --dart-define="FIREBASE_APP_ID=${FIREBASE_APP_ID:-}" \
  --dart-define="FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID:-}" \
  --dart-define="FIREBASE_STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET:-}" \
  --dart-define="API_BASE_URL=${API_BASE_URL:-}" \
  --dart-define="IMAGE_PROXY_URL=$IMAGE_PROXY_URL" \
  --dart-define="LOG_LEVEL=$LOG_LEVEL" \
  --dart-define="DESKTOP_UPDATE_REPO_OWNER=${DESKTOP_UPDATE_REPO_OWNER:-}" \
  --dart-define="DESKTOP_UPDATE_REPO_NAME=${DESKTOP_UPDATE_REPO_NAME:-}" \
  --dart-define="DESKTOP_UPDATE_ASSET_PATTERN=${DESKTOP_UPDATE_ASSET_PATTERN:-}"

APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}" "$ROOT_DIR/tool/build_appimage.sh"
