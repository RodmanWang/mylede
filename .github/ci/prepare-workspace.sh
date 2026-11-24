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

chmod +x "$BASE_DIR/bd.sh" "$BASE_DIR/scripts/"*.sh

echo "已在 $BASE_DIR 下准备好自定义编译文件。"
du -sh "$BASE_DIR"/* 2>/dev/null | sort -h || true
