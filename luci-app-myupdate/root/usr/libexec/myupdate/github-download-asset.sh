#!/bin/sh
set -eu
umask 077
fail() { logger -t myupdate "$1"; exit 1; }
[ "$#" -ge 5 ] && [ "$#" -le 6 ] || exit 2
OWNER="$1"; REPO="$2"; VISIBILITY="$3"; ASSET_ID="$4"; OUTPUT="$5"; EXPECTED_SIZE="${6:-0}"
case "$EXPECTED_SIZE" in ''|*[!0-9]*) exit 2;; esac
case "$VISIBILITY" in public|private) ;; *) exit 2;; esac
case "$OWNER" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac
case "$REPO" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac
case "$ASSET_ID" in ''|*[!0-9]*) exit 2;; esac
case "$OUTPUT" in /tmp/myupdate/*) ;; *) exit 2;; esac
mkdir -p /tmp/myupdate; chmod 700 /tmp/myupdate
T="$(mktemp -d /tmp/myupdate/asset.XXXXXX)"; trap 'rm -rf "$T"' EXIT HUP INT TERM
CFG="$T/curl.conf"
printf 'header = "Accept: application/octet-stream"\nheader = "X-GitHub-Api-Version: 2022-11-28"\n' > "$CFG"
if [ "$VISIBILITY" = private ]; then
	[ -s /etc/myupdate/token ] || fail '私有仓库未配置 Token'
	TOKEN="$(cat /etc/myupdate/token)"
	case "$TOKEN" in ''|*[!A-Za-z0-9_]* ) fail 'Token 格式无效';; esac
	printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" >> "$CFG"
	unset TOKEN
fi
chmod 600 "$CFG"
URL="https://api.github.com/repos/$OWNER/$REPO/releases/assets/$ASSET_ID"
CODE="$(curl -sS --connect-timeout 15 --max-time 180 --proto '=https' --tlsv1.2 --config "$CFG" -D "$T/headers" -o "$T/body" -w '%{http_code}' "$URL")" || fail '资产 API 请求失败'
case "$CODE" in
200) mv "$T/body" "$T/file";;
301|302|303|307|308)
	LOC="$(awk 'tolower($1)=="location:" { sub(/\r$/, "", $2); v=$2 } END { print v }' "$T/headers")"
	case "$LOC" in https://release-assets.githubusercontent.com/*|https://objects.githubusercontent.com/*|https://github.com/*) ;; *) fail '资产重定向地址不受信任';; esac
	if [ "$EXPECTED_SIZE" -gt 0 ]; then
		curl -sS --connect-timeout 15 --max-time 1800 --proto '=https' --tlsv1.2 -o "$T/file" "$LOC" &
		CURL_PID=$!
		while kill -0 "$CURL_PID" 2>/dev/null; do
			DOWNLOADED="$(wc -c < "$T/file" 2>/dev/null | tr -d ' ' || echo 0)"
			case "$DOWNLOADED" in ''|*[!0-9]*) DOWNLOADED=0;; esac
			PERCENT=$((DOWNLOADED * 100 / EXPECTED_SIZE))
			[ "$PERCENT" -le 99 ] || PERCENT=99
			PROGRESS_TMP="/tmp/myupdate/progress.tmp"
			printf '{"percent":%s,"downloaded_bytes":%s,"total_bytes":%s}\\n' "$PERCENT" "$DOWNLOADED" "$EXPECTED_SIZE" > "$PROGRESS_TMP"
			chmod 600 "$PROGRESS_TMP"; mv "$PROGRESS_TMP" /tmp/myupdate/progress.json
			sleep 1
		done
		wait "$CURL_PID" || fail '资产下载失败'
		printf '{"percent":100,"downloaded_bytes":%s,"total_bytes":%s}\\n' "$EXPECTED_SIZE" "$EXPECTED_SIZE" > /tmp/myupdate/progress.json
		chmod 600 /tmp/myupdate/progress.json
	else
		R="$(curl -sS --connect-timeout 15 --max-time 1800 --proto '=https' --tlsv1.2 -o "$T/file" -w '%{http_code}' "$LOC")" || fail '资产下载失败'
		[ "$R" = 200 ] || fail "资产下载 HTTP $R"
	fi;;
*) fail "GitHub 资产 API HTTP $CODE";;
esac
[ -s "$T/file" ] || fail '下载文件为空'
mkdir -p "$(dirname "$OUTPUT")"; mv "$T/file" "$OUTPUT"; chmod 600 "$OUTPUT"
