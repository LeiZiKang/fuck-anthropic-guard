#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
CCW_BUILD_MODE=preview bash "$root/scripts/build.sh"
"${CCW_OUTPUT_ROOT:-$root/dist/guard}/Claude Connection Watcher Preview.app/Contents/MacOS/CCWPreview" --self-test
python3 "$root/scripts/check_scope.py"
