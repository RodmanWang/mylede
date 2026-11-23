#!/bin/sh
set -eu
umask 077
fail() { logger -t myupdate "$1"; return 1; }
[ "$#" -eq 4 ] || exit 2
OWNER="$1"; REPO="$2"; VISIBILITY="$3"; CHANNEL="$4"
case "$OWNER" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac
case "$REPO" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac
case "$VISIBILITY" in public|private) ;; *) exit 2;; esac
case "$CHANNEL" in stable) ;; *) exit 2;; esac
mkdir -p /tmp/myupdate; chmod 700 /tmp/myupdate
TMP="$(mktemp -d /tmp/myupdate/api.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
URL="https://api.github.com/repos/$OWNER/$REPO/releases/latest"
CFG="$TMP/curl.conf"
printf 'header = "Accept: application/vnd.github+json"\nheader = "X-GitHub-Api-Version: 2022-11-28"\n' > "$CFG"
if [ "$VISIBILITY" = private ]; then
	[ -s /etc/myupdate/token ] || { fail '私有仓库未配置 GitHub Token'; exit 1; }
	TOKEN="$(cat /etc/myupdate/token)"
	case "$TOKEN" in ''|*[!A-Za-z0-9_]* ) fail 'Token 格式无效'; exit 1;; esac
	printf 'header = "Authorization: Bearer %s"\n' "$TOKEN" >> "$CFG"
	unset TOKEN
fi
chmod 600 "$CFG"
CODE="$(curl --silent --show-error --connect-timeout 15 --max-time 60 --proto '=https' --tlsv1.2 --config "$CFG" -o "$TMP/release.json" -w '%{http_code}' "$URL")" || { fail 'GitHub API 请求失败'; exit 1; }
[ "$CODE" = 200 ] || { fail "GitHub API 返回 HTTP $CODE"; exit 1; }
[ -s "$TMP/release.json" ] || { fail 'Release 响应为空'; exit 1; }
cp "$TMP/release.json" /tmp/myupdate/release.json
: > /tmp/myupdate/selected-tag
chmod 600 /tmp/myupdate/release.json /tmp/myupdate/selected-tag
