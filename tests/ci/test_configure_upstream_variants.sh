#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIGURE_SCRIPT="$ROOT_DIR/scripts/04-configure.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

TOPDIR="$TMP_DIR/lede"
mkdir -p "$TOPDIR/include" "$TOPDIR/target/linux/x86"
cat > "$TOPDIR/include/target.mk" <<'EOF'
DEFAULT_PACKAGES.router ?= base-files libc \
  luci-app-upstream-one luci-app-ddns
DEFAULT_PACKAGES.router += luci-app-upstream-two
EOF

cat > "$TOPDIR/target/linux/x86/Makefile" <<'EOF'
KERNEL_PATCHVER ?= 6.6
DEFAULT_PACKAGES := base-files kmod-e1000
EOF
: > "$TOPDIR/target/linux/x86/config-6.12"

cat > "$TOPDIR/package-config-generate.fixture" <<'EOF'
lan) ipad=\${ipaddr:-"10.1.2.3"} ;;
*) ipad=\${ipaddr:-"10.1.$((addr_offset++)).1"} ;;
EOF
mkdir -p "$TOPDIR/package/base-files/files/bin"
cp "$TOPDIR/package-config-generate.fixture" "$TOPDIR/package/base-files/files/bin/config_generate"

export TOPDIR
export KERNEL_VERSION=""
export CHANGE_LAN_IP=true
export LAN_IP=192.168.77.1

bash "$CONFIGURE_SCRIPT"

grep -Fq 'KERNEL_PATCHVER ?= 6.12' "$TOPDIR/target/linux/x86/Makefile"
! grep -Fq 'KERNEL_TESTING_PATCHVER' "$TOPDIR/target/linux/x86/Makefile"
grep -Fq 'DEFAULT_PACKAGES +=' "$TOPDIR/target/linux/x86/Makefile"
grep -Fq 'luci-app-smartdns' "$TOPDIR/target/linux/x86/Makefile"
grep -Fq 'lan) ipad=\${ipaddr:-"192.168.77.1"} ;;' "$TOPDIR/package/base-files/files/bin/config_generate"
grep -Fq '*) ipad=\${ipaddr:-"192.168.$((addr_offset++)).1"} ;;' "$TOPDIR/package/base-files/files/bin/config_generate"
! grep -Fq 'luci-app-upstream-one' "$TOPDIR/include/target.mk"
grep -Fq 'luci-app-ddns' "$TOPDIR/include/target.mk"

# Running the configuration step twice must not append duplicate package blocks.
BEFORE="$(grep -c '^# MyLEDE packages;' "$TOPDIR/target/linux/x86/Makefile")"
bash "$CONFIGURE_SCRIPT"
AFTER="$(grep -c '^# MyLEDE packages;' "$TOPDIR/target/linux/x86/Makefile")"
[[ "$BEFORE" -eq 1 && "$AFTER" -eq 1 ]]

echo '动态上游配置兼容性测试通过。'
