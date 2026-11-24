#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
BASE_DIR=/home/ubuntu

# minisign is a first-party package in this repository and is consumed by
# 01-check-env.sh from the prepared /home/ubuntu workspace.
for item in bd.sh scripts smartdns luci-app-smartdns luci-app-myupdate minisign; do
  if [[ ! -e "$ROOT/$item" ]]; then
    echo "::error::仓库中缺少必需文件或目录：$item"
    exit 1
  fi
done

sudo mkdir -p "$BASE_DIR"
sudo chown "$USER":"$USER" "$BASE_DIR"

for item in bd.sh scripts smartdns luci-app-smartdns luci-app-myupdate minisign; do
  rm -rf "$BASE_DIR/$item"
  cp -a "$ROOT/$item" "$BASE_DIR/$item"
done

mkdir -p "$BASE_DIR/dl" "$BASE_DIR/files"

if [[ -d "$ROOT/dl" ]]; then
  cp -a "$ROOT/dl/." "$BASE_DIR/dl/"
fi

if [[ -d "$ROOT/files" ]]; then
  cp -a "$ROOT/files/." "$BASE_DIR/files/"
fi

# Apply the minisign release version and archive digest resolved by source_check.
# Keep the package's existing LEDE download/build integration unchanged.
SOURCE_LOCK="${MYLEDE_SOURCE_LOCK:-$BASE_DIR/source-revisions.tsv}"
[[ -s "$SOURCE_LOCK" ]] || {
  echo "::error::缺少 minisign 源码版本锁定清单：$SOURCE_LOCK"
  exit 1
}
python3 - "$BASE_DIR/minisign/Makefile" "$SOURCE_LOCK" <<'PY'
from pathlib import Path
import re
import sys

makefile = Path(sys.argv[1])
lockfile = Path(sys.argv[2])
entries = []
for line in lockfile.read_text(encoding="utf-8").splitlines():
    fields = line.split("\\t")
    if fields and fields[0] == "MINISIGN_RELEASE":
        if len(fields) != 4:
            raise SystemExit("minisign release lock entry must contain exactly four fields")
        entries.append(fields)

if len(entries) != 1:
    raise SystemExit(f"expected exactly one minisign release lock entry, found {len(entries)}")

_, repository, version, digest = entries[0]
if repository != "https://github.com/jedisct1/minisign":
    raise SystemExit(f"unexpected minisign repository: {repository!r}")
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", version):
    raise SystemExit(f"invalid minisign release version: {version!r}")
if not re.fullmatch(r"[0-9a-f]{64}", digest):
    raise SystemExit("invalid minisign archive SHA-256")

text = makefile.read_text(encoding="utf-8")
for key, value in (("PKG_VERSION", version), ("PKG_HASH", digest)):
    pattern = re.compile(rf"(?m)^({key}:=).*$")
    text, count = pattern.subn(lambda match: match.group(1) + value, text)
    if count != 1:
        raise SystemExit(f"expected exactly one {key} assignment, found {count}")

makefile.write_text(text, encoding="utf-8")
print(f"minisign package pinned to upstream stable release {version}")
print(f"verified archive SHA-256: {digest}")
PY

chmod +x "$BASE_DIR/bd.sh" "$BASE_DIR/scripts/"*.sh

echo "已在 $BASE_DIR 下准备好自定义编译文件。"
du -sh "$BASE_DIR"/* 2>/dev/null | sort -h || true
