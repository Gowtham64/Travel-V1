#!/usr/bin/env bash
set -euo pipefail

# Build the Flutter source once for Cloudflare Pages. The output directory is
# mobile/build/web, Flutter's actual production build directory.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/mobile/build/web"
APP_ENV="${APP_ENV:-production}"
BACKEND_URL="${BACKEND_URL:-https://api.voyplan.in}"

# Fail before building if a dashboard/chat-formatted value was pasted into the
# shell (for example: [https://api.voyplan.in](https://api.voyplan.in)). A bad
# backend URL is compiled into the Flutter bundle and otherwise makes every
# API-backed feature fail after an apparently successful Pages deployment.
if [[ ! "$BACKEND_URL" =~ ^https?://[^[:space:][:punct:]] ]]; then
  echo "Invalid BACKEND_URL: $BACKEND_URL" >&2
  echo "Use a plain URL such as https://api.voyplan.in" >&2
  exit 1
fi

# Ensure Flutter is available (Cloudflare Pages build images do not have Flutter pre-installed)
if ! command -v flutter &> /dev/null; then
  echo "Flutter not found in environment. Installing Flutter stable..."
  FLUTTER_DIR="$HOME/flutter"
  if [ ! -d "$FLUTTER_DIR" ]; then
    git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
  export PATH="$FLUTTER_DIR/bin:$PATH"
  flutter --version
fi

cd "$ROOT_DIR/mobile"
flutter pub get

BUILD_ARGS=(
  --release
  --base-href "/app/"
  "--dart-define=APP_ENV=$APP_ENV"
  "--dart-define=BACKEND_URL=$BACKEND_URL"
)

# MAPBOX_TOKEN is a public client token. It is optional here because the app
# retains its client-safe fallback for local builds; CI should provide a
# URL-restricted token through the Cloudflare/GitHub secret configuration.
if [[ -n "${MAPBOX_TOKEN:-}" ]]; then
  BUILD_ARGS+=("--dart-define=MAPBOX_TOKEN=$MAPBOX_TOKEN")
fi

flutter build web "${BUILD_ARGS[@]}"

# Reorganize mobile/build/web so that:
# 1. Root index.html is the high-performance static landing page
# 2. /app/ contains the Flutter Web SPA
BUILD_DIR="$ROOT_DIR/mobile/build/web"
TEMP_FLUTTER="$ROOT_DIR/mobile/build/web_flutter"

mkdir -p "$TEMP_FLUTTER"
cp -R "$BUILD_DIR/"* "$TEMP_FLUTTER/"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/app"

cp -R "$TEMP_FLUTTER/"* "$BUILD_DIR/app/"
rm -rf "$TEMP_FLUTTER"

cp "$ROOT_DIR/web/index.html" "$BUILD_DIR/index.html"
cp "$ROOT_DIR/mobile/web/favicon"* "$BUILD_DIR/" 2>/dev/null || true
cp "$ROOT_DIR/mobile/web/apple-touch-icon.png" "$BUILD_DIR/" 2>/dev/null || true
cp "$ROOT_DIR/cloudflare/_headers" "$BUILD_DIR/_headers"
cp "$ROOT_DIR/cloudflare/_redirects" "$BUILD_DIR/_redirects"

echo "Cloudflare Pages deployment payload ready: $BUILD_DIR"
echo "Root landing page: $BUILD_DIR/index.html"
echo "Flutter Web app: $BUILD_DIR/app/index.html"
