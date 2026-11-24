#!/bin/sh
set -eu
fail() {
	echo "MyUpdate 分区容量检查失败：$1" >&2
	logger -t myupdate "分区容量检查失败：$1" 2>/dev/null || true
	exit 1
}
[ "$#" -eq 2 ] || fail '参数错误'
KERNEL_REQUIRED="$1"
ROOTFS_REQUIRED="$2"
case "$KERNEL_REQUIRED:$ROOTFS_REQUIRED" in
	*[!0-9:]*|:*|*:) fail '固件分区需求不是有效的正整数 MiB';;
esac
[ "$KERNEL_REQUIRED" -gt 0 ] && [ "$ROOTFS_REQUIRED" -gt 0 ] || fail '固件分区需求必须大于零'
ROOT="\${MYUPDATE_ROOT:-}"
MOUNTS="\${ROOT}/proc/mounts"
[ -r "$MOUNTS" ] || fail '无法读取 /proc/mounts，不能确认当前根分区设备'
# LEDE x86 combined EFI images use partition 1 for boot/kernel and partition 2 for rootfs.
ROOT_DEVICE="$(awk '$2 == "/rom" { print $1; exit }' "$MOUNTS")"
case "$ROOT_DEVICE" in
	/dev/*) ;;
	*) fail "无法从 /rom 挂载记录识别根分区设备：\${ROOT_DEVICE:-缺失}";;
esac
DEVICE_PATH="\${ROOT}$ROOT_DEVICE"
DEVICE_REAL="$(readlink -f "$DEVICE_PATH" 2>/dev/null || true)"
[ -n "$DEVICE_REAL" ] || fail "无法解析根分区设备：$ROOT_DEVICE"
ROOT_PART="\${DEVICE_REAL##*/}"
ROOT_SYSFS="$(readlink -f "\${ROOT}/sys/class/block/$ROOT_PART" 2>/dev/null || true)"
[ -n "$ROOT_SYSFS" ] && [ -f "$ROOT_SYSFS/partition" ] || fail '根分区没有对应的 sysfs 分区信息'
ROOT_NUMBER="$(cat "$ROOT_SYSFS/partition")"
[ "$ROOT_NUMBER" = 2 ] || fail "当前 /rom 位于分区 $ROOT_NUMBER，而 MyLEDE x86 EFI 镜像要求根文件系统位于分区 2"
DISK_SYSFS="$(dirname "$ROOT_SYSFS")"
KERNEL_SYSFS=''
for candidate in "$DISK_SYSFS"/*; do
	[ -f "$candidate/partition" ] || continue
	if [ "$(cat "$candidate/partition")" = 1 ]; then
		KERNEL_SYSFS="$candidate"
		break
	fi
done
[ -n "$KERNEL_SYSFS" ] || fail '无法在根分区所属磁盘上找到内核/启动分区 1'
KERNEL_SECTORS="$(cat "$KERNEL_SYSFS/size" 2>/dev/null || true)"
ROOTFS_SECTORS="$(cat "$ROOT_SYSFS/size" 2>/dev/null || true)"
case "$KERNEL_SECTORS:$ROOTFS_SECTORS" in
	*[!0-9:]*|:*|*:) fail '无法读取当前内核或根文件系统分区的扇区数';;
esac
# sysfs reports 512-byte sectors; one MiB is exactly 2048 sectors.
KERNEL_REQUIRED_SECTORS=$((KERNEL_REQUIRED * 2048))
ROOTFS_REQUIRED_SECTORS=$((ROOTFS_REQUIRED * 2048))
KERNEL_ACTUAL_MIB=$((KERNEL_SECTORS / 2048))
ROOTFS_ACTUAL_MIB=$((ROOTFS_SECTORS / 2048))
echo "当前分区容量：内核/启动分区 \${KERNEL_ACTUAL_MIB} MiB；根文件系统分区 \${ROOTFS_ACTUAL_MIB} MiB"
echo "目标固件需求：内核/启动分区 \${KERNEL_REQUIRED} MiB；根文件系统分区 \${ROOTFS_REQUIRED} MiB"
[ "$KERNEL_SECTORS" -ge "$KERNEL_REQUIRED_SECTORS" ] || fail "当前内核/启动分区仅 \${KERNEL_ACTUAL_MIB} MiB，小于目标固件要求的 \${KERNEL_REQUIRED} MiB"
[ "$ROOTFS_SECTORS" -ge "$ROOTFS_REQUIRED_SECTORS" ] || fail "当前根文件系统分区仅 \${ROOTFS_ACTUAL_MIB} MiB，小于目标固件要求的 \${ROOTFS_REQUIRED} MiB"
echo '分区容量检查通过：当前两个分区均不小于目标固件要求。'
