#!/bin/sh
# Called from /etc/rc.local after a sysupgrade that kept settings.
# The 40 MB cloudflared binary is not preserved, so fetch it again.

LOG=/tmp/cloudflared-restore.log

[ -x /usr/sbin/cloudflared ] && exit 0

(
	echo "=== $(date) cloudflared restore start ==="
	if [ ! -x /usr/sbin/cloudflared-update ]; then
		echo 'ERROR: cloudflared-update is missing. Reinstall luci-app-cloudflared, then open LuCI -> 升级.'
		logger -t cloudflared-restore -p user.err 'helper missing, reinstall luci-app-cloudflared'
		exit 1
	fi

	_i=0
	while [ "$_i" -lt 30 ]; do
		nslookup api.github.com >/dev/null 2>&1 && break
		_i=$((_i + 1))
		sleep 10
	done

	/etc/init.d/cloudflared enable >/dev/null 2>&1 || true
	/usr/sbin/cloudflared-update --restore
	_rc=$?
	echo "=== $(date) cloudflared restore finished (rc=$_rc) ==="
) >> "$LOG" 2>&1 &

exit 0
