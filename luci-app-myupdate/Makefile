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
ifneq ($(shell printf '%s' '$(MYUPDATE_PACKAGE_VERSION)' | grep -Eq '^[0-9]{12}$' && echo valid),valid)
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