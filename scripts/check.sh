#!/bin/sh
# Local static checks: shell syntax, JavaScript syntax, JSON validity.
# No network access and no OpenWrt SDK required.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

fail=0

printf '==> POSIX shell syntax (sh -n)\n'
for f in \
	root/etc/init.d/cloudflared \
	root/etc/uci-defaults/90-cloudflared \
	root/etc/cloudflared/post-upgrade.sh \
	root/usr/sbin/cloudflared-ctl \
	root/usr/sbin/cloudflared-update \
	scripts/*.sh; do
	if sh -n "$f"; then
		printf '    ok  %s\n' "$f"
	else
		printf '    FAIL %s\n' "$f"
		fail=1
	fi
done

printf '==> JavaScript syntax (LuCI modules are compiled as function bodies)\n'
if command -v node >/dev/null 2>&1; then
	for f in htdocs/luci-static/resources/view/cloudflared/*.js; do
		if node -e '
			const fs = require("fs");
			const src = fs.readFileSync(process.argv[1], "utf8");
			new Function(src);
		' "$f"; then
			printf '    ok  %s\n' "$f"
		else
			printf '    FAIL %s\n' "$f"
			fail=1
		fi
	done
else
	printf '    skip (node not found)\n'
fi

printf '==> JSON validity\n'
if command -v python3 >/dev/null 2>&1; then
	for f in root/usr/share/luci/menu.d/*.json root/usr/share/rpcd/acl.d/*.json; do
		if python3 -m json.tool "$f" >/dev/null; then
			printf '    ok  %s\n' "$f"
		else
			printf '    FAIL %s\n' "$f"
			fail=1
		fi
	done
else
	printf '    skip (python3 not found)\n'
fi

if [ "$fail" -ne 0 ]; then
	printf '\nStatic checks FAILED.\n' >&2
	exit 1
fi
printf '\nAll static checks passed.\n'
