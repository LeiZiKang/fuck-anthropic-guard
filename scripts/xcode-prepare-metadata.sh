#!/bin/sh
# Generate build-only metadata using the same versioned Mach-service contract.
set -eu
role=${1:?host or provider required}
output=${2:?output plist required}
case "$role" in host|provider) ;; *) exit 2 ;; esac
if [ -n "${CCW_PYTHON:-}" ]; then python_bin=$CCW_PYTHON
elif [ -x /opt/homebrew/bin/python3 ]; then python_bin=/opt/homebrew/bin/python3
elif [ -x /usr/local/bin/python3 ]; then python_bin=/usr/local/bin/python3
else python_bin=/usr/bin/python3; fi
mkdir -p "$(dirname "$output")"
if [ "$role" = host ]; then
  "$python_bin" "$SRCROOT/scripts/mach_service_metadata.py" --host "$SRCROOT/Info.plist" --host-output "$output"
  "$python_bin" "$SRCROOT/scripts/check_system_extension_metadata.py" "$output" --host-only
else
  "$python_bin" "$SRCROOT/scripts/mach_service_metadata.py" --host "$SRCROOT/Info.plist" --host-output "$DERIVED_FILE_DIR/HostMetadata.plist" \
    --provider-template "$SRCROOT/NetworkFilter/Info.plist" --provider-output "$output"
  "$python_bin" "$SRCROOT/scripts/check_system_extension_metadata.py" "$output" --host "$DERIVED_FILE_DIR/HostMetadata.plist"
fi
