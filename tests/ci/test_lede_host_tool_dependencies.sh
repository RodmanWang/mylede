#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
PATCH_SCRIPT="$ROOT_DIR/.github/ci/patch-lede-host-tool-dependencies.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DEPENDENCY='$(curdir)/dwarves/compile += $(curdir)/cmake/compile'
ANCHOR='$(curdir)/dwarves/compile += $(curdir)/elfutils/compile'

make_fixture() {
  local root="$1" anchor="$2"
  mkdir -p "$root/tools/dwarves"
  printf '%s\n' "$anchor" > "$root/tools/Makefile"
  printf '%s\n' 'include $(INCLUDE_DIR)/host-build.mk' 'include $(INCLUDE_DIR)/cmake.mk' \
    > "$root/tools/dwarves/Makefile"
}

VALID_ROOT="$TMP_DIR/valid"
make_fixture "$VALID_ROOT" "$ANCHOR"

TOPDIR="$VALID_ROOT" bash "$PATCH_SCRIPT"
grep -Fxq "$DEPENDENCY" <(sed "s/^[[:space:]]*//" "$VALID_ROOT/tools/Makefile")
[[ "$(grep -Fc "$DEPENDENCY" <(sed "s/^[[:space:]]*//" "$VALID_ROOT/tools/Makefile"))" -eq 1 ]]

# The patch must be idempotent.
TOPDIR="$VALID_ROOT" bash "$PATCH_SCRIPT"
[[ "$(grep -Fc "$DEPENDENCY" <(sed "s/^[[:space:]]*//" "$VALID_ROOT/tools/Makefile"))" -eq 1 ]]

# Unknown upstream layouts must fail closed and remain untouched.
UNKNOWN_ROOT="$TMP_DIR/unknown"
UNKNOWN_ANCHOR='$(curdir)/dwarves/compile += $(curdir)/some-other-tool/compile'
make_fixture "$UNKNOWN_ROOT" "$UNKNOWN_ANCHOR"
BEFORE="$(cat "$UNKNOWN_ROOT/tools/Makefile")"
if TOPDIR="$UNKNOWN_ROOT" bash "$PATCH_SCRIPT"; then
  echo '错误：上游依赖结构变化时补丁脚本不应继续执行。' >&2
  exit 1
fi
AFTER="$(cat "$UNKNOWN_ROOT/tools/Makefile")"
[[ "$BEFORE" == "$AFTER" ]]

echo 'LEDE 主机工具依赖补丁测试通过。'
