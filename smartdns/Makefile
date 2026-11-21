#
# Copyright (c) 2018-2025 Nick Peng (pymumu@gmail.com)
# This is free software, licensed under the GNU General Public License v3.
#

include $(TOPDIR)/rules.mk

# Use Asia/Shanghai timezone
export TZ:=Asia/Shanghai

PKG_NAME:=smartdns
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/pymumu/smartdns.git
PKG_SOURCE_VERSION:=$(shell if [ -n "$(MYLEDE_SOURCE_LOCK)" ] && [ -s "$(MYLEDE_SOURCE_LOCK)" ]; then awk -F '\\t' '$1=="smartdns" {print $4; exit}' "$(MYLEDE_SOURCE_LOCK)"; else git ls-remote https://github.com/pymumu/smartdns.git HEAD | awk '{print $1}'; fi)
PKG_VERSION:=$(shell TZ=Asia/Shanghai date +%y.%m.%d)-$(shell echo $(PKG_SOURCE_VERSION) | cut -c1-8)
PKG_RELEASE:=3
PKG_MIRROR_HASH:=skip

SMARTDNS_WEBUI_VERSION:=$(shell TZ=Asia/Shanghai date +%y.%m.%d)
SMARTDNS_WEBUI_SOURCE_PROTO:=git
SMARTDNS_WEBUI_SOURCE_URL:=https://github.com/pymumu/smartdns-webui.git
SMARTDNS_WEBUI_SOURCE_VERSION:=$(shell if [ -n "$(MYLEDE_SOURCE_LOCK)" ] && [ -s "$(MYLEDE_SOURCE_LOCK)" ]; then awk -F '\\t' '$1=="smartdns-webui" {print $4; exit}' "$(MYLEDE_SOURCE_LOCK)"; else git ls-remote https://github.com/pymumu/smartdns-webui.git HEAD | awk '{print $1}'; fi)
SMARTDNS_WEBUI_FILE:=smartdns-webui-$(SMARTDNS_WEBUI_VERSION)-$(shell echo $(SMARTDNS_WEBUI_SOURCE_VERSION) | cut -c1-8).tar.gz

PKG_MAINTAINER:=Nick Peng <pymumu@gmail.com>
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE

PKG_BUILD_PARALLEL:=1

# node compile is slow, so do not use it, download node manually.
# PACKAGE_smartdns-ui:node/host
PKG_BUILD_DEPENDS:=PACKAGE_luci-app-smartdns_INCLUDE_smartdns_ui:rust/host

include $(TOPDIR)/feeds/packages/lang/rust/rust-package.mk
include $(INCLUDE_DIR)/package.mk

MAKE_VARS += VER=$(PKG_VERSION)
MAKE_PATH:=src


define Package/smartdns/default
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=IP Addresses and Names
  URL:=https://www.github.com/pymumu/smartdns/
endef


define Package/smartdns
  $(Package/smartdns/default)
  TITLE:=smartdns server
  DEPENDS:=+libpthread +libopenssl +libatomic +zlib
endef

define Package/smartdns/description
SmartDNS is a local DNS server which accepts DNS query requests from local network clients,
gets DNS query results from multiple upstream DNS servers concurrently, and returns the fastest IP to clients.
Unlike dnsmasq's all-servers, smartdns returns the fastest IP, and encrypt DNS queries with DoT or DoH.
endef

define Package/smartdns/conffiles
/etc/config/smartdns
/etc/smartdns/address.conf
/etc/smartdns/blacklist-ip.conf
/etc/smartdns/custom.conf
/etc/smartdns/domain-block.list
/etc/smartdns/domain-forwarding.list
endef


define Package/smartdns/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/etc/config $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/smartdns $(1)/etc/smartdns/domain-set $(1)/etc/smartdns/conf.d/

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/src/smartdns \
		$(1)/usr/sbin/smartdns

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/package/openwrt/files/etc/init.d/smartdns \
		$(1)/etc/init.d/smartdns

	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/address.conf \
		$(1)/etc/smartdns/address.conf

	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/blacklist-ip.conf \
		$(1)/etc/smartdns/blacklist-ip.conf

	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/custom.conf \
		$(1)/etc/smartdns/custom.conf

	$(INSTALL_CONF) $(PKG_BUILD_DIR)/package/openwrt/files/etc/config/smartdns \
		$(1)/etc/config/smartdns

ifdef CONFIG_PACKAGE_luci-app-smartdns_INCLUDE_smartdns_ui
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_DIR) $(1)/usr/share/smartdns/wwwroot

	$(INSTALL_BIN) $(PKG_BUILD_DIR)/plugin/smartdns-ui/target/smartdns_ui.so \
		$(1)/usr/lib/smartdns_ui.so

	$(CP) $(PKG_BUILD_DIR)/smartdns-webui/out/* \
		$(1)/usr/share/smartdns/wwwroot/
endif
endef

define Package/smartdns-ui
  $(Package/smartdns/default)
  TITLE:=smartdns dashboard
  DEPENDS:=+smartdns $(RUST_ARCH_DEPENDS)
endef

define Package/smartdns-ui/description
A dashboard ui for smartdns server.
endef

define Package/smartdns-ui/conffiles
/etc/config/smartdns
endef

define Package/smartdns-ui/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_DIR) $(1)/etc/smartdns/conf.d/
	$(INSTALL_DIR) $(1)/usr/share/smartdns/wwwroot
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/plugin/smartdns-ui/target/smartdns_ui.so $(1)/usr/lib/smartdns_ui.so
	$(CP) $(PKG_BUILD_DIR)/smartdns-webui/out/* $(1)/usr/share/smartdns/wwwroot
endef

define Build/Compile/smartdns-webui
	which npm || (echo "npm not found, please install npm first" && exit 1)
	npm install --prefix $(PKG_BUILD_DIR)/smartdns-webui/
	npm run build --prefix $(PKG_BUILD_DIR)/smartdns-webui/
endef

define Build/Compile/smartdns-ui
	cargo install --force --locked bindgen-cli
	CARGO_BUILD_ARGS="$(if $(strip $(RUST_PKG_FEATURES)),--features "$(strip $(RUST_PKG_FEATURES)")") --profile $(CARGO_PKG_PROFILE)"
	+$(CARGO_PKG_VARS) CARGO_BUILD_ARGS="$(CARGO_BUILD_ARGS)" CC=$(TARGET_CC) \
	PATH="$$(PATH):$(CARGO_HOME)/bin" \
	make -C $(PKG_BUILD_DIR)/plugin/smartdns-ui
endef


define Download/smartdns-webui
	FILE:=$(SMARTDNS_WEBUI_FILE)
	PROTO:=$(SMARTDNS_WEBUI_SOURCE_PROTO)
	URL:=$(SMARTDNS_WEBUI_SOURCE_URL)
	VERSION:=$(SMARTDNS_WEBUI_SOURCE_VERSION)
	SUBDIR:=smartdns-webui
endef

$(eval $(call Download,smartdns-webui))


define Build/Prepare
	$(call Build/Prepare/Default)
ifdef CONFIG_PACKAGE_luci-app-smartdns_INCLUDE_smartdns_ui
	$(TAR) -C $(PKG_BUILD_DIR)/ -xf $(DL_DIR)/$(SMARTDNS_WEBUI_FILE)
endif
endef


define Build/Compile
	$(call Build/Compile/Default,smartdns)
ifdef CONFIG_PACKAGE_luci-app-smartdns_INCLUDE_smartdns_ui
	$(call Build/Compile/smartdns-ui)
	$(call Build/Compile/smartdns-webui)
endif
endef


$(eval $(call BuildPackage,smartdns))
$(eval $(call RustBinPackage,smartdns-ui))
$(eval $(call BuildPackage,smartdns-ui)) 
