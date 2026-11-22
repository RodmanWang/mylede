#!/usr/bin/env bash
set -Eeuo pipefail

: "${LEDE_COMMIT:?LEDE_COMMIT is required}"
BASE_DIR=/home/ubuntu
TOPDIR="$BASE_DIR/lede"
sudo mkdir -p "$BASE_DIR"
sudo chown "$USER":"$USER" "$BASE_DIR"

if [[ ! "$LEDE_COMMIT" =~ ^[0-9a-f]{40}$ ]]; then
  echo "::error::Invalid LEDE commit: $LEDE_COMMIT"
  exit 1
fi

rm -rf "$TOPDIR" "$BASE_DIR/lede-pinned-origin.git"
git clone --depth 1 --single-branch --branch master \
  https://github.com/coolsnowwolf/lede.git "$TOPDIR"

cd "$TOPDIR"
if [[ "$(git rev-parse HEAD)" != "$LEDE_COMMIT" ]]; then
  git fetch --depth=1 origin "$LEDE_COMMIT"
  git reset --hard "$LEDE_COMMIT"
fi

# cachewrtbuild derives its key from git history under tools/ and toolchain/.
# A blobless unshallow fetch supplies history without downloading old file blobs.
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  git fetch --filter=blob:none --unshallow origin master
fi

# The original 02-update-source.sh calls git pull. Pin its origin to this exact
# commit so the source cannot move between fingerprinting and building.
git clone --bare --depth 1 "file://$TOPDIR" "$BASE_DIR/lede-pinned-origin.git"
git remote set-url origin "file://$BASE_DIR/lede-pinned-origin.git"

echo "Pinned LEDE source: $(git rev-parse HEAD)"
echo "Toolchain source history: $(git log --pretty=tformat:%h -n1 tools toolchain)"
