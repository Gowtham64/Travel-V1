#!/usr/bin/env bash
set -euo pipefail

# Backward-compatible entry point for web releases. It now prepares the
# Flutter build for Cloudflare Pages and never writes to gh-pages. Set
# DEPLOY_CLOUDFLARE=1 to publish explicitly with Wrangler.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$ROOT_DIR/scripts/build_cloudflare_pages.sh"

if [[ "${DEPLOY_CLOUDFLARE:-0}" != "1" ]]; then
  echo "Build complete. To deploy, set DEPLOY_CLOUDFLARE=1 and provide:"
  echo "  CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_PROJECT_NAME"
  exit 0
fi

: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required for deployment}"
: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID is required for deployment}"
: "${CLOUDFLARE_PROJECT_NAME:?CLOUDFLARE_PROJECT_NAME is required for deployment}"

if command -v wrangler >/dev/null 2>&1; then
  wrangler pages deploy "$ROOT_DIR/mobile/build/web" --project-name "$CLOUDFLARE_PROJECT_NAME"
else
  npx --yes wrangler pages deploy "$ROOT_DIR/mobile/build/web" --project-name "$CLOUDFLARE_PROJECT_NAME"
fi
