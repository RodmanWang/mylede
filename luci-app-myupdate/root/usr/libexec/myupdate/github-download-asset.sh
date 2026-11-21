#!/bin/sh
set -eu
umask 077
fail() { logger -t myupdate "$1"; exit 1; }
[ "$#" -eq 5 ] || exit 2
OWNER="$1"; REPO="$2"; VISIBILITY="$3"; ASSET_ID="$4"; OUTPUT="$5"
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
	R="$(curl -sS --connect-timeout 15 --max-time 1800 --proto '=https' --tlsv1.2 -o "$T/file" -w '%{http_code}' "$LOC")" || fail '资产下载失败'
	[ "$R" = 200 ] || fail "资产下载 HTTP $R";;
*) fail "GitHub 资产 API HTTP $CODE";;
esac
[ -s "$T/file" ] || fail '下载文件为空'
mkdir -p "$(dirname "$OUTPUT")"; mv "$T/file" "$OUTPUT"; chmod 600 "$OUTPUT"
