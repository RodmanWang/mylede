#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/.github/ci/build-lede-cmake-host-tool.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

MOCK_BIN="$TMP_DIR/bin"
TOPDIR="$TMP_DIR/lede"
mkdir -p "$MOCK_BIN" "$TOPDIR/tools/cmake" "$TOPDIR/staging_dir/host/bin"
: > "$TOPDIR/Makefile"
: > "$TOPDIR/tools/cmake/Makefile"
printf 'upstream makefile must remain untouched\n' > "$TOPDIR/tools/Makefile"
cp "$TOPDIR/tools/Makefile" "$TMP_DIR/tools.Makefile.before"
export TOPDIR
export CALL_LOG="$TMP_DIR/calls.log"

cat > "$MOCK_BIN/make" <<'MOCK_MAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$CALL_LOG"
[[ "$1" == '-C' && "$2" == "$TOPDIR" && "$3" == 'V=1' && "$4" == 'tools/cmake/compile' ]]
cat > "$TOPDIR/staging_dir/host/bin/cmake" <<'MOCK_CMAKE'
#!/usr/bin/env bash
[[ "$1" == '--system-information' ]]
MOCK_CMAKE
chmod +x "$TOPDIR/staging_dir/host/bin/cmake"
MOCK_MAKE
chmod +x "$MOCK_BIN/make"

PATH="$MOCK_BIN:$PATH" MAKE=make bash "$BUILD_SCRIPT"
[[ "$(wc -l < "$CALL_LOG")" -eq 1 ]]
cmp "$TMP_DIR/tools.Makefile.before" "$TOPDIR/tools/Makefile"

# A missing CMake executable after make succeeds must fail closed.
rm -f "$TOPDIR/staging_dir/host/bin/cmake"
cat > "$MOCK_BIN/make" <<'MOCK_MAKE_MISSING'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$*" >> "$CALL_LOG"
MOCK_MAKE_MISSING
chmod +x "$MOCK_BIN/make"
if PATH="$MOCK_BIN:$PATH" MAKE=make bash "$BUILD_SCRIPT"; then
  echo '错误：未生成 CMake 可执行文件时必须失败。' >&2
  exit 1
fi

echo 'LEDE CMake 主机工具预构建测试通过。'
