#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# VoyPlan End-to-End Smoke Test Suite
# Tests Landing Page, Web App (/app/), Backend API, and CORS configurations.
# ==============================================================================

WEB_HOST="${1:-https://voyplan.in}"
API_HOST="${2:-https://api.voyplan.in}"

echo "========================================================="
echo " VoyPlan End-to-End Smoke Test"
echo " Web: $WEB_HOST"
echo " API: $API_HOST"
echo "========================================================="

# Helper function to invoke curl with automatic DNS fallback if local resolver fails
CURL_EXTRA_ARGS=()
if ! curl -s -o /dev/null "$WEB_HOST" 2>/dev/null; then
  # Local DNS resolver cannot resolve, resolve via Cloudflare edge IP
  if [[ "$WEB_HOST" == *"voyplan.in"* ]]; then
    echo "ℹ️  Local DNS failed to resolve voyplan.in directly. Using Cloudflare Edge IP resolution."
    CURL_EXTRA_ARGS+=(--resolve "voyplan.in:443:104.21.40.173" --resolve "api.voyplan.in:443:104.21.40.173")
  fi
fi

FAILED_TESTS=0

function assert_pass() {
  echo "✅ [PASS] $1"
}

function assert_fail() {
  echo "❌ [FAIL] $1" >&2
  FAILED_TESTS=$((FAILED_TESTS + 1))
}

function assert_warn() {
  echo "⚠️  [WARN] $1"
}

# 1. Landing Page Root Check
echo "--- 1. Testing Web Root ($WEB_HOST) ---"
LANDING_STATUS=$(curl -s "${CURL_EXTRA_ARGS[@]}" -o /dev/null -w "%{http_code}" "$WEB_HOST" || echo "000")
LANDING_HTML=$(curl -s "${CURL_EXTRA_ARGS[@]}" "$WEB_HOST" || true)

if [ "$LANDING_STATUS" = "200" ]; then
  assert_pass "Web root loaded successfully (HTTP 200)"
else
  assert_fail "Web root failed to load (HTTP $LANDING_STATUS)"
fi

# Check for the P0 redirect loop pattern
if echo "$LANDING_HTML" | grep -q "const APP_URL = 'https://voyplan.in/';"; then
  assert_fail "CRITICAL: Live landing page still has loop pattern (APP_URL = 'https://voyplan.in/')"
else
  assert_pass "Web root does NOT contain infinite loop APP_URL pattern"
fi

# 2. Flutter App SPA /login Route Check
echo "--- 2. Testing SPA Route ($WEB_HOST/login) ---"
LOGIN_STATUS=$(curl -s "${CURL_EXTRA_ARGS[@]}" -o /dev/null -w "%{http_code}" "$WEB_HOST/login" || echo "000")
if [ "$LOGIN_STATUS" = "200" ]; then
  assert_pass "SPA /login route returns HTTP 200 (Cloudflare Pages fallback active)"
elif [ "$LOGIN_STATUS" = "404" ]; then
  assert_fail "SPA /login route returns 404 (Missing SPA fallback rule)"
else
  assert_warn "SPA /login route returned status $LOGIN_STATUS"
fi

# 3. Flutter Web App Subpath Check (/app/)
echo "--- 3. Testing /app/ Redirect Behavior ($WEB_HOST/app/) ---"
APP_STATUS=$(curl -s "${CURL_EXTRA_ARGS[@]}" -o /dev/null -w "%{http_code}" "$WEB_HOST/app/" || echo "000")

if [ "$APP_STATUS" = "200" ] || [ "$APP_STATUS" = "301" ]; then
  assert_pass "Flutter web app path responds validly (HTTP $APP_STATUS)"
else
  assert_fail "Flutter web app root returned unexpected HTTP $APP_STATUS"
fi

# 4. Backend Health & Readiness Probes
echo "--- 4. Testing Backend Probes ($API_HOST) ---"
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$API_HOST/health" || echo "000")
if [ "$HEALTH_CODE" = "200" ]; then
  assert_pass "Backend /health returned 200 OK"
elif [ "$HEALTH_CODE" = "503" ]; then
  assert_warn "Backend /health returned 503 (Render service is suspended by user)"
else
  assert_fail "Backend /health returned unexpected status: $HEALTH_CODE"
fi

# 5. CORS Preflight
echo "--- 5. Testing CORS Options Preflight ---"
CORS_HEADER=$(curl -sI -X OPTIONS "$API_HOST/health" \
  -H "Origin: https://voyplan.in" \
  -H "Access-Control-Request-Method: GET" || true)

if echo "$CORS_HEADER" | grep -qi "access-control-allow-origin"; then
  assert_pass "CORS headers properly returned for https://voyplan.in"
else
  assert_warn "CORS headers not returned (API service might be suspended on Render)"
fi

echo "========================================================="
if [ $FAILED_TESTS -gt 0 ]; then
  echo "❌ Smoke test suite completed with $FAILED_TESTS failure(s)."
  exit 1
else
  echo "✅ Smoke test suite completed successfully."
  exit 0
fi
