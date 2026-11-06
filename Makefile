# luci-app-cloudflared - OpenWrt package definition
#
# This Makefile works standalone: drop this repository into
# <openwrt-buildroot>/package/luci-app-cloudflared and select
# "LuCI -> 3. Applications -> luci-app-cloudflared" in menuconfig.
# The package is architecture independent (scripts + LuCI JavaScript only).
#
# The cloudflared binary itself is NOT shipped: it is downloaded from the
# official Cloudflare GitHub releases by the LuCI "Update" page.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-cloudflared
PKG_VERSION:=1.0.1
PKG_RELEASE:=1
PKGARCH:=all
PKG_LICENSE:=MIT
PKG_MAINTAINER:=Lancenas <183653181@qq.com>

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Cloudflared Tunnel
  DEPENDS:=+luci-base +rpcd-mod-file +curl +ca-bundle
  PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
  LuCI web interface for Cloudflare Tunnel (cloudflared) on OpenWrt.
  Supports token and config.yml tunnels, live status, and a one-click
  upgrade to the latest official cloudflared release with SHA-256
  verification, backup/rollback and optional scheduled auto updates.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/cloudflared
/etc/cloudflared/tunnel-token
/etc/cloudflared/config.yml
endef

# No compilation needed, everything is plain shell / JavaScript / JSON.
define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) \
		$(1)/etc/config \
		$(1)/etc/init.d \
		$(1)/etc/uci-defaults \
		$(1)/etc/cloudflared \
		$(1)/usr/sbin \
		$(1)/usr/share/luci/menu.d \
		$(1)/usr/share/rpcd/acl.d \
		$(1)/www/luci-static/resources/view/cloudflared

	$(INSTALL_CONF) ./root/etc/config/cloudflared $(1)/etc/config/cloudflared
	$(INSTALL_BIN)  ./root/etc/init.d/cloudflared $(1)/etc/init.d/cloudflared
	$(INSTALL_BIN)  ./root/etc/uci-defaults/90-cloudflared $(1)/etc/uci-defaults/90-cloudflared
	$(INSTALL_DATA) ./root/etc/cloudflared/config.yml.example $(1)/etc/cloudflared/config.yml.example
	$(INSTALL_BIN)  ./root/etc/cloudflared/post-upgrade.sh $(1)/etc/cloudflared/post-upgrade.sh

	$(INSTALL_BIN)  ./root/usr/sbin/cloudflared-ctl $(1)/usr/sbin/cloudflared-ctl
	$(INSTALL_BIN)  ./root/usr/sbin/cloudflared-update $(1)/usr/sbin/cloudflared-update

	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-cloudflared.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-cloudflared.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/cloudflared/*.js $(1)/www/luci-static/resources/view/cloudflared/
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
# uci-defaults only runs at the next boot when installing with opkg/apk,
# so apply the same setup right away.
if [ -z "$${IPKG_INSTROOT:-}" ]; then
	[ -x /etc/uci-defaults/90-cloudflared ] && /etc/uci-defaults/90-cloudflared
	rm -f /etc/uci-defaults/90-cloudflared
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	/etc/init.d/cloudflared enable >/dev/null 2>&1 || true
fi
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
# Keep the UCI config, token and config.yml: they are conffiles.
# Only remove our own cron line and stop the service.
if [ -z "$${IPKG_INSTROOT:-}" ]; then
	/etc/init.d/cloudflared stop >/dev/null 2>&1 || true
	if [ -f /etc/crontabs/root ]; then
		grep -vF '/usr/sbin/cloudflared-update' /etc/crontabs/root > /etc/crontabs/root.tmp || true
		mv /etc/crontabs/root.tmp /etc/crontabs/root
		/etc/init.d/cron reload >/dev/null 2>&1 || true
	fi
fi
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
