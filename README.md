# luci-app-cloudflared

[简体中文 / 中文版](README.zh-CN.md) | **English**

**OpenWrt / LuCI app for Cloudflared Tunnel** — a full web UI with one-click upgrades of `cloudflared` to the latest official Cloudflare GitHub release. · [中文版](README.zh-CN.md)

Unlike shell-only installers, this project is a **standard OpenWrt package**: UCI configuration + a procd service + modern LuCI (JavaScript views) + rpcd ACL. It can be installed with `opkg` / `apk`, built with the OpenWrt SDK, and CI publishes `.ipk` artifacts.

> Inspired by [Coralesoft/OpenwrtCloudflare](https://github.com/Coralesoft/OpenwrtCloudflare) for its install/verification approach (GitHub Release digest checks, a `flock` concurrency guard, `/tmp` and flash space checks, sysupgrade restore). This project adds a LuCI interface, a UCI configuration model, background upgrade jobs, backup/rollback and scheduled upgrades.

UI design preview (opens offline): [docs/luci-preview.html](docs/luci-preview.html).

---

## 1. Features

| Capability | Description |
| --- | --- |
| **LuCI interface** | Three pages under the Services menu: `Status` / `Settings` / `Upgrade` |
| **One-click latest upgrade** | "Upgrade to latest (stable)" reads GitHub `releases/latest`, then downloads in the background → verifies SHA-256 → atomically replaces the binary → restarts the tunnel |
| **Live log** | Upgrade log streamed to `/var/run/cloudflared/update.log`, polled by LuCI every 2 seconds; progress survives page reloads |
| **Release channels** | `stable` / `preview` (includes prereleases) / `pinned` (locked version), plus upgrading to any explicit tag |
| **Scheduled upgrades** | UCI toggle + cron expression; versions are compared before downloading, so no traffic is wasted |
| **Security** | Verifies the GitHub Release asset `digest: sha256:...`; the Token is stored in `/etc/cloudflared/tunnel-token` (0600) and passed with `--token-file`, so it never appears in `ps` or UCI |
| **Backup / rollback** | Keeps `/usr/sbin/cloudflared.bak`; one-click rollback from the UI |
| **Two tunnel modes** | Token (remotely managed) and `config.yml` (locally managed, editable directly in the UI) |
| **Architecture detection** | `amd64 / arm64 / armhf / arm / 386`, with manual override; architectures without an official binary (mips, riscv, ...) fail with a clear message |
| **Per-architecture offline packages** | One ipk per architecture, bundling a SHA-256-verified official binary — ready to use without reaching the GitHub Release CDN; the CPU is checked at install time |
| **Download mirror** | When the GitHub Release CDN is unreachable, set a mirror prefix in Settings (e.g. `https://gh-proxy.com/`); release metadata and the SHA-256 digest still come from the official API |
| **Survives firmware upgrades** | `sysupgrade.conf` keeps the small files (architecture packages also keep the bundled binary); an `rc.local` hook re-downloads a missing binary once the network is up |
| **Command line** | `cloudflared-ctl status/check/log/start-update/rollback`, `cloudflared-update --cron` |

---

## 2. Comparison with the reference project

| Aspect | Coralesoft/OpenwrtCloudflare | This project |
| --- | --- | --- |
| Form | Two interactive shell scripts | OpenWrt package (ipk / SDK) + LuCI application |
| Configuration | `/etc/cloudflared/*` files + a generated init script | UCI `/etc/config/cloudflared` with a procd reload trigger |
| Interface | None | 3 LuCI pages (JS views + ACL + menu.d) |
| Upgrading | Run `/usr/sbin/cloudflared-update` over SSH, or cron | UI button + background job + live log + status polling |
| Architectures | aarch64 / x86_64 | Also armhf / arm / 386, plus `arch_override` |
| Version policy | Fixed to latest | stable / preview / pinned / explicit tag |
| Rollback | None (interrupted runs try to restore the old binary) | Keeps `.bak`, one-click rollback in the UI |
| Verification | GitHub digest | Same, plus a `--version` self-check and an optional skip switch |

---

## 3. Repository layout

```
.
├── README.md                        # Documentation (English, this file)
├── README.zh-CN.md                  # Documentation (Simplified Chinese)
├── Makefile                         # OpenWrt SDK package definition (PKGARCH:=all)
├── root/                            # File tree installed on the router at /
│   ├── etc/config/cloudflared       # UCI defaults (conffile)
│   ├── etc/init.d/cloudflared       # procd service
│   ├── etc/uci-defaults/90-cloudflared
│   ├── etc/cloudflared/             # config.yml.example + post-upgrade.sh
│   ├── usr/sbin/cloudflared-ctl     # Control plane (status/check/upgrade/rollback/cron)
│   ├── usr/sbin/cloudflared-update  # cron / SSH / restore entry point
│   ├── usr/share/luci/menu.d/       # Menu entries (status / settings / upgrade)
│   └── usr/share/rpcd/acl.d/        # Least-privilege ACL
├── htdocs/luci-static/resources/view/cloudflared/
│   ├── common.js                    # Shared RPC / DOM helpers
│   ├── status.js                    # Status page
│   ├── settings.js                  # Settings page (UCI form + Token / config.yml editors)
│   └── update.js                    # Upgrade page (one-click upgrade + live log)
├── scripts/
│   ├── fetch-binaries.sh            # Download and verify the 5 official cloudflared binaries
│   ├── make-ipk.sh                  # Build the generic and per-architecture ipks without the SDK
│   ├── install-to-router.sh         # Direct SSH install (development)
│   ├── uninstall-from-router.sh
│   └── check.sh                     # Local static checks
├── docs/luci-preview.html           # UI design preview
└── .github/workflows/ci.yml         # shellcheck + static checks + bundle builds
```

---

## 4. Installation

### 4.1 Choose a package (per-architecture releases; OpenWrt 23.05 / 24.10, opkg)

Since **v1.1.0**, every Release ships **6 packages**: one generic package plus five per-architecture offline packages that **bundle the official cloudflared binary**. Install the one matching your CPU; do not install several at once.

| Filename suffix | CPU / `DISTRIB_ARCH` | Bundled binary | Notes |
| --- | --- | --- | --- |
| `_all.ipk` | Any (scripts only, 19 KB) | No | After installing, click "Upgrade to latest" on the Upgrade page once; best for devices with good GitHub connectivity |
| `_amd64.ipk` | `x86_64` / `amd64` | Yes | x86 routers, PCs, VMs |
| `_arm64.ipk` | `aarch64` / `arm64` | Yes | 64-bit ARM (Raspberry Pi 4/5, ARM routers) |
| `_armhf.ipk` | `armv7l` / `armv8l`, `arm_cortex-a*` | Yes | 32-bit ARMv7 hard-float (Thunder OneCloud, etc.), **verified on a real ARM device** |
| `_arm.ipk` | `armv5*` / `armv6*` | Yes | Older 32-bit ARM |
| `_386.ipk` | `i386`–`i686` | Yes | 32-bit x86 |

```sh
# Example: an ARMv7 router using its matching offline package (no GitHub Release CDN needed)
wget https://github.com/Lancenas/luci-app-cloudflared/releases/download/v1.1.0/luci-app-cloudflared_1.1.0-1_armhf.ipk
opkg install luci-app-cloudflared_1.1.0-1_armhf.ipk
# Dependencies: luci-base rpcd-mod-file curl ca-bundle (normally already present with LuCI)
```

Architecture packages bundle the **unmodified** official binary (pinned at release time; see `tag` / `sha256` in `/etc/cloudflared/package-arch` inside the package). They work immediately and can still be upgraded later from the UI. `postinst` checks `uname -m`: if the architecture does not match, it removes the bundled binary, resets `arch_override` to `auto` and writes a syslog warning, so no unusable file is left behind. When the architecture matches, `arch_override` is locked to it (changeable on the Settings page).

> ⚠️ **v1.0.0 is deprecated**: its ipk used a Debian `ar` container and opkg reported `Malformed package file`; `check` also failed on busybox awk. Use **v1.1.0** (v1.0.1 is the minimum usable version).

A valid `.ipk` is a **gzip-compressed tar** containing `./debian-binary`, `./control.tar.gz` and `./data.tar.gz`; the two inner tars must be pure USTAR. `scripts/make-ipk.sh` generates every archive with Python, so even on macOS no bsdtar PAX `PaxHeader/` entries sneak in — opkg treats those as real files, causing an "install succeeded but no files landed" failure.

Repository: <https://github.com/Lancenas/luci-app-cloudflared> · [Releases](https://github.com/Lancenas/luci-app-cloudflared/releases)

`postinst` runs uci-defaults, restarts rpcd and enables the service. The menu is at **Services → Cloudflared 隧道 (Cloudflared Tunnel)**. Existing LuCI sessions expire after installation (rpcd restart), so log in again.

**Verified on real hardware**:
- **x86_64** (Kwrt 24.10-SNAPSHOT / QEMU): 13 files with correct permissions → all 3 LuCI pages and 4 JS assets return 200 → `cgi-exec` via rpcd ACL returns status/log → one-click upgrade to `2026.10.7` (38 MB, SHA-256 verified) → downgrade to `2026.10.6` creating `.bak` → rollback from the UI.
- **ARMv7** (Kwrt 24.10.0-rc2 / Thunder OneCloud / `arm_cortex-a5_vfpv4`): detected `armhf`, asset `cloudflared-linux-armhf` (35 MB) verified and executed on the device; LuCI pages/JS/ACL all working; offline package usable immediately. This device's link to the GitHub Release CDN is extremely slow — exactly the problem solved by the per-architecture packages and the download mirror option.

### 4.2 OpenWrt 25.12+ (apk) or building into firmware

Place this repository in the SDK/buildroot:

```sh
git clone https://github.com/Lancenas/luci-app-cloudflared.git \
  <openwrt>/package/luci-app-cloudflared
make menuconfig          # LuCI → 3. Applications → luci-app-cloudflared
make package/luci-app-cloudflared/compile V=s
```

`PKGARCH:=all` means the SDK produces the generic package (scripts + LuCI, no binary); the SDK emits the `.apk` automatically. The per-architecture offline packages do not need the SDK — build them with `sh scripts/fetch-binaries.sh` + `sh scripts/make-ipk.sh --all`, since the binaries are upstream prebuilt assets.

### 4.3 Direct install for development (no build)

```sh
sh scripts/install-to-router.sh root@192.168.1.1
```

This pushes the files over SSH + tar (bypassing the package manager) and is intended for debugging. To uninstall: `sh scripts/uninstall-from-router.sh root@192.168.1.1 [--purge]`.

---

## 5. First-time setup

1. **Cloudflare side**: Zero Trust → Networks → Tunnels → Create a remotely-managed tunnel, then copy the Tunnel Token.
2. **LuCI → Settings**:
   - Paste the Token → "Save Token and restart" (or switch to `config.yml` mode and fill in the config);
   - Tick "Enable tunnel" → **Save & Apply**.
3. **LuCI → Upgrade**: click "Check latest version" → "Upgrade to latest (stable)". Use this button on a fresh install too (the binary is not shipped with the generic package, about 38 MB).
4. **LuCI → Status**: confirm `● Running` and check the version and log.

> On routers with only 128 MB of RAM, the updater stops the tunnel before downloading when memory is low; if disk space is insufficient it aborts with an error and keeps the old version, never writing a partial binary.

---

## 6. How upgrades work

```
LuCI "Upgrade" button
  └─ cgi-exec → cloudflared-ctl start-update --latest --force   (returns immediately)
       └─ setsid background → cloudflared-ctl update-run --force
            ├─ flock /var/run/cloudflared/update.lock (concurrency guard)
            ├─ GitHub API /releases/latest → tag_name + asset digest/size
            ├─ check /tmp space, MemAvailable, free space in /usr/sbin
            ├─ download cloudflared-linux-<arch> to /tmp (optional download_mirror)
            ├─ sha256sum against the official digest; then a --version self-check
            ├─ cp to /usr/sbin/cloudflared.new → back up old binary as .bak → stop service
            ├─ atomic mv → sync → start service
            └─ write update.state / update.log / UCI last_update
```

- Every step is written to `/var/run/cloudflared/update.log` and mirrored to syslog (`logread -e cloudflared-update`).
- LuCI polls `status` + `log` every 2 seconds; job states: `pending → running → done / error`.
- Upgrades run in the background, so **closing the page does not interrupt them**; `flock` prevents cron and manual clicks from colliding.
- On interruption (signal), the tunnel that was stopped is started again automatically.
- **If the GitHub Release CDN is unreachable**: set a mirror prefix under "Settings → Upgrade settings → Download mirror" (e.g. `https://gh-proxy.com/`). The mirror applies only to the binary download URL — release metadata and the SHA-256 digest still come from `api.github.com`, so verification is never weakened. Installing the matching offline package is the other option.
- A stalled download (below 2 KB/s for 60 seconds) or a total runtime over 300 seconds fails proactively with a hint in the status/log, instead of hanging forever at "Downloading".

### Supported architectures and assets

| `uname -m` | Asset |
| --- | --- |
| `x86_64` | `cloudflared-linux-amd64` |
| `aarch64` | `cloudflared-linux-arm64` |
| `armv7*`, `armv8l` | `cloudflared-linux-armhf` |
| `armv6*`, `armv5*` | `cloudflared-linux-arm` |
| `i386`–`i686` | `cloudflared-linux-386` |
| Other (mips / riscv...) | No official binary → the UI reports an error; `arch_override` can be set manually |

### After sysupgrade

`/etc/sysupgrade.conf` keeps the configuration, Token, init script, both CLI tools and the LuCI files; installing an **architecture package** also keeps the bundled `/usr/sbin/cloudflared` (offline devices do not need to re-download after flashing). If the binary is missing, an `rc.local` hook waits for the network and calls `cloudflared-update --restore` to download and start it again.
Note: the package manager database is not preserved across sysupgrade, so reinstall the ipk/apk once afterwards to make it a managed package again.

---

## 7. UCI configuration

`/etc/config/cloudflared`, two named sections:

| Section | Option | Default | Meaning |
| --- | --- | --- | --- |
| `main` | `enabled` | `0` | Whether to start the tunnel |
| | `mode` | `token` | `token` / `config` |
| | `protocol` | `auto` | `auto` / `quic` / `http2` |
| | `loglevel` | `info` | Log level |
| | `metrics_addr` | empty | e.g. `127.0.0.1:20241` |
| | `extra_args` | empty | Space-separated additional arguments |
| | `tune_rmem` | `1` | Set `net.core.rmem_max` |
| | `config_file` | `/etc/cloudflared/config.yml` | Local config path |
| `update` | `channel` | `stable` | `stable` / `preview` / `pinned` |
| | `pinned_version` | empty | Locked release tag |
| | `auto_update` | `0` | Scheduled upgrade toggle |
| | `auto_update_time` | `30 3 * * *` | Cron expression |
| | `github_token` | empty | Raises the API rate limit (optional) |
| | `download_mirror` | empty | Mirror prefix for Release assets, e.g. `https://gh-proxy.com/` (optional) |
| | `arch_override` | `auto` | Manually set the asset suffix; locked to the architecture when an offline package is installed |
| | `verify_sha256` | `1` | Verify the official digest |
| | `keep_backup` | `1` | Keep `.bak` |
| | `last_update` | empty | Written by the updater |

**The Token is never stored in UCI**: UCI files are 0644 by default and readable by any process with read access. This project writes it to a separate 0600 file instead.

---

## 8. Command line

```sh
cloudflared-ctl status                          # JSON status snapshot (no network access)
cloudflared-ctl check                           # Query the latest release and refresh the cache
cloudflared-ctl log                             # Last 200 lines of the upgrade log
cloudflared-ctl start-update --latest            # Background upgrade to the latest stable release
cloudflared-ctl start-update --version 2026.10.7
cloudflared-ctl update-run --force              # Foreground synchronous upgrade (SSH / cron)
cloudflared-ctl rollback                        # Roll back to .bak
cloudflared-update --cron                       # cron entry point (compares versions before downloading)
cloudflared-update --restore                    # sysupgrade restore entry point
/etc/init.d/cloudflared restart
logread -e cloudflared-update
```

---

## 9. Troubleshooting

| Symptom | What to check |
| --- | --- |
| `Malformed package file` | The ipk is an `ar` container (the v1.0.0 bug); use a v1.0.1+ gzip/tar package. `tar -tzf xxx.ipk` should list `./debian-binary ./control.tar.gz ./data.tar.gz` |
| Install succeeded but no files landed | The package contains PAX `PaxHeader/` entries; rebuild with this repository's `scripts/make-ipk.sh` (pure USTAR) instead of the system `tar` |
| `awk: bad regex … Invalid contents of {}` | JSON splitting bug in older `cloudflared-ctl` versions; upgrade to v1.0.1+ |
| Menu not shown | Confirm `/usr/share/rpcd/acl.d/luci-app-cloudflared.json` exists and `rpcd` was restarted; `uci show cloudflared` returns config; hard-refresh the browser to clear the LuCI cache |
| Buttons report a permission error | ACL not applied: `/etc/init.d/rpcd restart`; confirm `rpcd-mod-file` and `luci-base` (cgi-io) are installed |
| Check for updates fails | `curl -fsSL https://api.github.com/repos/cloudflare/cloudflared/releases/latest`; the unauthenticated API is limited to 60 requests/hour, so a GitHub Token can help |
| Stuck at "Downloading" / download fails | The device cannot reach the GitHub Release CDN: ① install the matching per-architecture offline package (recommended), or ② set `https://gh-proxy.com/` or another prefix under "Settings → Upgrade settings → Download mirror". The Upgrade page shows the current download source |
| Architecture package installed but no binary | `uname -m` did not match the package architecture, so `postinst` removed the bundled binary; see `logread -e cloudflared`, then reinstall the correct package |
| Download succeeded but service not running | Check `logread`; verify the Token was pasted, `config.yml` contains `tunnel:`, and "Enable tunnel" was ticked |
| "Architecture not supported" | Cloudflare publishes no mips/riscv binary; check `uname -m` and `arch_override` |
| Not enough space / memory | The updater keeps the old version and reports how many KB are missing; free up flash or use external storage and retry |
| Broken after an upgrade | "Roll back to previous version" on the Upgrade page, or `cloudflared-ctl rollback` |

---

## 10. Development

```sh
sh scripts/check.sh                       # sh -n / JS syntax / JSON validation
sh scripts/make-ipk.sh                    # Generic _all.ipk
sh scripts/fetch-binaries.sh              # Download and SHA-256 verify the 5 official binaries
sh scripts/make-ipk.sh --all              # Generic package + 5 architecture packages
sh scripts/make-ipk.sh --arch armhf       # Build only the specified architecture
MIRROR=https://gh-proxy.com/ sh scripts/fetch-binaries.sh   # Use a mirror when direct download fails
tar -tzf dist/luci-app-cloudflared_1.1.0-1_all.ipk         # Inspect the outer package
```

`scripts/fetch-binaries.sh` reads each asset's `digest` from the GitHub API and verifies every download; output goes to `dist/bin/` (including `manifest.json` with tag / digest / size). `--all` verifies them again and aborts if any binary differs from the official digest. `dist/` and `dist/bin/` are excluded by `.gitignore`, so ~100 MB of binaries never enter the repository.

CI runs static checks, shellcheck (error level only) and builds the generic package on every push; on `v*` tags or manual triggers it also builds all per-architecture packages and uploads the artifacts. UI strings are wrapped in `_()` so `.po` translations can be added later.

---

## 11. License and credits

- This project is MIT licensed, see [LICENSE](LICENSE).
- `cloudflared` is a Cloudflare product. All binaries come unmodified from its official GitHub Releases; the per-architecture packages simply bundle the original file together with the official SHA-256 digest, and one-click upgrades at runtime still verify that digest.
- Design references: [Coralesoft/OpenwrtCloudflare](https://github.com/Coralesoft/OpenwrtCloudflare) and the JS view / ACL conventions of [OpenWrt LuCI](https://github.com/openwrt/luci).
