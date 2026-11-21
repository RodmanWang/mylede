
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'status=$?; echo "错误：清理旧编译产物在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
DL_SRC="${DL_SRC:-/home/ubuntu/dl}"

echo "========== 6/7 清理旧的 SmartDNS 编译产物 =========="

for root in "$TOPDIR/build_dir" "$TOPDIR/staging_dir"; do
    [[ -d "$root" ]] || continue

    while IFS= read -r -d '' path; do
        echo "清理编译产物：$path"
        rm -rf -- "$path"
    done < <(
        find "$root" \
            \( -type d -o -type l \) \
            \( -name 'smartdns' \
               -o -name 'smartdns-*' \
               -o -name 'luci-app-smartdns' \
               -o -name 'luci-app-smartdns-*' \) \
            -prune -print0
    )
done

if [[ -d "$TOPDIR/bin" ]]; then
    find "$TOPDIR/bin" -type f \
        \( -name 'smartdns_*.ipk' \
           -o -name 'luci-app-smartdns_*.ipk' \) \
        -print -delete
fi

echo "========== 清理 dl 中旧的 SmartDNS / LuCI SmartDNS 下载文件 =========="

if [[ -d "$DL_SRC" ]]; then
    find "$DL_SRC" -maxdepth 1 -type f \
        \( -name 'smartdns*' -o -name 'luci-app-smartdns*' \) \
        -print -delete
else
    echo "提示：下载缓存目录不存在，跳过清理：$DL_SRC"
fi

echo "========== 6/7 旧编译产物清理完成 =========="
