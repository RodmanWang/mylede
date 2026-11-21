
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; echo "错误：编译在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"

cd "$TOPDIR"

echo "========== 7/7 清理临时配置并重新生成 x86_64 编译配置 =========="

# 04-configure.sh 已经完成：
# 1. 内核分区大小设置
# 2. 根文件系统分区大小设置
# 3. 自动选择最高可用内核版本
# 4. 同步 KERNEL_PATCHVER
# 5. 同步 KERNEL_TESTING_PATCHVER
# 6. 系统默认软件包及其他系统定制
#
# 此处不再重复覆盖上述设置。

rm -rf -- "$TOPDIR/tmp"
rm -f -- "$TOPDIR/.config"

echo "========== 执行 make defconfig =========="

make defconfig

[[ -s "$TOPDIR/.config" ]] || {
    echo "错误：make defconfig 未生成 .config" >&2
    exit 1
}

echo "========== 检查最终内核和分区配置 =========="

python3 - "$TOPDIR/.config" <<'PY'
from pathlib import Path
import re
import sys

config = Path(sys.argv[1])
data = config.read_text(encoding="utf-8")

def get_value(key):
    matches = re.findall(
        rf"^{re.escape(key)}=(.*)$",
        data,
        re.MULTILINE
    )

    if len(matches) != 1:
        raise SystemExit(
            f"错误：无法从 .config 中唯一读取 {key}"
        )

    return matches[0].strip()

kernel_size = get_value("CONFIG_TARGET_KERNEL_PARTSIZE")
rootfs_size = get_value("CONFIG_TARGET_ROOTFS_PARTSIZE")

if kernel_size != "256":
    raise SystemExit(
        f"错误：内核分区大小不是 256 MB，当前值：{kernel_size}"
    )

if rootfs_size != "4096":
    raise SystemExit(
        f"错误：根文件系统分区大小不是 4096 MB，当前值：{rootfs_size}"
    )

print(f"内核分区：{kernel_size} MB")
print(f"根文件系统分区：{rootfs_size} MB")
print("分区配置检查通过。")
PY

echo "========== 配置检查通过，开始完整固件编译 =========="

make V=s -j"$(nproc)"

echo "========== 固件编译完成 =========="
echo "固件输出目录：$TOPDIR/bin/targets/x86/64"
