#!/bin/sh
# Development install: copy the files straight onto a router over SSH.
# This deliberately bypasses opkg/apk - use make-ipk.sh for a real package.
#
# Usage: ./scripts/install-to-router.sh root@192.168.1.1

set -eu

COPYFILE_DISABLE=1
export COPYFILE_DISABLE

TARGET=${1:-}
if [ -z "$TARGET" ]; then
	printf 'Usage: %s root@192.168.1.1\n' "$0" >&2
	exit 1
fi

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

printf '==> Copying root/ to %s:/ ...\n' "$TARGET"
tar -C "$ROOT/root" -czf - . | ssh "$TARGET" 'tar -C / -xzf -'

printf '==> Copying LuCI views ...\n'
tar -C "$ROOT/htdocs/luci-static/resources/view/cloudflared" -czf - . | \
	ssh "$TARGET" 'mkdir -p /www/luci-static/resources/view/cloudflared && tar -C /www/luci-static/resources/view/cloudflared -xzf -'

printf '==> Applying first-boot setup ...\n'
ssh "$TARGET" '/bin/sh' <<'EOF'
chmod 755 /etc/init.d/cloudflared /etc/uci-defaults/90-cloudflared \
	/etc/cloudflared/post-upgrade.sh /usr/sbin/cloudflared-ctl /usr/sbin/cloudflared-update
[ -x /etc/uci-defaults/90-cloudflared ] && /etc/uci-defaults/90-cloudflared
rm -f /etc/uci-defaults/90-cloudflared
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/cloudflared enable >/dev/null 2>&1 || true
EOF

printf '\nDone. Open LuCI -> Services -> Cloudflared 隧道 -> 升级 to install the binary.\n'
