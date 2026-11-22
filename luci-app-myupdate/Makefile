include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI MyUpdate Firmware Manager
LUCI_DESCRIPTION:=GitHub Release based firmware update manager
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode +curl +ca-bundle +jsonfilter +coreutils +coreutils-sha256sum +minisign
LUCI_PKGARCH:=all
LUCI_LANG.zh_Hans:=简体中文

PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=MyUpdate

# rpcd-mod-ucode rejects scripts that are writable by other users.
# Enforce safe permissions after live installation, then restart rpcd so the
# newly installed ubus object is registered immediately.
define Package/luci-app-myupdate/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0

chmod 0644 /usr/share/rpcd/ucode/myupdate.uc || exit 1
if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd restart
fi
exit 0
endef

# This package is kept under package/lean rather than feeds/luci/applications.
# Use TOPDIR so the include resolves correctly from the local package directory.
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
