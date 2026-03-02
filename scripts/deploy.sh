#!/usr/bin/env bash
# Build + install in one step (preserves app data).
#
# Usage: ./scripts/deploy.sh [--wifi]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/build.sh"
echo ""
"$SCRIPT_DIR/install.sh" "${1:-}"
