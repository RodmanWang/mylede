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

fail() {
    echo "错误：$*" >&2
    exit 1
}

[[ -f "$TOPDIR/Makefile" ]] || fail "LEDE 源码目录不存在：$TOPDIR"
[[ -f "$TOPDIR/feeds/luci/luci.mk" ]] || fail "找不到 feeds/luci/luci.mk；请先执行 feeds update/install。"
[[ -f "$TOPDIR/$PACKAGE_PATH/Makefile" ]] || fail "找不到 $PACKAGE_PATH/Makefile；请先建立插件软链接。"
[[ -f "$MINISIGN_SRC/Makefile" ]] || fail "找不到 minisign 包定义：$MINISIGN_SRC/Makefile"

cd "$TOPDIR"

# Register the bundled minisign package before Kconfig scans package metadata.
mkdir -p package/lean
if [[ -L "$MINISIGN_PATH" ]]; then
    [[ "$(readlink -f "$MINISIGN_PATH")" == "$(readlink -f "$MINISIGN_SRC")" ]] || fail "$MINISIGN_PATH 已指向其他位置：$(readlink -f "$MINISIGN_PATH")"
elif [[ -e "$MINISIGN_PATH" ]]; then
    fail "$MINISIGN_PATH 已存在且不是指向仓库 minisign 目录的软链接。"
else
    ln -s "$MINISIGN_SRC" "$MINISIGN_PATH"
fi

echo "========== 单独编译 luci-app-myupdate =========="
echo "源码：$TOPDIR/$PACKAGE_PATH"
echo "minisign：$TOPDIR/$MINISIGN_PATH"
echo "输出：$OUTPUT_DIR"

if [[ ! -f "$TOPDIR/.config" ]]; then
    echo "未找到 .config，先生成默认配置（非交互模式）..."
    make defconfig V=s
fi

# Select both packages as modules; defconfig will resolve their dependencies.
for package_config in CONFIG_PACKAGE_minisign "$PACKAGE_CONFIG"; do
    sed -i \
        -e "/^${package_config}=/d" \
        -e "/^# ${package_config} is not set$/d" \
        .config
    printf '%s=m\n' "$package_config" >> .config
done

# Minisign uses libsodium's scrypt API, which LEDE's default minimal
# configuration disables. Keep the full API enabled for this dependency.
sed -i \
    -e '/^CONFIG_LIBSODIUM_MINIMAL=/d' \
    -e '/^# CONFIG_LIBSODIUM_MINIMAL is not set$/d' \
    .config
printf '%s\n' '# CONFIG_LIBSODIUM_MINIMAL is not set' >> .config

make defconfig V=s

grep -qx 'CONFIG_PACKAGE_minisign=m' .config || fail "无法启用 minisign；请检查 libsodium 包定义及 feeds."
grep -qx '# CONFIG_LIBSODIUM_MINIMAL is not set' .config || fail "无法关闭 libsodium minimal 模式；Minisign 需要 scrypt API。"
grep -qx "${PACKAGE_CONFIG}=m" .config || fail "无法启用 luci-app-myupdate；请检查包定义和依赖。"
echo "已确认配置："
grep -E '^CONFIG_PACKAGE_(minisign|luci-app-myupdate)=m$' .config

make tools/install V=s -j2
make toolchain/install V=s -j2

# Rebuild libsodium without its minimal feature set before compiling Minisign.
LIBSODIUM_PATH="package/feeds/packages/libsodium"
[[ -f "$TOPDIR/$LIBSODIUM_PATH/Makefile" ]] || fail "找不到 libsodium 包定义：$LIBSODIUM_PATH/Makefile"
make "$LIBSODIUM_PATH/clean" V=s
make "$LIBSODIUM_PATH/compile" V=s -j1

make "$MINISIGN_PATH/clean" V=s
make "$MINISIGN_PATH/compile" V=s -j1
make "$PACKAGE_PATH/clean" V=s
make "$PACKAGE_PATH/compile" V=s -j1

# Export the complete runtime dependency set alongside the three MyUpdate
# packages. Users can then install the local IPKs without relying on a matching
# package feed being configured on the target router.
required_package_patterns=(
    'luci-app-myupdate_*.ipk'
    'luci-i18n-myupdate-zh-cn_*.ipk'
    'minisign_*.ipk'
    'libsodium_*.ipk'
    'coreutils_*.ipk'
    'coreutils-sha256sum_*.ipk'
)

packages=()
for pattern in "${required_package_patterns[@]}"; do
    mapfile -t matches < <(find "$TOPDIR/bin/packages" -type f -name "$pattern" -print | sort)
    (("${#matches[@]}" > 0)) || fail "缺少运行依赖包：$pattern；请检查 feeds 和编译日志。"
    packages+=("${matches[@]}")
done

mkdir -p "$OUTPUT_DIR"
for package in "${packages[@]}"; do
    cp -f "$package" "$OUTPUT_DIR/"
    echo "已生成：$OUTPUT_DIR/$(basename "$package")"
done

echo "========== MyUpdate 独立 IPK 编译完成 =========="
