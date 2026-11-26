#!/bin/sh
set -eu
umask 077
API_ERROR=/tmp/myupdate/api-error
fail() {
	logger -t myupdate "$1"
	printf '%s\n' "$1" > "$API_ERROR"
	return 1
}
[ "$#" -eq 4 ] || exit 2
OWNER="$1"; REPO="$2"; VISIBILITY="$3"; CHANNEL="$4"
case "$OWNER" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac
case "$REPO" in ''|*[!A-Za-z0-9_.-]*) exit 2;; esac
case "$VISIBILITY" in public|private) ;; *) exit 2;; esac
case "$CHANNEL" in stable) ;; *) exit 2;; esac
mkdir -p /tmp/myupdate; chmod 700 /tmp/myupdate
: > "$API_ERROR"
chmod 600 "$API_ERROR"
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
CODE="$(curl --silent --show-error --connect-timeout 10 --max-time 35 --proto '=https' --tlsv1.2 --config "$CFG" -o "$TMP/release.json" -w '%{http_code}' "$URL")" || { fail 'GitHub API 请求失败，请检查网络连接或 DNS'; exit 1; }
case "$CODE" in
	200) ;;
	401) fail 'GitHub Token 无效或已过期，请检查 Token。'; exit 1;;
	403) fail 'GitHub API 拒绝访问：Token 权限不足，或已触发 API 速率限制。'; exit 1;;
	404) fail 'GitHub 仓库不存在，或当前 Token 无权访问该私有仓库。'; exit 1;;
	*) fail "GitHub API 返回 HTTP $CODE"; exit 1;;
esac
[ -s "$TMP/release.json" ] || { fail 'Release 响应为空'; exit 1; }
cp "$TMP/release.json" /tmp/myupdate/release.json
: > /tmp/myupdate/selected-tag
chmod 600 /tmp/myupdate/release.json /tmp/myupdate/selected-tag
