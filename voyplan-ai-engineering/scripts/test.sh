#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[TEST SCRIPT] Invoking Testing Agent..."
python3 -m agents.tester.agent
