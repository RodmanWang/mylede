#!/bin/sh
set -eu
umask 077
fail() { logger -t myupdate "Manifest 校验失败：$1"; exit 1; }
[ "$#" -eq 4 ] || exit 2
MANIFEST="$1"; SIG="$2"; TAG="$3"; CHANNEL="$4"
ROOT="${MYUPDATE_ROOT:-}"
[ -s "$MANIFEST" ] && [ -s "$SIG" ] || fail 'Manifest 或签名文件缺失'
KEY="$(uci -q get myupdate.main.minisign_public_key || true)"
[ -n "$KEY" ] || fail '未配置 minisign 公钥'
command -v minisign >/dev/null 2>&1 || fail '系统未安装 minisign'
minisign -Vm "$MANIFEST" -x "$SIG" -P "$KEY" -q || fail '签名无效'
get() { jsonfilter -i "$MANIFEST" -e "$1" 2>/dev/null || true; }
[ "$(get '@.schema_version')" = 2 ] || fail 'Manifest 缺少分区容量元数据或版本不受支持；请使用包含分区布局信息的新固件发布'
VERSION="$(get '@.version')"; MTAG="$(get '@.tag')"; MCHANNEL="$(get '@.channel')"
ASSET="$(get '@.image.asset')"; HASH="$(get '@.image.sha256')"; SIZE="$(get '@.image.size')"
TARGET="$(get '@.compatibility.target')"; SUBTARGET="$(get '@.compatibility.subtarget')"; ARCH="$(get '@.compatibility.arch')"
KERNEL_PARTSIZE="$(get '@.partition_layout.kernel_partsize_mib')"
ROOTFS_PARTSIZE="$(get '@.partition_layout.rootfs_partsize_mib')"
USES_BOOT_PART="$(get '@.partition_layout.uses_boot_part')"
[ -n "$VERSION" ] && [ "$MTAG" = "$TAG" ] && [ "$MCHANNEL" = "$CHANNEL" ] || fail '版本、Tag 或通道不匹配'
case "$VERSION" in *[!0-9.]*|'') fail '版本号格式非法';; esac
case "$ASSET" in openwrt-x86-64-generic-squashfs-combined-efi.img.gz) ;; *) fail '固件不是本插件支持的 x86_64 squashfs UEFI 镜像';; esac
case "$HASH" in *[!A-Fa-f0-9]*|'') fail 'SHA256 格式非法';; esac
[ "${#HASH}" -eq 64 ] || fail 'SHA256 长度错误'
case "$SIZE" in ''|*[!0-9]*) fail '固件大小字段非法';; esac
[ "$SIZE" -gt 0 ] || fail '固件大小为零'
. "${ROOT}/etc/openwrt_release"
LOCAL_TARGET="${DISTRIB_TARGET%%/*}"; LOCAL_SUBTARGET="${DISTRIB_TARGET#*/}"
[ "$TARGET" = "$LOCAL_TARGET" ] && [ "$SUBTARGET" = "$LOCAL_SUBTARGET" ] && [ "$ARCH" = "$DISTRIB_ARCH" ] || fail '当前设备 target/subtarget/架构不匹配'
[ "$TARGET" = x86 ] && [ "$SUBTARGET" = 64 ] || fail '当前插件仅支持 x86/64'
case "$KERNEL_PARTSIZE:$ROOTFS_PARTSIZE" in
	*[!0-9:]*|:*|*:) fail 'Manifest 中的内核或根文件系统分区大小无效';;
esac
[ "$KERNEL_PARTSIZE" -gt 0 ] && [ "$ROOTFS_PARTSIZE" -gt 0 ] || fail 'Manifest 中的分区大小必须大于零'
[ "$USES_BOOT_PART" = true ] || fail '目标固件未声明 x86 boot-part 布局，拒绝自动升级'
[ -d "${ROOT}/sys/firmware/efi" ] || fail '当前系统不是 UEFI 启动，拒绝刷入 EFI 镜像'
ROOTFS="$(ubus call system board 2>/dev/null | jsonfilter -e '@.rootfs_type' 2>/dev/null || true)"
[ "$ROOTFS" = squashfs ] || fail '当前系统不是 squashfs 根文件系统，与目标镜像不匹配'
POLICY="$(get '@.compatibility.device_policy')"
[ "$POLICY" = target ] || fail '当前只接受经过构建流程确认的 target 兼容策略'
mkdir -p "${ROOT}/tmp/myupdate"
printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$VERSION" "$MTAG" "$ASSET" "$HASH" "$SIZE" "$KERNEL_PARTSIZE" "$ROOTFS_PARTSIZE" > "${ROOT}/tmp/myupdate/verified-manifest.txt"
chmod 600 "${ROOT}/tmp/myupdate/verified-manifest.txt"
