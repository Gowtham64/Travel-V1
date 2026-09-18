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

# 3. Check Flutter Production Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_CONFIG_FILE="$ROOT_DIR/mobile/lib/config/app_config.dart"

if [ -f "$APP_CONFIG_FILE" ]; then
  if grep -q "https://api.voyplan.in" "$APP_CONFIG_FILE"; then
    report_pass "mobile app_config.dart has the canonical production API URL"
  else
    report_error "mobile app_config.dart is missing the canonical production API URL"
  fi
else
  report_error "mobile app_config.dart is missing"
fi

# 4. Check Cloudflare Worker Configuration
WORKER_CONFIG="$ROOT_DIR/cloudflare-worker/wrangler.jsonc"
if [ -f "$WORKER_CONFIG" ]; then
  if grep -q '"name": "voyplan-api"' "$WORKER_CONFIG" && grep -q 'api.voyplan.in/\\*' "$WORKER_CONFIG"; then
    report_pass "Cloudflare Worker is configured for api.voyplan.in"
  else
    report_error "Cloudflare Worker configuration is missing the production name or route"
  fi
else
  report_error "cloudflare-worker/wrangler.jsonc is missing"
fi

# 5. Guard the canonical production delivery topology
PRODUCTION_WORKFLOW="$ROOT_DIR/.github/workflows/deploy-production.yml"
if [ -f "$PRODUCTION_WORKFLOW" ] && \
   grep -Fq 'branches: [main]' "$PRODUCTION_WORKFLOW" && \
   grep -Fq 'PAGES_PROJECT: voyplan' "$PRODUCTION_WORKFLOW" && \
   grep -Fq 'npx wrangler deploy' "$PRODUCTION_WORKFLOW" && \
   grep -Fq 'npx wrangler pages deploy' "$PRODUCTION_WORKFLOW"; then
  report_pass "the single production workflow deploys Worker then Pages from main"
else
  report_error "deploy-production.yml is missing the canonical Worker-to-Pages delivery path"
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
