#!/bin/sh
# Remove the files installed by install-to-router.sh.
# By default the UCI config, token and config.yml are kept; --purge removes them.
#
# Usage: ./scripts/uninstall-from-router.sh root@192.168.1.1 [--purge]

set -eu

TARGET=${1:-}
PURGE=${2:-}
if [ -z "$TARGET" ]; then
	printf 'Usage: %s root@192.168.1.1 [--purge]\n' "$0" >&2
	exit 1
fi

ssh "$TARGET" /bin/sh -s "$PURGE" <<'EOF'
PURGE=${1:-}
/etc/init.d/cloudflared stop >/dev/null 2>&1 || true
/etc/init.d/cloudflared disable >/dev/null 2>&1 || true

if [ -f /etc/crontabs/root ]; then
	grep -vF '/usr/sbin/cloudflared-update' /etc/crontabs/root > /etc/crontabs/root.tmp || true
	mv /etc/crontabs/root.tmp /etc/crontabs/root
	/etc/init.d/cron reload >/dev/null 2>&1 || true
fi

if [ -f /etc/rc.local ]; then
	grep -vF 'luci-app-cloudflared' /etc/rc.local | grep -vF '/etc/cloudflared/post-upgrade.sh' > /etc/rc.local.tmp || true
	mv /etc/rc.local.tmp /etc/rc.local
fi

if [ -f /etc/sysupgrade.conf ]; then
	grep -vF 'cloudflared' /etc/sysupgrade.conf > /etc/sysupgrade.conf.tmp || true
	mv /etc/sysupgrade.conf.tmp /etc/sysupgrade.conf
fi

rm -f /etc/init.d/cloudflared /usr/sbin/cloudflared-ctl /usr/sbin/cloudflared-update \
	/usr/share/luci/menu.d/luci-app-cloudflared.json \
	/usr/share/rpcd/acl.d/luci-app-cloudflared.json
rm -rf /www/luci-static/resources/view/cloudflared
rm -f /etc/uci-defaults/90-cloudflared /etc/cloudflared/post-upgrade.sh

if [ "$PURGE" = '--purge' ]; then
	rm -f /usr/sbin/cloudflared /usr/sbin/cloudflared.bak /usr/sbin/cloudflared.new
	rm -rf /etc/cloudflared /etc/config/cloudflared
fi

/etc/init.d/rpcd restart >/dev/null 2>&1 || true
printf 'Uninstall finished (purge=%s)\n' "${PURGE:-no}"
EOF
