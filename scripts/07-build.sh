#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; echo "错误：编译在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
KERNEL_PARTSIZE="${KERNEL_PARTSIZE:-256}"
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-4096}"

# Pin one compact UTC timestamp for the whole firmware build. The LuCI app
# and its generated zh-cn translation package must carry the same version.
MYUPDATE_PACKAGE_VERSION="${MYUPDATE_PACKAGE_VERSION:-$(date -u +%y%m%d%H%M%S)}"
[[ "$MYUPDATE_PACKAGE_VERSION" =~ ^[0-9]{12}$ ]] || {
    echo "错误：MYUPDATE_PACKAGE_VERSION 必须是 12 位 UTC 时间戳（YYMMDDHHMMSS）。" >&2
    exit 1
}
export MYUPDATE_PACKAGE_VERSION
echo "MyUpdate 软件包版本：$MYUPDATE_PACKAGE_VERSION（UTC）"

for entry in "KERNEL_PARTSIZE=$KERNEL_PARTSIZE" "ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE"; do