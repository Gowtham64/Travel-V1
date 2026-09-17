#!/usr/bin/env bash
set -euo pipefail

# Build the Flutter source once for Cloudflare Pages. The output directory is
# mobile/build/web, Flutter's actual production build directory; committed
# app/, web/app/, and public/app/ copies are not deployment sources of truth.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/mobile/build/web"
APP_ENV="${APP_ENV:-production}"
BACKEND_URL="${BACKEND_URL:-https://api.voyplan.in}"

cd "$ROOT_DIR/mobile"
flutter pub get

BUILD_ARGS=(
  --release
  --base-href "/"
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

cp "$ROOT_DIR/cloudflare/_headers" "$BUILD_DIR/_headers"
cp "$ROOT_DIR/cloudflare/_redirects" "$BUILD_DIR/_redirects"

echo "Cloudflare Pages build ready: $BUILD_DIR"
echo "APP_ENV=$APP_ENV"
echo "BACKEND_URL=$BACKEND_URL"
