#!/usr/bin/env bash
set -Eeuo pipefail

: "${LEDE_COMMIT:?LEDE_COMMIT is required}"
: "${LEDE_REF:?LEDE_REF must be the upstream default branch ref}"
BASE_DIR=/home/ubuntu
TOPDIR="$BASE_DIR/lede"
sudo mkdir -p "$BASE_DIR"
sudo chown "$USER":"$USER" "$BASE_DIR"

if [[ ! "$LEDE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::LEDE 提交版本无效：$LEDE_COMMIT"
  exit 1
fi

if [[ ! "$LEDE_REF" =~ ^refs/heads/.+ ]]; then
  echo "::error::LEDE_REF 必须是 refs/heads/ 下的分支引用：$LEDE_REF"
  exit 1
fi
LEDE_BRANCH="${LEDE_REF#refs/heads/}"

rm -rf "$TOPDIR" "$BASE_DIR/lede-pinned-origin.git"
git clone --depth 1 --single-branch --branch "$LEDE_BRANCH" \
  https://github.com/coolsnowwolf/lede.git "$TOPDIR"

cd "$TOPDIR"
if [[ "$(git rev-parse HEAD)" != "$LEDE_COMMIT" ]]; then
  git fetch --depth=1 origin "$LEDE_COMMIT"
  git reset --hard "$LEDE_COMMIT"
fi

# cachewrtbuild derives its key from git history under tools/ and toolchain/.
# A blobless unshallow fetch supplies history without downloading old file blobs.
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  git fetch --filter=blob:none --unshallow origin "$LEDE_BRANCH"
fi

# The original 02-update-source.sh calls git pull. Pin its origin to this exact
# commit so the source cannot move between fingerprinting and building.
git clone --bare --depth 1 "file://$TOPDIR" "$BASE_DIR/lede-pinned-origin.git"
git remote set-url origin "file://$BASE_DIR/lede-pinned-origin.git"

echo "已锁定 LEDE 源码版本：$(git rev-parse HEAD)（分支：$LEDE_REF）"
echo "工具链源码历史版本：$(git log --pretty=tformat:%h -n1 tools toolchain)"
