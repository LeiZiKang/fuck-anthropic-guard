#!/bin/bash
# Runs only on an ephemeral GitHub-hosted macOS runner. Never executes the app.
set -euo pipefail
set +x
[[ "${GITHUB_REPOSITORY:-}" == LeiZiKang/fuck-anthropic-guard && "${GITHUB_REF:-}" == refs/heads/main && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || exit 2
for name in MACOS_CERTIFICATE_P12_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_HOST_PROFILE_BASE64 MACOS_FILTER_PROFILE_BASE64 APPLE_ID APPLE_APP_PASSWORD; do
 [[ -n "${!name:-}" ]] || { echo "Missing required secret: $name" >&2; exit 2; }
done
work="${RUNNER_TEMP:?}/guard-signing-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
state="$PWD/dist/ci-state"
mkdir -p "$work" "$state"
chmod 700 "$work"
keychain="$work/release.keychain-db"
cleanup() {
 security delete-keychain "$keychain" >/dev/null 2>&1 || true
 python3 - "$work" <<'PY'
import pathlib,shutil,sys
p=pathlib.Path(sys.argv[1]);assert p.name.startswith('guard-signing-');shutil.rmtree(p,ignore_errors=True)
PY
}
trap cleanup EXIT
python3 - "$work" <<'PY'
import base64,os,pathlib,secrets,sys
p=pathlib.Path(sys.argv[1])
for env,name in [('MACOS_CERTIFICATE_P12_BASE64','certificate.p12'),('MACOS_HOST_PROFILE_BASE64','host.provisionprofile'),('MACOS_FILTER_PROFILE_BASE64','filter.provisionprofile')]:
 data=base64.b64decode(os.environ[env],validate=True);(p/name).write_bytes(data);os.chmod(p/name,0o600)
(p/'keychain-password').write_text(secrets.token_urlsafe(40));os.chmod(p/'keychain-password',0o600)
PY
keychain_password=$(cat "$work/keychain-password")
printf '::add-mask::%s\n' "$keychain_password"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/certificate.p12" -P "$MACOS_CERTIFICATE_PASSWORD" -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null
identity=$(security find-identity -v -p codesigning "$keychain" | sed -nE '/Developer ID Application:.*\(Y355LMZA6C\)/s/.* ([A-F0-9]{40}) .*/\1/p')
[[ "$identity" =~ ^[A-F0-9]{40}$ ]] || { echo 'Expected exactly one matching Developer ID identity' >&2; exit 2; }
app="$state/fuck-anthropic guard.app"
if [[ -f "$state/notary-state.json" ]]; then
 python3 - "$state" <<'PY'
import hashlib,json,os,pathlib,sys
p=pathlib.Path(sys.argv[1]);s=json.loads((p/'notary-state.json').read_text());m=json.loads((p/'manifest.json').read_text())
assert s['source_commit']==m['source_commit']==os.environ['GITHUB_SHA']
assert hashlib.sha256((p/'notary-input.zip').read_bytes()).hexdigest()==s['input_sha256']
PY
 python3 scripts/ci/release.py extract --archive "$state/notary-input.zip" --directory "$state"
else
 python3 - <<'PY'
import hashlib,json,pathlib
p=pathlib.Path('dist/ci-build');m=json.loads((p/'manifest.json').read_text());assert hashlib.sha256((p/'unsigned.zip').read_bytes()).hexdigest()==m['unsigned_zip_sha256']
PY
 python3 scripts/ci/release.py extract --archive dist/ci-build/unsigned.zip --directory "$state"
 cp dist/ci-build/manifest.json "$state/manifest.json"
 ext="$app/Contents/Library/SystemExtensions/com.leizikang.claude-connection-watcher.filter.systemextension"
 python3 scripts/check_filter_profile.py "$work/host.provisionprofile" com.leizikang.claude-connection-watcher
 python3 scripts/check_filter_profile.py "$work/filter.provisionprofile" com.leizikang.claude-connection-watcher.filter
 cp "$work/host.provisionprofile" "$app/Contents/embedded.provisionprofile"
 cp "$work/filter.provisionprofile" "$ext/Contents/embedded.provisionprofile"
 codesign --force --options runtime --timestamp --keychain "$keychain" --entitlements NetworkFilter/Filter.entitlements --sign "$identity" "$ext"
 codesign --force --options runtime --timestamp --keychain "$keychain" --entitlements NetworkFilter/Host.entitlements --sign "$identity" "$app"
 codesign --verify --all-architectures --deep --strict "$app"
 ditto -c -k --keepParent --sequesterRsrc "$app" "$state/notary-input.zip"
 xcrun notarytool store-credentials guard-ci --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id Y355LMZA6C --keychain "$keychain" >/dev/null
 xcrun notarytool submit "$state/notary-input.zip" --keychain-profile guard-ci --keychain "$keychain" --output-format json > "$work/submit.json"
 python3 - "$work/submit.json" "$state" <<'PY'
import hashlib,json,os,pathlib,sys
p=pathlib.Path(sys.argv[2]);r=json.loads(pathlib.Path(sys.argv[1]).read_text());(p/'notary-state.json').write_text(json.dumps({'source_commit':os.environ['GITHUB_SHA'],'id':r['id'],'input_sha256':hashlib.sha256((p/'notary-input.zip').read_bytes()).hexdigest()},indent=2))
PY
fi
xcrun notarytool store-credentials guard-ci --apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id Y355LMZA6C --keychain "$keychain" >/dev/null
submission=$(python3 -c 'import json;print(json.load(open("dist/ci-state/notary-state.json"))["id"])')
# A timeout retains the submission and exact signed input for a failed-job rerun.
xcrun notarytool wait "$submission" --keychain-profile guard-ci --keychain "$keychain" --timeout 20m --output-format json > "$state/notary-result.json"
python3 - "$state/notary-result.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['status']=='Accepted','Notarization has not been accepted'
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
mkdir -p dist/ci-release
version=$(python3 -c 'import json;print(json.load(open("dist/ci-state/manifest.json"))["version"])')
archive="dist/ci-release/fuck-anthropic-guard-${version}.zip"
ditto -c -k --keepParent --sequesterRsrc "$app" "$archive"
python3 - "$archive" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.load(open('dist/ci-state/manifest.json'));s=json.load(open('dist/ci-state/notary-state.json'));m.update(zip_sha256=hashlib.sha256(p.read_bytes()).hexdigest(),notary_submission_id=s['id'],notarization_status='Accepted');(p.parent/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
PY
