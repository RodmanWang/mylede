#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; echo "错误：编译在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
KERNEL_PARTSIZE="256"
ROOTFS_PARTSIZE="4096"
cd "$TOPDIR"

echo "========== 清理临时配置并重新生成 x86_64 编译配置 =========="

# bd.sh 已经按顺序执行完 feeds 和源码配置；这里仅负责正式固件构建前
# 清理旧临时配置、生成 .config、固定分区大小并启动完整编译。
rm -rf -- "$TOPDIR/tmp"
rm -f -- "$TOPDIR/.config"

make defconfig
[[ -s "$TOPDIR/.config" ]] || {
    echo '错误：make defconfig 未生成 .config' >&2
    exit 1
}

# 固定分区大小。软件包选择已经由 04-configure.sh 写入
# target/linux/x86/Makefile 的 DEFAULT_PACKAGES，不在这里重复管理。
python3 - "$TOPDIR/.config" "$KERNEL_PARTSIZE" "$ROOTFS_PARTSIZE" <<'PY'
from pathlib import Path
import re
import sys

config = Path(sys.argv[1])
kernel, rootfs = (value.strip() for value in sys.argv[2:4])
updates = {
    'CONFIG_TARGET_KERNEL_PARTSIZE': kernel,
    'CONFIG_TARGET_ROOTFS_PARTSIZE': rootfs,
}
data = config.read_text(encoding='utf-8')

for key, value in updates.items():
    pattern = re.compile(rf'^(?:# )?{re.escape(key)}(?:=.*| is not set)$', re.M)
    replacement = f'{key}={value}'
    if pattern.search(data):
        data = pattern.sub(replacement, data, count=1)
    else:
        data += f'\n{replacement}\n'

config.write_text(data, encoding='utf-8')
print(f'已固定内核分区：{kernel} MB')
print(f'已固定根文件系统分区：{rootfs} MB')
PY

# 让 Kconfig 规范化配置，再检查固定值是否被接受。
make defconfig

for entry in \
    'CONFIG_TARGET_KERNEL_PARTSIZE=256' \
    'CONFIG_TARGET_ROOTFS_PARTSIZE=4096'; do
    grep -Fxq "$entry" .config || {
        echo "错误：当前 LEDE 配置未接受固定配置：$entry" >&2
        exit 1
    }
done

echo '========== 配置检查通过，开始完整固件编译 =========='
make V=s -j"$(nproc)"

echo '========== 固件编译完成 =========='
echo "固件输出目录：$TOPDIR/bin/targets/x86/64"
