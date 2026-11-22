#!/usr/bin/env bash
set -Eeuo pipefail

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
PACKAGE_PATH="package/lean/luci-app-myupdate"
OUTPUT_DIR="${OUTPUT_DIR:-$TOPDIR/myupdate-ipk}"

fail() {
    echo "错误：$*" >&2
    exit 1
}

[[ -f "$TOPDIR/Makefile" ]] || fail "LEDE 源码目录不存在：$TOPDIR"
[[ -f "$TOPDIR/feeds/luci/luci.mk" ]] || fail "找不到 feeds/luci/luci.mk；请先执行 feeds update/install。"
[[ -f "$TOPDIR/$PACKAGE_PATH/Makefile" ]] || fail "找不到 $PACKAGE_PATH/Makefile；请先运行仓库的 scripts/01-check-env.sh 建立插件软链接。"

cd "$TOPDIR"

echo "========== 单独编译 luci-app-myupdate =========="
echo "源码：$TOPDIR/$PACKAGE_PATH"
echo "输出：$OUTPUT_DIR"

# A fresh LEDE checkout has no .config. Package targets depend on .config,
# and without it make may fall back to the interactive menuconfig target.
# Generate the default configuration non-interactively before package targets.
if [[ ! -f "$TOPDIR/.config" ]]; then
    echo "未找到 .config，先生成默认配置（非交互模式）..."
    make defconfig V=s
fi

# Buildroot exposes a direct per-package target. Do not call scripts/config:
# in some LEDE revisions scripts/config is a directory, not an executable.
# The explicit package target builds this package without selecting it for
# inclusion in a complete firmware image.
make "$PACKAGE_PATH/clean" V=s
make "$PACKAGE_PATH/compile" V=s -j1

mapfile -t packages < <(
    find "$TOPDIR/bin/packages" -type f \
        \( -name 'luci-app-myupdate_*.ipk' -o -name 'luci-i18n-myupdate-zh-cn_*.ipk' \) \
        -print | sort
)

(("${#packages[@]}" > 0)) || fail "编译命令已结束，但 bin/packages 中没有找到 MyUpdate IPK。请检查上方编译日志。"

mkdir -p "$OUTPUT_DIR"
for package in "${packages[@]}"; do
    cp -f "$package" "$OUTPUT_DIR/"
    echo "已生成：$OUTPUT_DIR/$(basename "$package")"
done

echo "========== MyUpdate 独立 IPK 编译完成 =========="
