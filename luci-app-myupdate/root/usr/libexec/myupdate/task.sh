#!/bin/sh
set -eu
umask 077
ACTION="${1:-}"
case "$ACTION" in check|download|upgrade) ;; *) exit 2;; esac
R=/tmp/myupdate
mkdir -p "$R"; chmod 700 "$R"
LOCK="$R/task.lock"
if ! mkdir "$LOCK" 2>/dev/null; then exit 1; fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT HUP INT TERM
STATUS="$R/status.json"
. /etc/openwrt_release
CFG() { uci -q get "myupdate.main.$1" 2>/dev/null || printf '%s' "$2"; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
write_status() {
	STATE="$1"; MSG="$2"; UPDATE="${3:-false}"; READY="${4:-false}"; VERIFIED="${5:-false}"; CURRENT="${6:-${CURRENT_VERSION:-}}"; LATEST="${7:-${LATEST:-}}"
	TMP="$R/status.tmp"
	printf '{"state":"%s","message":"%s","current_version":"%s","latest_version":"%s","update_available":%s,"image_ready":%s,"image_verified":%s,"busy":%s,"updated_at":"%s"}\n' \
		"$(json_escape "$STATE")" "$(json_escape "$MSG")" "$(json_escape "$CURRENT")" "$(json_escape "$LATEST")" \
		"$UPDATE" "$READY" "$VERIFIED" "$(case "$STATE" in running|downloading|upgrading) echo true;; *) echo false;; esac)" \
		"$(date -Iseconds 2>/dev/null || date)" > "$TMP"
	chmod 600 "$TMP"; mv "$TMP" "$STATUS"
}
VIS="$(CFG repo_visibility public)"; CHANNEL=stable
REPO_URL="$(CFG repo_url '')"
if [ -n "$REPO_URL" ]; then
	case "$REPO_URL" in
		https://github.com/*) REPO_PATH="${REPO_URL#https://github.com/}";;
		*) write_status error 'GitHub 仓库地址无效，请填写 https://github.com/所有者/仓库名' false false false; exit 1;;
	esac
	REPO_PATH="${REPO_PATH%/}"
	REPO_PATH="${REPO_PATH%.git}"
	case "$REPO_PATH" in
		*/*) OWNER="${REPO_PATH%%/*}"; REPO="${REPO_PATH#*/}";;
		*) write_status error 'GitHub 仓库地址必须包含所有者和仓库名' false false false; exit 1;;
	esac
	case "$REPO" in ''|*/*) write_status error 'GitHub 仓库地址路径无效' false false false; exit 1;; esac
	case "$OWNER" in ''|*[!A-Za-z0-9_.-]*) write_status error 'GitHub 仓库所有者格式无效' false false false; exit 1;; esac
	case "$REPO" in *[!A-Za-z0-9_.-]*) write_status error 'GitHub 仓库名称格式无效' false false false; exit 1;; esac
else
	# Backward compatibility with configurations created by older MyUpdate versions.
	OWNER="$(CFG repo_owner '')"
	REPO="$(CFG repo_name '')"
fi
CURRENT_VERSION="$(cat /etc/myupdate/build-version 2>/dev/null || true)"
[ -n "$CURRENT_VERSION" ] || CURRENT_VERSION="${DISTRIB_RELEASE:-unknown}"
[ -n "$OWNER" ] && [ -n "$REPO" ] || { write_status error '请先填写有效的 GitHub 仓库完整地址' false false false; exit 1; }
write_status running '正在查询 GitHub Release' false false false
/usr/libexec/myupdate/github-api.sh "$OWNER" "$REPO" "$VIS" "$CHANNEL" || { write_status error '查询 GitHub Release 失败' false false false; exit 1; }
REL="$R/release.json"
TAG="$(jsonfilter -i "$REL" -e '@.tag_name' 2>/dev/null || true)"
[ -n "$TAG" ] || { write_status error 'Release 中没有可用版本' false false false; exit 1; }
# The Release tag is an opaque identifier. The signed manifest is the
# authoritative source of the numeric firmware version.
UPDATE=false
ASSET_NAMES="$(jsonfilter -i "$REL" -e '@.assets[*].name' 2>/dev/null || true)"
ASSET_IDS="$(jsonfilter -i "$REL" -e '@.assets[*].id' 2>/dev/null || true)"
NAMES_FILE="$R/names"; IDS_FILE="$R/ids"
printf '%s\n' "$ASSET_NAMES" > "$NAMES_FILE"; printf '%s\n' "$ASSET_IDS" > "$IDS_FILE"
MANIFEST_ID=''; SIGNATURE_ID=''
while IFS= read -r name && IFS= read -r id <&3; do
	case "$id" in ''|*[!0-9]*) continue;; esac
	[ "$name" = manifest.json ] && MANIFEST_ID="$id"
	[ "$name" = manifest.minisig ] && SIGNATURE_ID="$id"
done < "$NAMES_FILE" 3< "$IDS_FILE"
[ -n "$MANIFEST_ID" ] && [ -n "$SIGNATURE_ID" ] || { write_status error 'Release 缺少 manifest.json 或 manifest.minisig' "$UPDATE" false false; exit 1; }
/usr/libexec/myupdate/github-download-asset.sh "$OWNER" "$REPO" "$VIS" "$MANIFEST_ID" "$R/manifest.json" || { write_status error 'Manifest 下载失败' "$UPDATE" false false; exit 1; }
/usr/libexec/myupdate/github-download-asset.sh "$OWNER" "$REPO" "$VIS" "$SIGNATURE_ID" "$R/manifest.minisig" || { write_status error 'Manifest 签名下载失败' "$UPDATE" false false; exit 1; }
/usr/libexec/myupdate/verify-manifest.sh "$R/manifest.json" "$R/manifest.minisig" "$TAG" "$CHANNEL" || { write_status error 'Manifest 验签或设备兼容性检查失败' "$UPDATE" false false; exit 1; }
VERSION="$(sed -n '1p' "$R/verified-manifest.txt")"
ASSET="$(sed -n '3p' "$R/verified-manifest.txt")"
HASH="$(sed -n '4p' "$R/verified-manifest.txt")"
SIZE="$(sed -n '5p' "$R/verified-manifest.txt")"
LATEST="$VERSION"
# Compare numeric dot-separated components, including the run number and attempt.
if [ "$CURRENT_VERSION" = unknown ] || [ "$CURRENT_VERSION" = "${DISTRIB_RELEASE:-}" ]; then
	UPDATE=true
elif [ "$LATEST" != "$CURRENT_VERSION" ]; then
	if awk -v a="$LATEST" -v b="$CURRENT_VERSION" 'BEGIN {
		na=split(a,x,"."); nb=split(b,y,"."); n=(na>nb?na:nb);
		for(i=1;i<=n;i++){ ax=x[i]+0; by=y[i]+0; if(ax>by) exit 0; if(ax<by) exit 1; }
		exit 1;
	}'; then
		UPDATE=true
	elif [ "$(CFG allow_downgrade 0)" = 1 ]; then
		UPDATE=true
	fi
fi
ASSET_ID=''
while IFS= read -r name && IFS= read -r id <&3; do [ "$name" = "$ASSET" ] && ASSET_ID="$id"; done < "$NAMES_FILE" 3< "$IDS_FILE"
[ -n "$ASSET_ID" ] || { write_status error 'Manifest 指定的固件资产不存在' "$UPDATE" false false; exit 1; }
if [ "$ACTION" = check ]; then
	if [ "$UPDATE" = true ]; then write_status checked "发现可用更新 $TAG；Manifest 签名和设备兼容性已验证" true false false; else write_status current "当前已是最新版本 $CURRENT_VERSION" false false false; fi
	exit 0
fi
[ "$UPDATE" = true ] || { write_status current '当前已经是最新版本，不需要重复刷写' false false false; exit 1; }
if [ "$ACTION" = download ]; then
	write_status downloading "正在下载 $ASSET" true false false
	# Avoid filling tmpfs; sysupgrade needs working space while validating and flashing.
	FREE_KB="$(df -Pk /tmp | awk 'NR==2 {print $4}')"
	NEED_KB=$(( (SIZE + 1023) / 1024 + 32768 ))
	[ "$FREE_KB" -ge "$NEED_KB" ] || { write_status error ' /tmp 可用空间不足，无法安全下载和升级' true false false; exit 1; }
	/usr/libexec/myupdate/github-download-asset.sh "$OWNER" "$REPO" "$VIS" "$ASSET_ID" "$R/firmware.bin" || { write_status error '固件下载失败' true false false; exit 1; }
	/usr/libexec/myupdate/verify-image.sh "$R/firmware.bin" "$HASH" "$SIZE" >/dev/null || { rm -f "$R/firmware.bin"; write_status error '固件大小或 SHA256 校验失败' true false false; exit 1; }
	printf '%s\n' "$ASSET" > "$R/image-name"; printf '%s\n' "$VERSION" > "$R/image-version"
	chmod 600 "$R/image-name" "$R/image-version"
fi
if [ "$ACTION" = download ]; then
	write_status downloaded "版本 $VERSION 已下载，签名和 SHA256 校验通过；尚未刷写" true true true
	exit 0
fi
# Require the downloaded image to be re-verified immediately before handing it to sysupgrade.
[ -s "$R/firmware.bin" ] && [ "$(cat "$R/image-version" 2>/dev/null || true)" = "$VERSION" ] || { write_status error '没有当前版本的已验证固件，请重新下载' true false false; exit 1; }
/usr/libexec/myupdate/verify-image.sh "$R/firmware.bin" "$HASH" "$SIZE" >/dev/null || { write_status error '刷写前固件复验失败' true false false; exit 1; }
command -v sysupgrade >/dev/null 2>&1 || { write_status error '系统没有 sysupgrade 命令' true true true; exit 1; }
write_status running '正在执行 sysupgrade -T 镜像预检查' true true true
if ! sysupgrade -T "$R/firmware.bin"; then
	write_status error 'LEDE sysupgrade 镜像预检查失败，已取消刷写' true true true
	exit 1
fi
if ! /bin/sh /usr/libexec/myupdate/prepare-sysupgrade-backup.sh; then
	write_status error '自定义文件保留路径准备失败，已取消刷写' true true true
	exit 1
fi
write_status upgrading '预检查通过，正在执行保留系统配置及自定义文件的升级；设备将自动重启' true true true
sync
exec sysupgrade -v "$R/firmware.bin"
