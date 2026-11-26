#!/usr/bin/env bash
set -Eeuo pipefail

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
MAKE_BIN="${MAKE:-make}"
HOST_CMAKE="$TOPDIR/staging_dir/host/bin/cmake"

[[ -f "$TOPDIR/Makefile" ]] || {
  echo "::error::LEDE 顶层 Makefile 不存在：$TOPDIR/Makefile"
  exit 1
}
[[ -f "$TOPDIR/tools/cmake/Makefile" ]] || {
  echo "::error::当前 LEDE 源码没有 tools/cmake/Makefile，无法确认 CMake 主机工具构建入口。"
  exit 1
}

echo "先独立构建 LEDE CMake 主机工具，避免其与 dwarves 并行竞争。"
"$MAKE_BIN" -C "$TOPDIR" V=1 tools/cmake/compile

[[ -x "$HOST_CMAKE" ]] || {
  echo "::error::CMake 构建目标完成后仍未生成可执行文件：$HOST_CMAKE"
  exit 1
}

# --system-information forces CMake to load its module tree. --version alone
# would not detect the original 'Could not find CMAKE_ROOT' failure.
if ! "$HOST_CMAKE" --system-information >/dev/null; then
  echo "::error::LEDE 主机 CMake 无法加载其模块目录，拒绝启动并行工具链构建。"
  exit 1
fi

echo "LEDE 主机 CMake 已构建，且模块目录检查通过。"
