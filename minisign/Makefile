include $(TOPDIR)/rules.mk

PKG_NAME:=minisign
PKG_VERSION:=0.11
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/jedisct1/minisign/archive/refs/tags/$(PKG_VERSION)
PKG_HASH:=74c2c78a1cd51a43a6c98f46a4eabefbc8668074ca9aa14115544276b663fc55

PKG_LICENSE:=ISC
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=libsodium
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/minisign
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Simple tool to sign and verify files
  URL:=https://github.com/jedisct1/minisign
  DEPENDS:=+libsodium
endef

define Package/minisign/description
 Minisign is a simple tool to sign files and verify Ed25519 signatures.
endef

CMAKE_OPTIONS += -DBUILD_STATIC_EXECUTABLES=OFF

define Package/minisign/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/minisign $(1)/usr/bin/minisign
endef

$(eval $(call BuildPackage,minisign))
