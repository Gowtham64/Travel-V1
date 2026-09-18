#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# VoyPlan Environment Configuration Validator
# Prevents invalid, missing, or localhost configs from being deployed to prod.
# ==============================================================================

TARGET_ENV="${1:-${APP_ENV:-production}}"
echo "==> Validating VoyPlan environment configuration for: [$TARGET_ENV]"

ERRORS=0

function report_error() {
  echo "❌ [ERROR] $1" >&2
  ERRORS=$((ERRORS + 1))
}

function report_warn() {
  echo "⚠️  [WARN] $1"
}

function report_pass() {
  echo "✅ [PASS] $1"
}

# 1. Check BACKEND_URL
BACKEND_URL="${BACKEND_URL:-}"
if [ "$TARGET_ENV" = "production" ]; then
  if [ -z "$BACKEND_URL" ]; then
    BACKEND_URL="https://api.voyplan.in"
    report_pass "BACKEND_URL defaults to canonical production: $BACKEND_URL"
  else
    if [[ "$BACKEND_URL" =~ (localhost|127\.0\.0\.1|0\.0\.0\.0|10\.0\.2\.2) ]]; then
      report_error "Production BACKEND_URL cannot point to local host ($BACKEND_URL)"
    elif [[ ! "$BACKEND_URL" =~ ^https:// ]]; then
      report_error "Production BACKEND_URL must use HTTPS protocol ($BACKEND_URL)"
    else
      report_pass "Production BACKEND_URL is valid HTTPS ($BACKEND_URL)"
    fi
  fi
else
  report_pass "Non-production BACKEND_URL: ${BACKEND_URL:-default}"
fi

# 2. Check SUPABASE_URL & ANON_KEY
SUPABASE_URL="${SUPABASE_URL:-https://dtemayjpttktntooxraa.supabase.co}"
if [ "$TARGET_ENV" = "production" ]; then
  if [[ "$SUPABASE_URL" =~ (localhost|127\.0\.0\.1) ]]; then
    report_error "Production SUPABASE_URL cannot point to localhost ($SUPABASE_URL)"
  elif [[ ! "$SUPABASE_URL" =~ ^https://.*\.supabase\.co ]]; then
    report_warn "SUPABASE_URL ($SUPABASE_URL) does not match standard supabase.co domain"
  else
    report_pass "SUPABASE_URL points to valid cloud instance ($SUPABASE_URL)"
  fi
fi

# 3. Check Web Landing Index Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="$ROOT_DIR/web/index.html"

if [ -f "$INDEX_FILE" ]; then
  # Verify that APP_URL does NOT hardcode 'https://voyplan.in/' (which causes infinite loops)
  if grep -q "const APP_URL = 'https://voyplan.in/';" "$INDEX_FILE"; then
    report_error "web/index.html contains hardcoded APP_URL = 'https://voyplan.in/' which causes an infinite reload loop!"
  else
    report_pass "web/index.html APP_URL contains loop guard and dynamic resolution"
  fi

  # Verify guest links point to /app/ and not the root /
  if grep -q 'href="https://voyplan.in/?guest=true"' "$INDEX_FILE"; then
    report_error "web/index.html contains guest links pointing to root (href=\"https://voyplan.in/?guest=true\") instead of /app/"
  else
    report_pass "web/index.html guest links correctly point to /app/"
  fi
else
  report_warn "web/index.html not found at $INDEX_FILE"
fi

# 4. Check Mobile App Configuration
APP_CONFIG_FILE="$ROOT_DIR/mobile/lib/config/app_config.dart"
if [ -f "$APP_CONFIG_FILE" ]; then
  if grep -q 'static const String productionApiUrl =.*localhost' "$APP_CONFIG_FILE"; then
    report_error "mobile app_config.dart productionApiUrl contains localhost"
  else
    report_pass "mobile app_config.dart productionApiUrl is clean"
  fi
fi

# 5. Check Render Blueprint
RENDER_YAML="$ROOT_DIR/render.yaml"
if [ -f "$RENDER_YAML" ]; then
  if grep -q 'name: voyplan-backend' "$RENDER_YAML"; then
    report_pass "render.yaml declares voyplan-backend service"
  else
    report_error "render.yaml is missing voyplan-backend web service"
  fi
fi

# 6. Check Cloudflare Headers Security
CF_HEADERS="$ROOT_DIR/cloudflare/_headers"
if [ -f "$CF_HEADERS" ]; then
  if grep -q 'X-Frame-Options' "$CF_HEADERS" && grep -q 'X-Content-Type-Options' "$CF_HEADERS"; then
    report_pass "cloudflare/_headers contains security headers (X-Frame-Options, X-Content-Type-Options)"
  else
    report_warn "cloudflare/_headers is missing some recommended security headers"
  fi
fi

echo "---------------------------------------------------------"
if [ $ERRORS -gt 0 ]; then
  echo "❌ Environment validation FAILED with $ERRORS error(s)." >&2
  exit 1
else
  echo "✅ Environment validation PASSED for [$TARGET_ENV]."
  exit 0
fi
