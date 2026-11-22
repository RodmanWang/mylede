#!/usr/bin/env bash
set -Eeuo pipefail
trap 'status=$?; echo "错误：环境检查在第 ${LINENO} 行执行失败（退出码：${status}）。" >&2; exit "$status"' ERR

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
SMARTDNS_SRC="${SMARTDNS_SRC:-/home/ubuntu/smartdns}"
LUCI_SRC="${LUCI_SRC:-/home/ubuntu/luci-app-smartdns}"
MYUPDATE_SRC="${MYUPDATE_SRC:-/home/ubuntu/luci-app-myupdate}"
MINISIGN_SRC="${MINISIGN_SRC:-$REPO_ROOT/minisign}"
DL_SRC="${DL_SRC:-/home/ubuntu/dl}"
FILES_SRC="${FILES_SRC:-/home/ubuntu/files}"

echo "========== 1/6 检查目录并确认本地软链接 =========="
[[ -f "$TOPDIR/Makefile" ]] || { echo "错误：LEDE 目录不存在：$TOPDIR" >&2; exit 1; }

ensure_link() {
  local link="$1" target="$2" required="$3"
  if [[ ! -d "$target" ]]; then
    if [[ "$required" == yes ]]; then echo "错误：必需的本地源码目录不存在：$target" >&2; exit 1; fi
    echo "可选目录不存在，跳过：$target"; return 0
  fi
  mkdir -p "$(dirname "$link")"
  if [[ -L "$link" ]]; then
    [[ "$(readlink -f "$link")" == "$(readlink -f "$target")" ]] || { echo "错误：软链接指向错误位置：$link" >&2; exit 1; }
    echo "软链接正确：$link"; return 0
  fi
  [[ ! -e "$link" ]] || { echo "错误：目标路径已存在且不是软链接：$link" >&2; exit 1; }
  ln -s "$target" "$link"
  echo "已创建软链接：$link -> $target"
}

ensure_link "$TOPDIR/package/smartdns" "$SMARTDNS_SRC" yes
ensure_link "$TOPDIR/package/lean/luci-app-smartdns" "$LUCI_SRC" yes
ensure_link "$TOPDIR/package/lean/luci-app-myupdate" "$MYUPDATE_SRC" yes
ensure_link "$TOPDIR/package/lean/minisign" "$MINISIGN_SRC" yes
ensure_link "$TOPDIR/dl" "$DL_SRC" no
ensure_link "$TOPDIR/files" "$FILES_SRC" no

echo "========== 1/6 环境检查完成 =========="
