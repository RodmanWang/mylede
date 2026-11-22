#!/usr/bin/env bash
set -Eeuo pipefail

# Shared, version-controlled host dependency list for both build runners.
# The runner OS is pinned to ubuntu-24.04 in build.yml.

PACKAGES=(
  build-essential
  clang
  llvm
  flex
  bison
  g++
  gawk
  gcc-multilib
  g++-multilib
  gettext
  git
  libncurses-dev
  libncurses5-dev
  libssl-dev
  python3
  python3-dev
  python3-setuptools
  python-is-python3
  rsync
  unzip
  zlib1g-dev
  file
  wget
  curl
  time
  perl
  subversion
  swig
  xsltproc
  libelf-dev
  libglib2.0-dev
  libgmp-dev
  libmpc-dev
  libmpfr-dev
  libreadline-dev
  libtool
  autopoint
  autoconf
  automake
  cmake
  pkgconf
  qemu-utils
  squashfs-tools
  device-tree-compiler
  patch
  gperf
  help2man
  asciidoc
  xmlto
  zstd
  ca-certificates
)

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${PACKAGES[@]}"
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

echo '========== Installed host dependencies =========='
git --version
python3 --version
zstd --version | head -n 1
