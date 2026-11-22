#!/usr/bin/env bash
set -Eeuo pipefail

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
PACKAGE_PATH="package/lean/luci-app-myupdate"
OUTPUT_DIR="${OUTPUT_DIR:-$TOPDIR/myupdate-ipk}"
PACKAGE_CONFIG="CONFIG_PACKAGE_luci-app-myupdate"

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

# A fresh LEDE checkout has no .config. Generate it non-interactively.
if [[ ! -f "$TOPDIR/.config" ]]; then
    echo "未找到 .config，先生成默认配置（非交互模式）..."
    make defconfig V=s
fi

# A direct package target can silently do nothing when the package is not
# selected in .config. Select it as a module, preserving all other settings.
sed -i \
    -e "/^\${PACKAGE_CONFIG}=/d" \
    -e "/^# \${PACKAGE_CONFIG} is not set$/d" \
    .config
printf '%s=m\n' "$PACKAGE_CONFIG" >> .config
make defconfig V=s

grep -qx "${PACKAGE_CONFIG}=m" .config || fail "无法在 .config 中启用 luci-app-myupdate；请检查 feeds 和包定义。"
echo "已确认配置：$(grep -x "${PACKAGE_CONFIG}=m" .config)"

# A package-only build still needs the host tools and target toolchain.
# This does not build the complete firmware image.
make tools/install V=s -j2
make toolchain/install V=s -j2

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
