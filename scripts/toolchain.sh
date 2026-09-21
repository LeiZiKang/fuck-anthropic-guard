#!/usr/bin/env bash
# A process-local choice of the already installed standalone CLT. Never accepts
# an Xcode license and never changes the global xcode-select preference.
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
if [ -z "${CCW_PYTHON:-}" ]; then
  if [ -x /opt/homebrew/bin/python3 ]; then export CCW_PYTHON=/opt/homebrew/bin/python3
  else export CCW_PYTHON=python3; fi
fi

ccw_validate_build11_output() {
  "$CCW_PYTHON" - "$project_root" "$output_root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path(sys.argv[2]).resolve()
base = root / 'dist' / 'build11'
if output != base and base not in output.parents:
    raise SystemExit('Build 11 output must stay inside this project dist/build11; frozen build 10 is protected.')
PY
}
