# Copyright (c) 2018-2025 Nick Peng (pymumu@gmail.com)
# This is free software, licensed under the GNU General Public License v3.

include $(TOPDIR)/rules.mk

# Use Asia/Shanghai timezone
export TZ:=Asia/Shanghai

PKG_NAME:=luci-app-smartdns

# 虚拟机当天日期，例如：
# 2026-10-16 -> 26.10.16
PKG_VERSION:=$(shell TZ=Asia/Shanghai date +%y.%m.%d)

# 获取 pymumu/luci-app-smartdns master 最新 Commit
MYLEDE_SOURCE_LOCK?=/home/ubuntu/source-revisions.tsv
PKG_SOURCE_VERSION:=$(shell awk -F '\t' '$$1 == "plugin:luci_app_smartdns" {print $$4; exit}' "$(MYLEDE_SOURCE_LOCK)")
ifeq ($(strip $(PKG_SOURCE_VERSION)),)
$(error Missing locked full SHA for plugin:luci_app_smartdns in $(MYLEDE_SOURCE_LOCK))
endif

# Commit 前 7 位
PKG_SOURCE_VERSION_SHORT:=$(shell \
	echo $(PKG_SOURCE_VERSION) | cut -c1-7)

# 版本发布号
# 例如：1.581e5e8
PKG_RELEASE:=1.$(PKG_SOURCE_VERSION_SHORT)

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/pymumu/luci-app-smartdns.git

# Git 下载后的源码目录
PKG_SOURCE_SUBDIR:=$(PKG_NAME)-$(PKG_VERSION)-$(PKG_SOURCE_VERSION_SHORT)

# 明确让 PKG_BUILD_DIR 指向实际 Git 源码目录
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_SOURCE_SUBDIR)

PKG_SOURCE:=$(PKG_SOURCE_SUBDIR).tar.gz

PKG_HASH:=skip

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/package-defaults.mk

define Package/luci-app-smartdns
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=LuCI support for SmartDNS
	DEPENDS:=+smartdns
endef

define Package/luci-app-smartdns/description
	LuCI support for SmartDNS
endef

#
# 保留官方配置
# smartdns-ui 固定
#

define Package/luci-app-smartdns/config
	config PACKAGE_$(PKG_NAME)_INCLUDE_smartdns_ui
		bool "Include smartdns-ui"
		default y
endef

#
# 安装
#

define Package/luci-app-smartdns/install
	#
	# root
	#

	if [ -d "$(PKG_BUILD_DIR)/root" ]; then \
		$(INSTALL_DIR) $(1)/; \
		$(CP) $(PKG_BUILD_DIR)/root/. $(1)/; \
	fi

	#
	# LuCI 前端
	#

	if [ -d "$(PKG_BUILD_DIR)/htdocs" ]; then \
		$(INSTALL_DIR) $(1)/www; \
		$(CP) $(PKG_BUILD_DIR)/htdocs/. $(1)/www/; \
	fi

	#
	# LuCI 翻译
	#
	# pymumu/luci-app-smartdns:
	#
	#   zh_Hans -> LEDE zh-cn
	#   zh_Hant -> LEDE zh-tw
	#
	# 使用 LEDE/coolsnowwolf/luci 的 po2lmo
	#

	if [ -d "$(PKG_BUILD_DIR)/po" ]; then \
		$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n; \
		for langdir in $(PKG_BUILD_DIR)/po/*; do \
			if [ -d "$$$$langdir" ]; then \
				lang=$$$$(basename "$$$$langdir"); \
				case "$$$$lang" in \
					zh_Hans) lang=zh-cn ;; \
					zh_Hant) lang=zh-tw ;; \
				esac; \
				for po in "$$$$langdir"/*.po; do \
					if [ -f "$$$$po" ]; then \
						name=$$$$(basename "$$$$po" .po); \
						po2lmo "$$$$po" \
							"$(1)/usr/lib/lua/luci/i18n/$$$$name.$$$$lang.lmo"; \
					fi; \
				done; \
			fi; \
		done; \
	fi
endef

$(eval $(call BuildPackage,luci-app-smartdns))
