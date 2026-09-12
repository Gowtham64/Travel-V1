#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
echo "[RESEARCH SCRIPT] Invoking R&D Agent..."
python3 -m agents.researcher.agent "${1:-123}" "${2:-Fix AI Planner Random Locations}" "${3:-Destination: Tirumala}"
