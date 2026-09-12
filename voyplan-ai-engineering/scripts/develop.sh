#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[DEVELOP SCRIPT] Invoking Developer Agent..."
python3 -m agents.developer.agent
