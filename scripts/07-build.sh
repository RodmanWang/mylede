#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; echo "错误：编译在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
KERNEL_PARTSIZE="${KERNEL_PARTSIZE:-256}"
ROOTFS_PARTSIZE="${ROOTFS_PARTSIZE:-4096}"

for entry in "KERNEL_PARTSIZE=$KERNEL_PARTSIZE" "ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE"; do
    key="${entry%%=*}"
    value="${entry#*=}"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
        echo "错误：$key 必须是大于 0 的整数 MB，当前值：$value" >&2
        exit 1
    }
done
cd "$TOPDIR"

echo "========== 清理临时配置并重新生成 x86_64 编译配置 =========="

# bd.sh 已经按顺序执行完 feeds 和源码配置；这里仅负责正式固件构建前
# 清理旧临时配置、生成 .config、应用 Actions 输入的分区大小并启动完整编译。
rm -rf -- "$TOPDIR/tmp"
rm -f -- "$TOPDIR/.config"

make defconfig
[[ -s "$TOPDIR/.config" ]] || {
    echo '错误：make defconfig 未生成 .config' >&2
    exit 1
}

# 按 Actions 输入设置实际分区大小。软件包选择已经由 04-configure.sh 写入
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

# minisign 0.11 uses libsodium's legacy scrypt API. The packages feed
# defaults LIBSODIUM_MINIMAL to y, which hides that API from sodium.h.
minimal_enabled = 'CONFIG_LIBSODIUM_MINIMAL=y'
minimal_disabled = '# CONFIG_LIBSODIUM_MINIMAL is not set'
config_lines = data.splitlines()
for index, line in enumerate(config_lines):
    if line.startswith('CONFIG_LIBSODIUM_MINIMAL=') or line == minimal_disabled:
        config_lines[index] = minimal_disabled
        break
else:
    config_lines.append(minimal_disabled)
data = '\n'.join(config_lines) + '\n'

config.write_text(data, encoding='utf-8')
print(f'已设置内核分区：{kernel} MB')
print(f'已设置根文件系统分区：{rootfs} MB')
print('已关闭 libsodium 最小化构建，以保留 minisign 所需的 scrypt API。')
PY

# 让 Kconfig 规范化配置，再检查固定值及 libsodium API 配置是否被接受。
make defconfig

for entry in \
    "CONFIG_TARGET_KERNEL_PARTSIZE=$KERNEL_PARTSIZE" \
    "CONFIG_TARGET_ROOTFS_PARTSIZE=$ROOTFS_PARTSIZE"; do
    grep -Fxq "$entry" .config || {
        echo "错误：当前 LEDE 配置未接受固定配置：$entry" >&2
        exit 1
    }
done

if ! grep -Fxq '# CONFIG_LIBSODIUM_MINIMAL is not set' .config; then
    echo '::error::libsodium 最小化构建仍处于启用状态，minisign 所需的 scrypt API 不可用。'
    exit 1
fi

echo "分区配置检查通过：Kernel=${KERNEL_PARTSIZE} MB，Rootfs=${ROOTFS_PARTSIZE} MB。"

# CMake packages use LEDE's staged host Ninja. A restored toolchain cache can
# contain stale Ninja build stamps while the actual host binary is missing.
# Rebuild and install Ninja before package compilation when either copy is absent.
NINJA_BIN="$TOPDIR/staging_dir/host/bin/ninja"
NINJA_BUILD_BIN="$(find "$TOPDIR/build_dir/host" -mindepth 2 -maxdepth 2 -type f -name ninja -perm /111 -print -quit 2>/dev/null || true)"
if [[ ! -x "$NINJA_BIN" || -z "$NINJA_BUILD_BIN" ]]; then
    echo '检测到 LEDE 主机 Ninja 工具缓存不完整，正在清理并重新构建。'
    make tools/ninja/clean
    make tools/ninja/install V=s
fi

if [[ ! -x "$NINJA_BIN" ]]; then
    echo "::error::LEDE 主机 Ninja 工具安装失败：$NINJA_BIN 不存在或不可执行。"
    exit 1
fi
echo "LEDE 主机 Ninja 版本：$("$NINJA_BIN" --version)"

echo '========== 配置及主机工具检查通过，开始完整固件编译 =========='
make V=s -j"$(nproc)"

echo '========== 固件编译完成 =========='
echo "固件输出目录：$TOPDIR/bin/targets/x86/64"
