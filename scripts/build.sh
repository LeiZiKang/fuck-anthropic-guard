#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/scripts/toolchain.sh"
mode="${CCW_BUILD_MODE:-preview}"
[[ "$mode" == preview || "$mode" == host ]] || { echo 'Use preview or host' >&2; exit 2; }
out="${CCW_OUTPUT_ROOT:-$root/dist/guard}"
"$CCW_PYTHON" - "$root" "$out" <<'PY'
from pathlib import Path
import sys
assert Path(sys.argv[2]).resolve().is_relative_to(Path(sys.argv[1]).resolve()/'dist'), 'Output must stay in project dist'
PY
sdk="${CCW_SDK_PATH:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk}"
[[ -d "$sdk" ]] || sdk="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$out/cache"
common=( "$root/Sources/Localization.swift" "$root/Sources/FilterProtocol.swift" "$root/Sources/RouteRequirements.swift" "$root/Sources/PolicyEvidence.swift" "$root/Sources/ProcessAncestry.swift" "$root/Guard/Shared/ProcessIdentity.swift" "$root/Guard/Shared/ProbeModel.swift" "$root/Guard/Shared/GuardianTimer.swift" )
if [[ "$mode" == preview ]]; then
 app="$out/Claude Connection Watcher Preview.app"; binary=CCWPreview; definition=(-D CCW_PREVIEW); sources=()
else
 app="$out/Claude Connection Watcher.app"; binary=ClaudeConnectionWatcher; definition=(); sources=( "$root/Guard/Shared/RuntimeIdentity.swift" "$root/Sources/CommandRunner.swift" "$root/Sources/ProcessInventory.swift" "$root/Sources/LocalSurgeAuditor.swift" "$root/Sources/FilterController.swift" "$root/Sources/ProxyTransportConfiguration.swift" "$root/Guard/App/GuardProbe.swift" )
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$root/Resources/Watcher.icns" "$app/Contents/Resources/Watcher.icns"
[[ ! -f "$root/docs/UserGuide.html" ]] || cp "$root/docs/UserGuide.html" "$app/Contents/Resources/UserGuide.html"
if [[ "$mode" == preview ]]; then cp "$root/Preview/Info.plist" "$app/Contents/Info.plist"
else "$CCW_PYTHON" "$root/scripts/mach_service_metadata.py" --host "$root/Info.plist" --host-output "$app/Contents/Info.plist"; fi
archs="${CCW_ARCHITECTURES:-$(uname -m)}"; bins=(); filterbins=()
for arch in $archs; do
 [[ "$arch" == arm64 || "$arch" == x86_64 ]] || exit 2
 mkdir -p "$out/$arch"
 xcrun clang -target "$arch-apple-macosx14.0" -isysroot "$sdk" -c "$root/NetworkFilter/Sources/AuditToken.c" -o "$out/$arch/AuditToken.o"
 bridge=(); if [[ "$mode" == host ]]; then bridge=(-import-objc-header "$root/NetworkFilter/Sources/AuditToken.h" "$out/$arch/AuditToken.o" -lbsm); fi
 nice -n 10 xcrun swiftc -swift-version 5 -file-prefix-map "$root"=WatcherSource -debug-prefix-map "$root"=WatcherSource -target "$arch-apple-macosx14.0" -sdk "$sdk" -module-cache-path "$out/cache" -framework AppKit ${definition[@]+"${definition[@]}"} ${bridge[@]+"${bridge[@]}"} "${common[@]}" ${sources[@]+"${sources[@]}"} "$root/Guard/Tests/GuardTests.swift" "$root/Guard/App/main.swift" -o "$out/$arch/$binary"
 bins+=("$out/$arch/$binary")
 if [[ "$mode" == host ]]; then
  nice -n 10 xcrun swiftc -swift-version 5 -file-prefix-map "$root"=WatcherSource -debug-prefix-map "$root"=WatcherSource -target "$arch-apple-macosx14.0" -sdk "$sdk" -module-cache-path "$out/cache" -module-name ClaudeConnectionFilter -framework NetworkExtension -framework Security -import-objc-header "$root/NetworkFilter/Sources/AuditToken.h" "$out/$arch/AuditToken.o" -lbsm "${common[@]}" "$root/Guard/Shared/RuntimeIdentity.swift" "$root/NetworkFilter/Sources/main.swift" -o "$out/$arch/ClaudeConnectionFilter"
  filterbins+=("$out/$arch/ClaudeConnectionFilter")
 fi
done
xcrun lipo -create "${bins[@]}" -output "$app/Contents/MacOS/$binary"
if [[ "$mode" == host ]]; then
 ext="$app/Contents/Library/SystemExtensions/com.leizikang.claude-connection-watcher.filter.systemextension"
 mkdir -p "$ext/Contents/MacOS"
 xcrun lipo -create "${filterbins[@]}" -output "$ext/Contents/MacOS/ClaudeConnectionFilter"
 "$CCW_PYTHON" "$root/scripts/mach_service_metadata.py" --host "$root/Info.plist" --host-output "$out/HostMetadata.plist" --provider-template "$root/NetworkFilter/Info.plist" --provider-output "$ext/Contents/Info.plist"
 if [[ -n "${CCW_SIGN_IDENTITY:-}" ]]; then
  : "${CCW_HOST_PROFILE:?}" "${CCW_FILTER_PROFILE:?}"
  "$CCW_PYTHON" "$root/scripts/check_filter_profile.py" "$CCW_HOST_PROFILE" com.leizikang.claude-connection-watcher
  "$CCW_PYTHON" "$root/scripts/check_filter_profile.py" "$CCW_FILTER_PROFILE" com.leizikang.claude-connection-watcher.filter
  cp "$CCW_HOST_PROFILE" "$app/Contents/embedded.provisionprofile"; cp "$CCW_FILTER_PROFILE" "$ext/Contents/embedded.provisionprofile"
  codesign --force --options runtime --timestamp --entitlements "$root/NetworkFilter/Filter.entitlements" --sign "$CCW_SIGN_IDENTITY" "$ext"
  codesign --force --options runtime --timestamp --entitlements "$root/NetworkFilter/Host.entitlements" --sign "$CCW_SIGN_IDENTITY" "$app"
 else codesign --force --sign - --timestamp=none "$ext"; codesign --force --sign - --timestamp=none "$app"; fi
else codesign --force --sign - --timestamp=none "$app"; fi
codesign --verify --all-architectures --deep --strict "$app"
echo "Built $mode (not installed): $app"
