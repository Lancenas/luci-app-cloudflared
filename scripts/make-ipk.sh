#!/bin/sh
# Build a noarch .ipk without an OpenWrt SDK.
#
# The package contains only shell scripts, JSON and LuCI JavaScript, so a
# standard ar archive (debian-binary / control.tar.gz / data.tar.gz) is all
# opkg needs. For OpenWrt 25.12+ (apk) build with the official SDK instead.

set -eu

# macOS bsdtar otherwise embeds AppleDouble "._*" metadata files.
COPYFILE_DISABLE=1
export COPYFILE_DISABLE

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$ROOT/Makefile" | head -n1)
RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$ROOT/Makefile" | head -n1)
VERSION=${VERSION:-1.0.0}
RELEASE=${RELEASE:-1}

OUT_DIR="$ROOT/dist"
OUT="$OUT_DIR/luci-app-cloudflared_${VERSION}-${RELEASE}_all.ipk"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/luci-cloudflared-ipk.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

mkdir -p "$OUT_DIR" "$WORK/data" "$WORK/control"

# --- data.tar.gz -----------------------------------------------------------
cp -R -p "$ROOT/root/." "$WORK/data/"
mkdir -p "$WORK/data/www/luci-static/resources/view/cloudflared"
cp "$ROOT"/htdocs/luci-static/resources/view/cloudflared/*.js \
	"$WORK/data/www/luci-static/resources/view/cloudflared/"

SIZE_KB=$(du -sk "$WORK/data" | awk '{print $1}')

( cd "$WORK/data" && tar -czf "$WORK/data.tar.gz" --owner=0 --group=0 --numeric-owner . )

# --- control.tar.gz --------------------------------------------------------
cat > "$WORK/control/control" <<EOF
Package: luci-app-cloudflared
Version: ${VERSION}-${RELEASE}
Depends: luci-base, rpcd-mod-file, curl, ca-bundle
Section: luci
Priority: optional
Architecture: all
Installed-Size: ${SIZE_KB}
Maintainer: Lancenas <183653181@qq.com>
Description: LuCI interface for Cloudflared Tunnel with one-click upgrades
Source: https://github.com/Lancenas/luci-app-cloudflared
EOF

cat > "$WORK/control/conffiles" <<'EOF'
/etc/config/cloudflared
EOF

cat > "$WORK/control/postinst" <<'EOF'
#!/bin/sh
if [ -x /etc/uci-defaults/90-cloudflared ]; then
	/etc/uci-defaults/90-cloudflared
	rm -f /etc/uci-defaults/90-cloudflared
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/cloudflared enable >/dev/null 2>&1 || true
exit 0
EOF

cat > "$WORK/control/prerm" <<'EOF'
#!/bin/sh
/etc/init.d/cloudflared stop >/dev/null 2>&1 || true
if [ -f /etc/crontabs/root ]; then
	grep -vF '/usr/sbin/cloudflared-update' /etc/crontabs/root > /etc/crontabs/root.tmp || true
	mv /etc/crontabs/root.tmp /etc/crontabs/root
	/etc/init.d/cron reload >/dev/null 2>&1 || true
fi
exit 0
EOF

chmod 755 "$WORK/control/postinst" "$WORK/control/prerm"
printf '2.0\n' > "$WORK/debian-binary"
( cd "$WORK/control" && tar -czf "$WORK/control.tar.gz" --owner=0 --group=0 --numeric-owner . )

# --- ar archive ------------------------------------------------------------
# Write a GNU-style ar archive ourselves. macOS `ar` emits a BSD symbol table
# (__.SYMDEF) which opkg does not expect, and GNU binutils is not guaranteed
# to be installed on the build host.
python3 - "$OUT" "$WORK/debian-binary" "$WORK/control.tar.gz" "$WORK/data.tar.gz" <<'PY'
import os, sys

out = sys.argv[1]
members = sys.argv[2:]

def field(value, width):
    data = str(value).encode('ascii')
    if len(data) > width:
        raise SystemExit('ar field too long: %r' % data)
    return data.ljust(width, b' ')

with open(out, 'wb') as ar:
    ar.write(b'!<arch>\n')
    for path in members:
        data = open(path, 'rb').read()
        name = (os.path.basename(path) + '/').encode('ascii')
        ar.write(name.ljust(16, b' '))
        ar.write(field(0, 12))       # mtime
        ar.write(field(0, 6))        # uid
        ar.write(field(0, 6))        # gid
        ar.write(field(100644, 8))   # mode
        ar.write(field(len(data), 10))
        ar.write(b'`\n')
        ar.write(data)
        if len(data) % 2:
            ar.write(b'\n')
PY

printf 'Built: %s (%s KB)\n' "$OUT" "$SIZE_KB"
