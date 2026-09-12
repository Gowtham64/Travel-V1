#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[RELEASE SCRIPT] Invoking Release Agent..."
python3 -m agents.release.agent "$@"
