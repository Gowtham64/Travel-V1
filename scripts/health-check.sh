#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# VoyPlan Service Health & Readiness Probe
# Inspects live HTTP response, latency, and database readiness of the API.
# ==============================================================================

BASE_URL="${1:-https://api.voyplan.in}"
echo "==> Probing VoyPlan API at: $BASE_URL"

# Strip trailing slash if present
BASE_URL="${BASE_URL%/}"

HEALTH_URL="$BASE_URL/health"
READY_URL="$BASE_URL/ready"

echo "---------------------------------------------------------"
echo "1. Checking Health Probe: $HEALTH_URL"

HEALTH_RESP=$(curl -s -w "\n%{http_code}\n%{time_total}" "$HEALTH_URL" || true)
HTTP_CODE=$(echo "$HEALTH_RESP" | tail -n 2 | head -n 1)
TIME_TOTAL=$(echo "$HEALTH_RESP" | tail -n 1)
BODY=$(echo "$HEALTH_RESP" | sed '$d' | sed '$d')

echo "HTTP Status Code: $HTTP_CODE (Latency: ${TIME_TOTAL}s)"

if [ "$HTTP_CODE" = "200" ]; then
  echo "✅ Health probe PASSED: $BODY"
elif [ "$HTTP_CODE" = "503" ]; then
  echo "❌ Worker readiness is degraded (HTTP 503): $BODY"
  echo "   Check Cloudflare Worker logs, bindings, and upstream provider credentials."
else
  echo "❌ Health probe returned unexpected status: $HTTP_CODE"
  echo "   Response body: $BODY"
fi

echo "---------------------------------------------------------"
echo "2. Checking Readiness Probe: $READY_URL"

READY_RESP=$(curl -s -w "\n%{http_code}\n%{time_total}" "$READY_URL" || true)
READY_CODE=$(echo "$READY_RESP" | tail -n 2 | head -n 1)
READY_TIME=$(echo "$READY_RESP" | tail -n 1)
READY_BODY=$(echo "$READY_RESP" | sed '$d' | sed '$d')

echo "HTTP Status Code: $READY_CODE (Latency: ${READY_TIME}s)"

if [ "$READY_CODE" = "200" ]; then
  echo "✅ Readiness probe PASSED: $READY_BODY"
elif [ "$READY_CODE" = "503" ]; then
  echo "⚠️  Readiness probe returned 503:"
  echo "   $READY_BODY"
else
  echo "❌ Readiness probe returned HTTP $READY_CODE:"
  echo "   $READY_BODY"
fi

echo "---------------------------------------------------------"
if [ "$HTTP_CODE" = "200" ] && [ "$READY_CODE" = "200" ]; then
  echo "🚀 Service is 100% HEALTHY and READY."
  exit 0
else
  echo "ℹ️  Health or readiness checks did not return 200 (Result: Health=$HTTP_CODE, Ready=$READY_CODE)."
  exit 1
fi
