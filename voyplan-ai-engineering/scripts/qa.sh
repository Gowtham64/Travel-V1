#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[QA SCRIPT] Invoking QA / Validation Agent..."
python3 -m agents.qa.agent
