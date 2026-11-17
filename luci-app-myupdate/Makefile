include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI MyUpdate Firmware Manager
LUCI_DESCRIPTION:=GitHub Release based firmware update manager
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +curl +ca-bundle +jsonfilter +coreutils-sha256sum +minisign
LUCI_PKGARCH:=all
LUCI_LANG.zh_Hans:=简体中文

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=MyUpdate

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
