#!/bin/sh
# Build OpenWrt .ipk packages without an SDK.
#
# An OpenWrt .ipk is a *gzipped tar* containing ./debian-binary,
# ./control.tar.gz and ./data.tar.gz - NOT a Debian-style ar archive.
# Verified against the official 24.10 feed (ipk files start with 1f 8b) and
# against opkg's deb_extract(), which walks the outer archive with a tar
# reader. All archives are written as pure USTAR by Python: macOS bsdtar emits
# PAX "PaxHeader/" entries which opkg records as real files.
#
# Usage:
#   sh scripts/make-ipk.sh                       # generic "all" package (no binary)
#   sh scripts/make-ipk.sh --arch armhf          # one architecture bundle
#   sh scripts/make-ipk.sh --arch armhf --binary /path/to/cloudflared
#   sh scripts/make-ipk.sh --all                 # generic + all 5 architectures
#
# Architecture bundles contain the official cloudflared binary from
# dist/bin/<arch>/cloudflared (see scripts/fetch-binaries.sh) and a marker at
# /etc/cloudflared/package-arch. They install offline and still support
# one-click upgrades. "Architecture: all" is kept in control because the
# scripts are portable; the filename and marker identify the bundled binary,
# and postinst verifies CPU compatibility before keeping it.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(sed -n 's/^PKG_VERSION:=//p' "$ROOT/Makefile" | head -n1)
RELEASE=$(sed -n 's/^PKG_RELEASE:=//p' "$ROOT/Makefile" | head -n1)
VERSION=${VERSION:-1.1.0}
RELEASE=${RELEASE:-1}

CF_MODE=generic
CF_ARCH=''
CF_BINARY=''

usage() {
	cat <<'EOF'
Usage: sh scripts/make-ipk.sh [--all | --arch ARCH [--binary FILE]]
  (no args)              build the generic all.ipk (no bundled binary)
  --arch ARCH            build one architecture bundle
  --binary FILE          binary for --arch (default dist/bin/ARCH/cloudflared)
  --all                  build generic + all five architecture bundles
ARCH: amd64 | arm64 | armhf | arm | 386
Run scripts/fetch-binaries.sh first to populate dist/bin/.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--all) CF_MODE=all ;;
		--arch)
			shift
			[ $# -gt 0 ] || { echo '--arch needs a value' >&2; exit 1; }
			CF_MODE=arch
			CF_ARCH=$1
			;;
		--binary)
			shift
			[ $# -gt 0 ] || { echo '--binary needs a value' >&2; exit 1; }
			CF_BINARY=$1
			;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown option: $1" >&2; usage; exit 1 ;;
	esac
	shift
done

case "$CF_ARCH" in
	''|amd64|arm64|armhf|arm|386) ;;
	*) echo "unsupported arch: $CF_ARCH" >&2; exit 1 ;;
esac

mkdir -p "$ROOT/dist"
export CF_MODE CF_ARCH CF_BINARY

python3 - "$ROOT" "$VERSION" "$RELEASE" <<'PY'
import gzip
import hashlib
import io
import json
import os
import stat
import sys
import tarfile

root, version, release = sys.argv[1:4]
outdir = os.path.join(root, 'dist')
bindir = os.path.join(outdir, 'bin')
manifest_path = os.path.join(bindir, 'manifest.json')
mode = os.environ.get('CF_MODE', 'generic')
single_arch = os.environ.get('CF_ARCH', '')
single_binary = os.environ.get('CF_BINARY', '')
ARCHES = ['amd64', 'arm64', 'armhf', 'arm', '386']

manifest = None
if os.path.isfile(manifest_path):
    with open(manifest_path, 'r', encoding='utf-8') as handle:
        manifest = json.load(handle)

targets = []
if mode == 'generic':
    targets.append(None)
elif mode == 'arch':
    binary = single_binary or os.path.join(bindir, single_arch, 'cloudflared')
    meta = manifest['arches'][single_arch] if manifest and single_arch in manifest['arches'] else None
    targets.append((single_arch, binary, meta))
elif mode == 'all':
    targets.append(None)
    if not manifest:
        raise SystemExit('dist/bin/manifest.json missing - run scripts/fetch-binaries.sh first')
    for arch in ARCHES:
        binary = os.path.join(bindir, arch, 'cloudflared')
        if not os.path.isfile(binary):
            raise SystemExit('missing binary: %s' % binary)
        targets.append((arch, binary, manifest['arches'][arch]))
else:
    raise SystemExit('unknown mode: %s' % mode)


def tar_info(name, size, filemode, isdir=False):
    info = tarfile.TarInfo(name)
    info.size = size
    info.mode = filemode
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
        for name, data, filemode, isdir in entries:
            payload = io.BytesIO(data) if data is not None else None
            tar.addfile(tar_info(name, len(data) if data else 0, filemode, isdir), payload)
    return gzip.compress(buf.getvalue(), mtime=0)


def collect_data():
    files = []
    dirs = set()

    def add(rel, disk):
        st = os.stat(disk)
        filemode = 0o755 if (st.st_mode & stat.S_IXUSR) else 0o644
        with open(disk, 'rb') as handle:
            files.append(('./' + rel, handle.read(), filemode, False))
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
    return dirs, files


GENERIC_POSTINST = '''#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
if [ -x /etc/uci-defaults/90-cloudflared ]; then
\t/etc/uci-defaults/90-cloudflared
\trm -f /etc/uci-defaults/90-cloudflared
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/cloudflared enable >/dev/null 2>&1 || true
exit 0
'''

# The CPU probe mirrors cloudflared-ctl arch_get(). A wrong bundle must never
# leave an unrunnable executable behind: remove it and fall back to auto
# detection, so the LuCI update page can download the right binary later.
BUNDLE_POSTINST = '''#!/bin/sh
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
if [ -x /etc/uci-defaults/90-cloudflared ]; then
\t/etc/uci-defaults/90-cloudflared
\trm -f /etc/uci-defaults/90-cloudflared
fi
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/cloudflared enable >/dev/null 2>&1 || true

_pkg=__ARCH__
_cpu=$(uname -m 2>/dev/null)
case "$_cpu" in
\tx86_64|amd64) _cpu=amd64 ;;
\taarch64|arm64) _cpu=arm64 ;;
\tarmv7*|armv8l) _cpu=armhf ;;
\tarmv6*|armv5*|arm*) _cpu=arm ;;
\ti386|i486|i586|i686) _cpu=386 ;;
\t*) _cpu=unknown ;;
esac
if [ "$_cpu" = 'unknown' ]; then
\t[ -f /etc/openwrt_release ] && . /etc/openwrt_release
\tcase "${DISTRIB_ARCH:-}" in
\t\taarch64*) _cpu=arm64 ;;
\t\tx86_64*) _cpu=amd64 ;;
\t\tarm_cortex-a*|arm_*neon*) _cpu=armhf ;;
\t\tarm_*) _cpu=arm ;;
\t\ti386*|i486*|i586*|i686*) _cpu=386 ;;
\tesac
fi
if [ "$_cpu" != 'unknown' ] && [ "$_cpu" != "$_pkg" ]; then
\techo "WARNING: luci-app-cloudflared $_pkg bundle does not match this CPU ($_cpu); removing the bundled binary." >&2
\tlogger -t cloudflared -p user.err "architecture mismatch: $_pkg bundle on $_cpu, binary removed"
\trm -f /usr/sbin/cloudflared
\tuci -q set cloudflared.update.arch_override=auto
\tuci -q commit cloudflared
else
\tuci -q set cloudflared.update.arch_override="$_pkg"
\tuci -q commit cloudflared
fi
exit 0
'''

PRERM = '''#!/bin/sh
/etc/init.d/cloudflared stop >/dev/null 2>&1 || true
if [ -f /etc/crontabs/root ]; then
\tgrep -vF '/usr/sbin/cloudflared-update' /etc/crontabs/root > /etc/crontabs/root.tmp || true
\tmv /etc/crontabs/root.tmp /etc/crontabs/root
\t/etc/init.d/cron reload >/dev/null 2>&1 || true
fi
exit 0
'''


def assert_clean(tar_bytes, label):
    with tarfile.open(fileobj=io.BytesIO(gzip.decompress(tar_bytes)), mode='r:') as tar:
        names = tar.getnames()
    bad = [n for n in names if 'PaxHeader' in n or '._' in n]
    if bad:
        raise SystemExit('%s contains forbidden PAX/AppleDouble entries: %r' % (label, bad))
    return names


def build(target):
    dirs, files = collect_data()
    if target is None:
        arch, binary, meta = None, None, None
        suffix = 'all'
        postinst = GENERIC_POSTINST
        description = 'LuCI interface for Cloudflared Tunnel with one-click upgrades'
    else:
        arch, binary, meta = target
        suffix = arch
        if not os.path.isfile(binary):
            raise SystemExit('missing binary: %s' % binary)
        with open(binary, 'rb') as handle:
            bindata = handle.read()
        digest = hashlib.sha256(bindata).hexdigest()
        if meta and digest != meta['digest']:
            raise SystemExit('%s binary sha256 mismatch: got %s, want %s'
                             % (arch, digest, meta['digest']))
        tag = manifest['tag'] if manifest else 'unknown'
        files.append(('./usr/sbin/cloudflared', bindata, 0o755, False))
        files.append(('./etc/cloudflared/package-arch',
                      ('arch=%s\ntag=%s\nsha256=%s\nsource=https://github.com/cloudflare/cloudflared\n'
                       % (arch, tag, digest)).encode(), 0o644, False))
        postinst = BUNDLE_POSTINST.replace('__ARCH__', arch)
        description = ('LuCI interface for Cloudflared Tunnel (bundles official '
                       'cloudflared %s / %s)' % (tag, arch))

    entries = [(d, None, 0o755, True) for d in sorted(dirs)]
    entries.extend(sorted(files, key=lambda e: e[0]))
    installed_kb = sum(len(e[1]) for e in entries if e[1]) // 1024 + 1

    control = (
        'Package: luci-app-cloudflared\n'
        'Version: %s-%s\n'
        'Depends: luci-base, rpcd-mod-file, curl, ca-bundle\n'
        'Section: luci\n'
        'Priority: optional\n'
        'Architecture: all\n'
        'Installed-Size: %d\n'
        'Maintainer: Lancenas <183653181@qq.com>\n'
        'Description: %s\n'
        'Source: https://github.com/Lancenas/luci-app-cloudflared\n'
    ) % (version, release, installed_kb, description)

    control_tar = make_targz([
        ('./control', control.encode(), 0o644, False),
        ('./conffiles', b'/etc/config/cloudflared\n', 0o644, False),
        ('./postinst', postinst.encode(), 0o755, False),
        ('./prerm', PRERM.encode(), 0o755, False),
    ])
    data_tar = make_targz(entries)
    ipk_bytes = make_targz([
        ('./debian-binary', b'2.0\n', 0o644, False),
        ('./control.tar.gz', control_tar, 0o644, False),
        ('./data.tar.gz', data_tar, 0o644, False),
    ])

    ctl_members = assert_clean(control_tar, 'control.tar.gz')
    data_members = assert_clean(data_tar, 'data.tar.gz')
    outer_members = assert_clean(ipk_bytes, 'ipk')
    if outer_members != ['./debian-binary', './control.tar.gz', './data.tar.gz']:
        raise SystemExit('bad outer members: %r' % outer_members)
    if arch:
        with tarfile.open(fileobj=io.BytesIO(gzip.decompress(data_tar)), mode='r:') as tar:
            member = tar.getmember('./usr/sbin/cloudflared')
            if member.mode != 0o755:
                raise SystemExit('bundled binary is not executable')
        if './etc/cloudflared/package-arch' not in data_members:
            raise SystemExit('missing package-arch marker')

    out_path = os.path.join(outdir, 'luci-app-cloudflared_%s-%s_%s.ipk'
                            % (version, release, suffix))
    with open(out_path, 'wb') as out:
        out.write(ipk_bytes)
    print('Built: %s (%s KB, %d files, %d data tar members, no PAX)' % (
        os.path.basename(out_path), os.path.getsize(out_path) // 1024,
        len(files), len(data_members)))


for item in targets:
    build(item)
PY
