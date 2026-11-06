#!/bin/sh
# Download the official cloudflared Linux binaries used by the per-architecture
# .ipk packages. Runs on a build host (Linux/macOS/CI), not on the router.
#
#   sh scripts/fetch-binaries.sh                    # latest stable, all arches
#   TAG=2026.10.7 sh scripts/fetch-binaries.sh     # a specific release
#   MIRROR=https://gh-proxy.com/ sh scripts/fetch-binaries.sh
#   ARCHES='amd64 arm64' sh scripts/fetch-binaries.sh
#
# Every binary is verified against the sha256 digest published in the GitHub
# release metadata, so using a third-party download mirror cannot inject a
# tampered executable. Results go to dist/bin/<arch>/cloudflared plus
# dist/bin/manifest.json, which make-ipk.sh --all consumes.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT="$ROOT/dist/bin"
API=https://api.github.com/repos/cloudflare/cloudflared
DOWNLOAD=https://github.com/cloudflare/cloudflared/releases/download
TAG=${TAG:-latest}
MIRROR=${MIRROR:-}
ARCHES=${ARCHES:-amd64 arm64 armhf arm 386}
CURL_TIMEOUT=${CURL_TIMEOUT:-300}

mkdir -p "$OUT"

RELEASE_JSON="$OUT/release.json"
if [ "$TAG" = 'latest' ]; then
	API_URL="$API/releases/latest"
else
	case "$TAG" in
		''|*[!A-Za-z0-9._-]*) echo "invalid TAG: $TAG" >&2; exit 1 ;;
	esac
	API_URL="$API/releases/tags/$TAG"
fi

echo "Fetching release metadata: $API_URL"
curl -fsSL --connect-timeout 15 --max-time 60 \
	-H 'Accept: application/vnd.github+json' \
	-H 'User-Agent: luci-app-cloudflared-builder' \
	-o "$RELEASE_JSON" "$API_URL"

TAG=$(python3 - "$RELEASE_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d['tag_name'])
PY
)
echo "Release: $TAG"

python3 - "$RELEASE_JSON" "$OUT" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1]))
out = sys.argv[2]
arches = os.environ.get('ARCHES', 'amd64 arm64 armhf arm 386').split()
assets = {}
for a in data.get('assets', []):
    n = a['name']
    if n.startswith('cloudflared-linux-') and not n.endswith(('.deb', '.rpm')):
        assets[n[len('cloudflared-linux-'):]] = {
            'asset': n,
            'digest': (a.get('digest') or '').replace('sha256:', ''),
            'size': a.get('size', 0),
            'state': a.get('state', ''),
        }
missing = [a for a in arches if a not in assets or not assets[a]['digest']]
if missing:
    raise SystemExit('release lacks signed assets for: %s' % ', '.join(missing))
manifest = {
    'tag': data['tag_name'],
    'published': data.get('published_at', ''),
    'prerelease': bool(data.get('prerelease')),
    'source': 'https://github.com/cloudflare/cloudflared/releases/tag/%s' % data['tag_name'],
    'arches': {a: assets[a] for a in arches},
}
with open(os.path.join(out, 'manifest.json'), 'w') as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
    f.write('\n')
for a in arches:
    print('  %-7s %s  %s bytes' % (a, assets[a]['asset'], assets[a]['size']))
PY

for arch in $ARCHES; do
	ASSET="cloudflared-linux-$arch"
	DEST="$OUT/$arch/cloudflared"
	mkdir -p "$OUT/$arch"
	URL="$DOWNLOAD/$TAG/$ASSET"
	[ -n "$MIRROR" ] && URL="${MIRROR%/}/$URL"
	if [ -f "$DEST" ] && python3 - "$OUT/manifest.json" "$DEST" "$arch" <<'PY'
import hashlib, json, sys
manifest, path, arch = sys.argv[1:4]
want = json.load(open(manifest))['arches'][arch]['digest']
h = hashlib.sha256()
with open(path, 'rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
        h.update(chunk)
sys.exit(0 if h.hexdigest() == want else 1)
PY
	then
		echo "  $arch cached, sha256 already matches - skipping"
		chmod 755 "$DEST"
		continue
	fi
	echo "Downloading $ASSET ..."
	curl -fsSL --connect-timeout 15 --max-time "$CURL_TIMEOUT" --retry 2 \
		-o "$DEST" "$URL" || {
			echo "download failed: $URL" >&2
			echo "hint: set MIRROR=https://gh-proxy.com/ if GitHub releases are blocked" >&2
			exit 1
		}
	python3 - "$OUT/manifest.json" "$DEST" "$arch" <<'PY'
import hashlib, json, sys
manifest, path, arch = sys.argv[1:4]
want = json.load(open(manifest))['arches'][arch]['digest']
h = hashlib.sha256()
with open(path, 'rb') as f:
    for chunk in iter(lambda: f.read(1024 * 1024), b''):
        h.update(chunk)
got = h.hexdigest()
if got != want:
    raise SystemExit('%s: sha256 mismatch (got %s, want %s)' % (arch, got, want))
print('  %-7s sha256 OK  %s' % (arch, got))
PY
	chmod 755 "$DEST"
done

echo "Done: $OUT (release $TAG)"
