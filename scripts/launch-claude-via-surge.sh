#!/usr/bin/env bash
set -euo pipefail
kind="${1:-}"; port="${2:-6154}"
[[ "$port" =~ ^[1-9][0-9]{3,4}$ ]] && (( 10#$port >= 1024 && 10#$port <= 65535 )) || { echo 'Invalid port' >&2; exit 2; }
case "$port" in 6152|6153|6162|6163) echo 'Use the dedicated Surge port' >&2; exit 2;; esac
case "$kind" in
 desktop)
  binary='/Applications/Claude.app/Contents/MacOS/Claude'
  /usr/bin/pgrep -x Claude >/dev/null && { echo 'Quit existing Desktop first; no process was stopped.' >&2; exit 2; }
  requirement='anchor apple generic and identifier "com.anthropic.claudefordesktop" and certificate leaf[subject.OU] = "Q6L2SF6YDW"';;
 cli)
  binary="$(command -v claude)"
  requirement='anchor apple generic and identifier "com.anthropic.claude-code" and certificate leaf[subject.OU] = "Q6L2SF6YDW"';;
 *) echo 'Usage: launch-claude-via-surge.sh desktop|cli [dedicated-port]' >&2; exit 2;;
esac
[[ "$binary" == /* ]] || { echo "Native executable must resolve to an absolute path" >&2; exit 2; }
/usr/bin/codesign --verify --strict -R "$requirement" "$binary"
proxy="http://127.0.0.1:$port"
export HTTP_PROXY="$proxy" HTTPS_PROXY="$proxy" ALL_PROXY="$proxy" http_proxy="$proxy" https_proxy="$proxy" all_proxy="$proxy"
export NO_PROXY='' no_proxy='' NODE_USE_ENV_PROXY=1
if [[ "$kind" == desktop ]]; then
 /usr/bin/nohup "$binary" --proxy-server="$proxy" '--proxy-bypass-list=<-loopback>' --disable-quic >/dev/null 2>&1 &
else exec "$binary"; fi
