#
# Copyright (c) 2026 RodmanWang
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
#
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI MyUpdate Firmware Manager
LUCI_DESCRIPTION:=GitHub Release based firmware update manager
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +curl +ca-bundle +jsonfilter +coreutils +coreutils-sha256sum +minisign
LUCI_PKGARCH:=all
LUCI_LANG.zh_Hans:=简体中文

# Use a compact UTC build timestamp (YYMMDDHHMMSS) so OPKG sees every
# later MyUpdate build as a newer package without a manually bumped release.
MYUPDATE_PACKAGE_VERSION := $(if $(strip $(MYUPDATE_PACKAGE_VERSION)),$(MYUPDATE_PACKAGE_VERSION),$(shell date -u +%y%m%d%H%M%S))
# Export the value and read it from the shell environment. Do not interpolate
# it into shell source: externally supplied values may contain shell quotes.
export MYUPDATE_PACKAGE_VERSION
ifneq ($(shell printf '%s' "$MYUPDATE_PACKAGE_VERSION" | grep -Eq '^[0-9]{12}$' && echo valid),valid)
$(error MYUPDATE_PACKAGE_VERSION must be a 12-digit UTC timestamp (YYMMDDHHMMSS))
endif
PKG_VERSION:=$(MYUPDATE_PACKAGE_VERSION)
PKG_RELEASE:=1
# LuCI translation IPKs use PKG_PO_VERSION instead of PKG_VERSION.
# Keep the zh-cn package version identical to the application package.
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=MyUpdate

# Keep administrator settings when this package is upgraded or reinstalled.
# This is required for opkg to treat the UCI file as a user configuration file.
define Package/luci-app-myupdate/conffiles
/etc/config/myupdate
endef

# Normalize package-owned file modes after live installation. Some generated
# IPKs have arrived with world-writable files, which is unsafe and can break
# services that enforce strict file permissions.
define Package/luci-app-myupdate/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

chmod 0755 /etc/init.d/myupdate || exit 1
chmod 0644 /usr/share/rpcd/ucode/myupdate.uc || exit 1
chmod 0600 /etc/config/myupdate || exit 1
chmod 0755 /usr/libexec/myupdate/*.sh || exit 1
[ ! -e /etc/myupdate/token ] || chmod 0600 /etc/myupdate/token || exit 1

# Migrate the previous package default (6 hours) to the new default (1 day).
# Preserve any non-default interval explicitly chosen by the administrator.
if [ "$(uci -q get myupdate.main.check_interval 2>/dev/null)" = "21600" ]; then
	uci set myupdate.main.check_interval='86400' && uci commit myupdate || exit 1
fi

# Move the previous package default (04:00) to the new default (03:30).
# Preserve any other schedule explicitly selected by the administrator.
if [ "$(uci -q get myupdate.main.auto_upgrade_time 2>/dev/null)" = "04:00" ]; then
	uci set myupdate.main.auto_upgrade_time='03:30' && uci commit myupdate || exit 1
fi
chmod 0600 /etc/config/myupdate || exit 1

if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd restart
fi

# MyUpdate's resident scheduler also consumes queued LuCI task requests.
if [ -x /etc/init.d/myupdate ]; then
	/etc/init.d/myupdate enable || exit 1
	/etc/init.d/myupdate restart || exit 1
fi
exit 0
endef

# This package is kept under package/lean rather than feeds/luci/applications.
# Use TOPDIR so the include resolves correctly from the local package directory.
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
