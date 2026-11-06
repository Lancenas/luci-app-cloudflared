#!/bin/sh
# Build a noarch .ipk without an OpenWrt SDK.
#
# An OpenWrt .ipk is a *gzipped tar* containing ./debian-binary,
# ./control.tar.gz and ./data.tar.gz - NOT a Debian-style ar archive.
# Verified against the official 24.10 feed (ipk files start with 1f 8b) and
# against opkg's deb_extract(), which walks the outer archive with a tar
# reader; an ar header is rejected with "Malformed package file".
#
# The inner archives must be pure USTAR: macOS bsdtar emits PAX "PaxHeader/"
# entries which opkg records as real files, so the install appears to succeed
# while no file actually lands on the router. Python writes every archive here
# to be independent of the host tar/ar flavour.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$ROOT/Makefile" | head -n1)
RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$ROOT/Makefile" | head -n1)
VERSION=${VERSION:-1.0.1}
RELEASE=${RELEASE:-1}

mkdir -p "$ROOT/dist"

python3 - "$ROOT" "$VERSION" "$RELEASE" <<'PY'
import io
import gzip
import os
import stat
import sys
import tarfile

root, version, release = sys.argv[1:4]
outdir = os.path.join(root, 'dist')
out_path = os.path.join(outdir, 'luci-app-cloudflared_%s-%s_all.ipk' % (version, release))


def tar_info(name, size, mode, isdir=False):
    info = tarfile.TarInfo(name)
    info.size = size
    info.mode = mode
    info.mtime = 0
    info.uid = 0
    info.gid = 0
    info.uname = 'root'
    info.gname = 'root'
    if isdir:
        info.type = tarfile.DIRTYPE
    return info


def make_targz(entries):
    """entries: (name, bytes|None, mode, isdir) -> gzipped USTAR tar bytes."""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode='w', format=tarfile.USTAR_FORMAT) as tar:
        for name, data, mode, isdir in entries:
            payload = io.BytesIO(data) if data is not None else None
            tar.addfile(tar_info(name, len(data) if data else 0, mode, isdir), payload)
    return gzip.compress(buf.getvalue(), mtime=0)


def collect_data():
    files = []
    dirs = set()

    def add(rel, disk):
        st = os.stat(disk)
        mode = 0o755 if (st.st_mode & stat.S_IXUSR) else 0o644
        with open(disk, 'rb') as handle:
            files.append(('./' + rel, handle.read(), mode, False))
        parts = rel.split('/')
        for i in range(1, len(parts)):
            dirs.add('./' + '/'.join(parts[:i]))

    base = os.path.join(root, 'root')
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            if name.startswith('._') or name == '.DS_Store':
                continue
            disk = os.path.join(dirpath, name)
            add(os.path.relpath(disk, base), disk)

    jsdir = os.path.join(root, 'htdocs/luci-static/resources/view/cloudflared')
    for name in sorted(os.listdir(jsdir)):
        if name.endswith('.js'):
            add('www/luci-static/resources/view/cloudflared/' + name,
                os.path.join(jsdir, name))

    entries = [(d, None, 0o755, True) for d in sorted(dirs)]
    entries.extend(sorted(files))
    return entries, len(files)


data_entries, file_count = collect_data()
installed_kb = sum(len(e[1]) for e in data_entries if e[1]) // 1024 + 1

control = (
    'Package: luci-app-cloudflared\n'
    'Version: %s-%s\n'
    'Depends: luci-base, rpcd-mod-file, curl, ca-bundle\n'
    'Section: luci\n'
    'Priority: optional\n'
    'Architecture: all\n'
    'Installed-Size: %d\n'
    'Maintainer: Lancenas <183653181@qq.com>\n'
    'Description: LuCI interface for Cloudflared Tunnel with one-click upgrades\n'
    'Source: https://github.com/Lancenas/luci-app-cloudflared\n'
) % (version, release, installed_kb)

conffiles = '/etc/config/cloudflared\n'

postinst = '''#!/bin/sh
if [ -x /etc/uci-defaults/90-cloudflared ]; then
\t/etc/uci-defaults/90-cloudflared
\trm -f /etc/uci-defaults/90-cloudflared
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/cloudflared enable >/dev/null 2>&1 || true
exit 0
'''

prerm = '''#!/bin/sh
/etc/init.d/cloudflared stop >/dev/null 2>&1 || true
if [ -f /etc/crontabs/root ]; then
\tgrep -vF '/usr/sbin/cloudflared-update' /etc/crontabs/root > /etc/crontabs/root.tmp || true
\tmv /etc/crontabs/root.tmp /etc/crontabs/root
\t/etc/init.d/cron reload >/dev/null 2>&1 || true
fi
exit 0
'''

control_tar = make_targz([
    ('./control', control.encode(), 0o644, False),
    ('./conffiles', conffiles.encode(), 0o644, False),
    ('./postinst', postinst.encode(), 0o755, False),
    ('./prerm', prerm.encode(), 0o755, False),
])
data_tar = make_targz(data_entries)
debian_binary = b'2.0\n'

outer = [
    ('./debian-binary', debian_binary, 0o644, False),
    ('./control.tar.gz', control_tar, 0o644, False),
    ('./data.tar.gz', data_tar, 0o644, False),
]
with open(out_path, 'wb') as out:
    out.write(make_targz(outer))


# --- self check: no PAX headers, correct outer container ------------------
def assert_clean(tar_bytes, label):
    with tarfile.open(fileobj=io.BytesIO(gzip.decompress(tar_bytes)), mode='r:') as tar:
        names = tar.getnames()
    bad = [n for n in names if 'PaxHeader' in n or '._' in n]
    if bad:
        raise SystemExit('%s contains forbidden PAX/AppleDouble entries: %r' % (label, bad))
    return names


ctl_members = assert_clean(control_tar, 'control.tar.gz')
data_members = assert_clean(data_tar, 'data.tar.gz')
outer_members = assert_clean(open(out_path, 'rb').read(), 'ipk')
expected = ['./debian-binary', './control.tar.gz', './data.tar.gz']
if outer_members != expected:
    raise SystemExit('bad outer members: %r' % outer_members)

print('Built: %s' % out_path)
print('  gzipped tar container, %d data files / %d data tar members, '
      '%d control members, no PAX headers'
      % (file_count, len(data_members), len(ctl_members)))
PY
