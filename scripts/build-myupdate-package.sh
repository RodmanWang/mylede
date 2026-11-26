#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
PACKAGE_PATH="package/lean/luci-app-myupdate"
MINISIGN_PATH="package/lean/minisign"
MINISIGN_SRC="${MINISIGN_SRC:-$REPO_ROOT/minisign}"
OUTPUT_DIR="${OUTPUT_DIR:-$TOPDIR/myupdate-ipk}"
PACKAGE_CONFIG="CONFIG_PACKAGE_luci-app-myupdate"

# Keep the app and generated translation package on the exact same build stamp.
MYUPDATE_PACKAGE_VERSION="${MYUPDATE_PACKAGE_VERSION:-$(date -u +%y%m%d%H%M%S)}"
[[ "$MYUPDATE_PACKAGE_VERSION" =~ ^[0-9]{12}$ ]] || {
    echo "错误：MYUPDATE_PACKAGE_VERSION 必须是 12 位 UTC 时间戳（YYMMDDHHMMSS）。" >&2
    exit 1
}
export MYUPDATE_PACKAGE_VERSION
echo "MyUpdate 软件包版本：$MYUPDATE_PACKAGE_VERSION（UTC）"

fail() {