include $(TOPDIR)/rules.mk

PKG_NAME:=minisign
# The Actions preflight locks the latest stable upstream Release in this file's
# source-revisions.tsv. These defaults are retained for standalone/local builds.
MINISIGN_LOCK_FILE ?= /home/ubuntu/source-revisions.tsv
MINISIGN_LOCK_VERSION := $(shell awk -F '\t' '$1 == "MINISIGN_RELEASE" { print $3; exit }' "$(MINISIGN_LOCK_FILE)" 2>/dev/null)
MINISIGN_LOCK_HASH := $(shell awk -F '\t' '$1 == "MINISIGN_RELEASE" { print $4; exit }' "$(MINISIGN_LOCK_FILE)" 2>/dev/null)

PKG_VERSION:=0.11
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://github.com/jedisct1/minisign/archive/refs/tags/$(PKG_VERSION)
# Fallback digest for local builds without an Actions source lock.
PKG_HASH:=74c2c78a1cd51a43a6c98f46a4eabefbc8668074ca9aa14115544276b663fc55
ifneq ($(strip $(MINISIGN_LOCK_VERSION)),)
ifeq ($(strip $(MINISIGN_LOCK_HASH)),)
$(error Minisign release lock has a version but no SHA-256 digest)
endif
PKG_VERSION:=$(MINISIGN_LOCK_VERSION)
PKG_HASH:=$(MINISIGN_LOCK_HASH)
endif

PKG_LICENSE:=ISC
PKG_LICENSE_FILES:=LICENSE
PKG_BUILD_DEPENDS:=libsodium
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk

# The CI runner's host Ninja installation is not reliable; use CMake's
# Unix Makefiles generator for this small package instead.
PKG_USE_NINJA:=0
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

# LEDE's cmake.mk passes CMAKE_STRIP=:, but CMake treats ":" as an executable
# in POST_BUILD commands and generates an invalid ./:: invocation. An empty
# value disables upstream's optional POST_BUILD strip step; package stripping
# remains handled by the normal LEDE package pipeline.
CMAKE_OPTIONS += -DBUILD_STATIC_EXECUTABLES=OFF -DCMAKE_STRIP=

define Package/minisign/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/minisign $(1)/usr/bin/minisign
endef

$(eval $(call BuildPackage,minisign))
