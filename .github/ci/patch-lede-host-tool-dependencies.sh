#!/usr/bin/env bash
set -Eeuo pipefail

TOPDIR="${TOPDIR:-/home/ubuntu/lede}"
TOOLS_MAKEFILE="$TOPDIR/tools/Makefile"
DWARVES_MAKEFILE="$TOPDIR/tools/dwarves/Makefile"
DEPENDENCY='$(curdir)/dwarves/compile += $(curdir)/cmake/compile'
ANCHOR='$(curdir)/dwarves/compile += $(curdir)/elfutils/compile'

[[ -f "$TOOLS_MAKEFILE" ]] || {
  echo "::error::LEDE tools/Makefile 不存在：$TOOLS_MAKEFILE"
  exit 1
}
[[ -f "$DWARVES_MAKEFILE" ]] || {
  echo "::error::LEDE tools/dwarves/Makefile 不存在：$DWARVES_MAKEFILE"
  exit 1
}

grep -Fq 'include $(INCLUDE_DIR)/cmake.mk' "$DWARVES_MAKEFILE" || {
  echo "::error::dwarves 不再通过 cmake.mk 构建；请重新审查依赖补丁。"
  exit 1
}

python3 - "$TOOLS_MAKEFILE" "$ANCHOR" "$DEPENDENCY" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
anchor, dependency = sys.argv[2:]
text = path.read_text(encoding="utf-8")

count = sum(line.strip() == anchor for line in text.splitlines())
if text.splitlines().count(dependency) > 1:
    raise SystemExit("tools/Makefile 中 dwarves -> cmake 依赖重复，拒绝继续")
if any(line.strip() == dependency for line in text.splitlines()):
    print("LEDE dwarves -> cmake 构建依赖已存在，无需修改")
elif count != 1:
    raise SystemExit(
        f"未能唯一定位 dwarves 的 elfutils 依赖行（匹配 {count} 次），"
        "上游 tools/Makefile 结构可能已变化；拒绝盲目修改"
    )
else:
    updated = text.replace(anchor, anchor + "\n" + dependency, 1)
    path.write_text(updated, encoding="utf-8")
    print("已补齐 LEDE 依赖：tools/dwarves/compile -> tools/cmake/compile")

lines = path.read_text(encoding="utf-8").splitlines()
if sum(line.strip() == dependency for line in lines) != 1:
    raise SystemExit("dwarves -> cmake 依赖写入后校验失败")
PY
