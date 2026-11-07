# luci-app-cloudflared

**简体中文** | [English](README.md)

**Cloudflared 隧道的 OpenWrt / LuCI 插件**：带完整 Web 界面，可在 LuCI 里一键把 `cloudflared` 升级到 Cloudflare 官方 GitHub 发布的最新版本。

不同于纯 shell 安装脚本方案，本项目是一个**标准 OpenWrt 软件包**：UCI 配置 + procd 服务 + 现代 LuCI（JavaScript view）界面 + rpcd ACL，支持 `opkg` / `apk` 安装、SDK 编译、CI 产出 `.ipk`。

> 参考了 [Coralesoft/OpenwrtCloudflare](https://github.com/Coralesoft/OpenwrtCloudflare) 的安装/校验思路（GitHub Release digest 校验、`flock` 防并发、`/tmp` 与 flash 空间检查、sysupgrade 恢复），并在此基础上补了 LuCI 界面、UCI 配置模型、后台升级任务、备份回滚与定时升级。

---

## 1. 功能

| 能力 | 说明 |
| --- | --- |
| **LuCI 界面** | 服务菜单下三个页面：`状态` / `设置` / `升级` |
| **一键升级最新版** | 「升级到最新版（stable）」直接读 GitHub `releases/latest`，后台下载 → SHA-256 校验 → 原子替换 → 重启隧道 |
| **实时日志** | 升级日志流式落盘 `/var/run/cloudflared/update.log`，LuCI 每 2 秒轮询显示，刷新页面也不丢进度 |
| **多通道** | `stable` / `preview`（含预发布）/ `pinned`（锁定版本），另可指定任意 tag 升级 |
| **定时升级** | UCI 开关 + cron 表达式，自动对比版本后再下载（不做无意义的流量消耗） |
| **安全** | 校验 GitHub Release 资产 `digest: sha256:...`；Token 存 `/etc/cloudflared/tunnel-token`（0600），用 `--token-file` 传入，不出现在 `ps` / UCI |
| **备份 / 回滚** | 保留 `/usr/sbin/cloudflared.bak`，界面一键回滚 |
| **两种隧道模式** | Token（远程管理）与 `config.yml`（本地管理，界面内可直接编辑） |
| **架构自适应** | `amd64 / arm64 / armhf / arm / 386`，可手动覆盖；mips/riscv 等官方无二进制的架构明确报错 |
| **分架构离线包** | 每个架构单独发一个 ipk，内置经 SHA-256 校验的官方二进制，装上即用、不需访问 GitHub Release CDN；安装时校验 CPU 是否匹配 |
| **下载镜像** | GitHub Release CDN 不通时，设置页可填镜像前缀（如 `https://gh-proxy.com/`）；版本信息与 SHA-256 仍来自官方 API |
| **固件升级恢复** | `sysupgrade.conf` 保留小文件（架构包还保留内置二进制），`rc.local` 钩子在二进制缺失时等网络后重新下载 |
| **命令行** | `cloudflared-ctl status/check/log/start-update/rollback`、`cloudflared-update --cron` |

界面设计预览（离线可打开）：[docs/luci-preview.html](docs/luci-preview.html)。

---

## 2. 与参考项目的差异

| 维度 | Coralesoft/OpenwrtCloudflare | 本项目 |
| --- | --- | --- |
| 形态 | 两个交互式 shell 脚本 | OpenWrt 软件包（ipk / SDK）+ LuCI 应用 |
| 配置 | `/etc/cloudflared/*` 文件 + 生成的 init 脚本 | UCI `/etc/config/cloudflared`，procd reload trigger |
| 界面 | 无 | 3 个 LuCI 页面（JS view + ACL + menu.d） |
| 升级 | SSH 跑 `/usr/sbin/cloudflared-update`，或 cron | 界面按钮 + 后台任务 + 实时日志 + 状态轮询 |
| 架构 | aarch64 / x86_64 | 另加 armhf / arm / 386，并支持 `arch_override` |
| 版本策略 | 固定 latest | stable / preview / pinned / 指定 tag |
| 回滚 | 无（失败时恢复旧二进制靠中断处理） | 保留 `.bak`，界面一键回滚 |
| 校验 | GitHub digest | 同上，另加二进制自检 `--version` 与可选跳过开关 |

---

## 3. 目录结构

```
.
├── README.md                        # 英文文档
├── README.zh-CN.md                  # 中文文档（本文件）
├── Makefile                         # OpenWrt SDK 包定义（PKGARCH:=all）
├── root/                            # 安装到路由器 / 的文件树
│   ├── etc/config/cloudflared       # UCI 默认配置（conffile）
│   ├── etc/init.d/cloudflared       # procd 服务
│   ├── etc/uci-defaults/90-cloudflared
│   ├── etc/cloudflared/             # config.yml.example + post-upgrade.sh
│   ├── usr/sbin/cloudflared-ctl     # 控制平面（状态/检查/升级/回滚/cron）
│   ├── usr/sbin/cloudflared-update  # cron / SSH / 恢复入口
│   ├── usr/share/luci/menu.d/       # 菜单（状态 / 设置 / 升级）
│   └── usr/share/rpcd/acl.d/        # 最小权限 ACL
├── htdocs/luci-static/resources/view/cloudflared/
│   ├── common.js                    # 共享 RPC / DOM helper
│   ├── status.js                    # 状态页
│   ├── settings.js                  # 设置页（UCI 表单 + Token / config.yml 编辑）
│   └── update.js                    # 升级页（一键升级 + 实时日志）
├── scripts/
│   ├── fetch-binaries.sh            # 拉取并校验 5 个架构的官方 cloudflared
│   ├── make-ipk.sh                  # 免 SDK 生成通用包 + 分架构离线包
│   ├── install-to-router.sh         # SSH 直装（开发调试）
│   ├── uninstall-from-router.sh
│   └── check.sh                     # 本地静态检查
├── docs/luci-preview.html           # 界面设计预览
└── .github/workflows/ci.yml         # shellcheck + 静态检查 + 分包构建
```

---

## 4. 安装

### 4.1 选择安装包（按架构分开发布，OpenWrt 23.05 / 24.10，opkg）

自 **v1.1.0** 起，每个 Release 提供 **6 个包**：1 个通用包 + 5 个**内置官方 cloudflared 二进制**的架构离线包。选与你 CPU 对应的一个即可，不要同时装多个。

| 包名后缀 | 适用 CPU / `DISTRIB_ARCH` | 内置二进制 | 说明 |
| --- | --- | --- | --- |
| `_all.ipk` | 任意（纯脚本，19 KB） | 否 | 装完到「升级」页点一次「升级到最新版」下载；适合 GitHub 下载通畅的设备 |
| `_amd64.ipk` | `x86_64` / `amd64` | 是 | x86 软路由、PC、虚拟机 |
| `_arm64.ipk` | `aarch64` / `arm64` | 是 | 64 位 ARM（树莓派 4/5、ARM 软路由） |
| `_armhf.ipk` | `armv7l` / `armv8l`，`arm_cortex-a*` | 是 | 32 位 ARMv7 硬浮点（Thunder OneCloud 等），**本次 ARM 真机实测** |
| `_arm.ipk` | `armv5*` / `armv6*` | 是 | 老 32 位 ARM |
| `_386.ipk` | `i386`–`i686` | 是 | 32 位 x86 |

```sh
# 以 ARMv7 路由器为例，用对应架构的离线包（无需访问 GitHub Release CDN）
wget https://github.com/Lancenas/luci-app-cloudflared/releases/download/v1.1.0/luci-app-cloudflared_1.1.0-1_armhf.ipk
opkg install luci-app-cloudflared_1.1.0-1_armhf.ipk
# 依赖：luci-base rpcd-mod-file curl ca-bundle（一般已随 LuCI 装好）
```

架构包内置**未经修改**的官方二进制（Release 时固定版本，见包内 `/etc/cloudflared/package-arch` 的 `tag`/`sha256`），安装即可用，之后仍能通过界面一键升级。`postinst` 会核对 `uname -m`：装错架构时会删除内置二进制、把 `arch_override` 复位为 `auto` 并写入 syslog，避免留下无法运行的文件。安装匹配时则把 `arch_override` 锁定为该架构（可在设置页改）。

> ⚠️ **v1.0.0 已废弃**：ipk 误用 Debian `ar` 容器，opkg 报 `Malformed package file`；且 `check` 在 busybox awk 上失败。请使用 **v1.1.0**（最低不低于 v1.0.1）。

`.ipk` 的正确容器是 **gzip 压缩的 tar**（外层 `./debian-binary`、`./control.tar.gz`、`./data.tar.gz`），内部两个 tar 必须是纯 USTAR。`scripts/make-ipk.sh` 用 Python 生成全部归档，因此在 macOS 上也不会混入 bsdtar 的 PAX `PaxHeader/` 条目——那种条目会被 opkg 当成真实文件，造成「安装成功但一个文件都没落地」。

仓库：<https://github.com/Lancenas/luci-app-cloudflared> · [Releases](https://github.com/Lancenas/luci-app-cloudflared/releases)

`postinst` 会自动执行 uci-defaults、重启 rpcd、enable 服务。菜单在 **Services → Cloudflared 隧道**。安装后 LuCI 旧会话会失效（rpcd 重启），重新登录一次即可。

**真机验证**：
- **x86_64**（Kwrt 24.10-SNAPSHOT / QEMU）：13 个文件与权限正确 → LuCI 三页 + 4 个 JS 均 200 → `cgi-exec` 经 rpcd ACL 返回 status/log → 一键升级 `2026.10.7`（38 MB，SHA-256 通过）→ 降级 `2026.10.6` 生成 `.bak` → 界面回滚恢复。
- **ARMv7**（Kwrt 24.10.0-rc2 / Thunder OneCloud / `arm_cortex-a5_vfpv4`）：架构识别 `armhf`、资产 `cloudflared-linux-armhf`（35 MB）校验通过并在真机运行；LuCI 三页/JS/ACL 正常；架构离线包安装即用。该设备出口到 GitHub Release CDN 极慢，正是分架构离线包与下载镜像选项要解决的问题。

### 4.2 OpenWrt 25.12+（apk）或集成进固件

把本仓库放进 SDK/buildroot：

```sh
git clone https://github.com/Lancenas/luci-app-cloudflared.git \
  <openwrt>/package/luci-app-cloudflared
make menuconfig          # LuCI → 3. Applications → luci-app-cloudflared
make package/luci-app-cloudflared/compile V=s
```

`PKGARCH:=all`，SDK 产出的是通用包（脚本 + LuCI，无二进制）；`.apk` 由 SDK 自动产出。按架构内置二进制的离线包不需要 SDK，用 `sh scripts/fetch-binaries.sh` + `sh scripts/make-ipk.sh --all` 生成，因为二进制是上游预编译资产。

### 4.3 开发直装（不编译）

```sh
sh scripts/install-to-router.sh root@192.168.1.1
```

该脚本通过 SSH + tar 把文件推到路由器（绕过包管理器），适合调试。卸载：`sh scripts/uninstall-from-router.sh root@192.168.1.1 [--purge]`。

---

## 5. 首次使用流程

1. **Cloudflare 侧**：Zero Trust → Networks → Tunnels → Create a remotely-managed tunnel，复制 Tunnel Token。
2. **LuCI → 设置**：
   - 粘贴 Token → 「保存 Token 并重启」（或切到 `config.yml` 模式并填写配置）；
   - 「启用隧道」打勾 → **保存并应用**。
3. **LuCI → 升级**：点「检查最新版本」→「升级到最新版（stable）」。首次安装也走这个按钮（二进制不随包分发，约 38 MB）。
4. **LuCI → 状态**：确认 `● 运行中`，查看版本与日志。

> 若路由器只有 128 MB 内存，升级器会在内存不足时先停隧道再下载；空间不足会直接报错并保留旧版本，不会写入半个二进制。

---

## 6. 升级是怎么工作的

```
LuCI「升级」按钮
  └─ cgi-exec → cloudflared-ctl start-update --latest --force   (立即返回)
       └─ setsid 后台 → cloudflared-ctl update-run --force
            ├─ flock /var/run/cloudflared/update.lock （防并发）
            ├─ GitHub API /releases/latest → tag_name + 资产 digest/size
            ├─ 检查 /tmp 空间、MemAvailable、/usr/sbin 剩余空间
            ├─ 下载 cloudflared-linux-<arch> 到 /tmp（可选 download_mirror）
            ├─ sha256sum 对比官方 digest；再跑一次 --version 自检
            ├─ cp 到 /usr/sbin/cloudflared.new → 备份旧版 .bak → 停服务
            ├─ mv 原子替换 → sync → 启动服务
            └─ 写 update.state / update.log / UCI last_update
```

- 所有步骤写入 `/var/run/cloudflared/update.log` 并同步 syslog（`logread -e cloudflared-update`）。
- LuCI 轮询 `status` + `log`（2 秒），任务状态：`pending → running → done / error`。
- 升级在后台运行，**关闭页面不会中断**；`flock` 保证 cron 与手动点击不会打架。
- 中断（信号）时会自动把停掉的隧道重新拉起。
- **GitHub Release CDN 不通时**：在「设置 → 升级设置 → 下载镜像」填镜像前缀（如 `https://gh-proxy.com/`）。镜像只作用于二进制下载 URL，版本元数据与 SHA-256 摘要仍来自 `api.github.com`，校验不会放松；也可以直接安装对应架构的离线包。
- 下载停滞（60 秒内低于 2 KB/s）或总耗时超过 300 秒会主动失败并在状态/日志里给出提示，不会无限卡在「正在下载」。

### 支持的架构与资产

| `uname -m` | 资产 |
| --- | --- |
| `x86_64` | `cloudflared-linux-amd64` |
| `aarch64` | `cloudflared-linux-arm64` |
| `armv7*`, `armv8l` | `cloudflared-linux-armhf` |
| `armv6*`, `armv5*` | `cloudflared-linux-arm` |
| `i386`–`i686` | `cloudflared-linux-386` |
| 其他（mips / riscv…） | 官方未提供 → 界面报错，可设 `arch_override` 手动指定 |

### sysupgrade 之后

`/etc/sysupgrade.conf` 保留配置、Token、init 脚本、两个 CLI 与 LuCI 文件；安装**架构离线包**时还会保留内置的 `/usr/sbin/cloudflared`（离线设备刷机后不用重新下载）。`rc.local` 钩子检测到二进制缺失时，等待网络后调用 `cloudflared-update --restore` 重新下载并启动。
注意：sysupgrade 后包管理器数据库不会保留该包，建议刷机完成后重新安装一次 ipk/apk，使其成为受管包。

---

## 7. UCI 配置

`/etc/config/cloudflared`，两个匿名命名段：

| 段 | 选项 | 默认 | 含义 |
| --- | --- | --- | --- |
| `main` | `enabled` | `0` | 是否启动隧道 |
| | `mode` | `token` | `token` / `config` |
| | `protocol` | `auto` | `auto` / `quic` / `http2` |
| | `loglevel` | `info` | 日志级别 |
| | `metrics_addr` | 空 | 如 `127.0.0.1:20241` |
| | `extra_args` | 空 | 空格分隔的附加参数 |
| | `tune_rmem` | `1` | 设置 `net.core.rmem_max` |
| | `config_file` | `/etc/cloudflared/config.yml` | 本地配置路径 |
| `update` | `channel` | `stable` | `stable` / `preview` / `pinned` |
| | `pinned_version` | 空 | 锁定版本 tag |
| | `auto_update` | `0` | 定时升级开关 |
| | `auto_update_time` | `30 3 * * *` | cron 表达式 |
| | `github_token` | 空 | 提升 API 限流（可选） |
| | `download_mirror` | 空 | Release 资产下载镜像前缀，如 `https://gh-proxy.com/`（可选） |
| | `arch_override` | `auto` | 手动指定资产后缀；架构离线包安装时会锁定为对应架构 |
| | `verify_sha256` | `1` | 校验官方 digest |
| | `keep_backup` | `1` | 保留 `.bak` |
| | `last_update` | 空 | 由升级器写入 |

**Token 不放在 UCI**：UCI 文件默认 0644，任何有读权限的进程都能看到；本项目把它写在 0600 的独立文件里。

---

## 8. 命令行

```sh
cloudflared-ctl status                          # JSON 状态快照（不联网）
cloudflared-ctl check                           # 查询最新版本并刷新缓存
cloudflared-ctl log                             # 最近 200 行升级日志
cloudflared-ctl start-update --latest            # 后台升级到最新正式版
cloudflared-ctl start-update --version 2026.10.7
cloudflared-ctl update-run --force              # 前台同步升级（SSH / cron）
cloudflared-ctl rollback                        # 回滚到 .bak
cloudflared-update --cron                       # cron 入口（对比版本后再下载）
cloudflared-update --restore                    # sysupgrade 后恢复入口
/etc/init.d/cloudflared restart
logread -e cloudflared-update
```

---

## 9. 排障

| 现象 | 排查 |
| --- | --- |
| `Malformed package file` | 说明 ipk 是 `ar` 容器（v1.0.0 的问题）；改用 v1.0.1+ 的 gzip/tar 包，`tar -tzf xxx.ipk` 应列出 `./debian-binary ./control.tar.gz ./data.tar.gz` |
| 安装成功但文件没落地 | 包内含 PAX `PaxHeader/` 条目；用本仓库 `scripts/make-ipk.sh` 重新构建（纯 USTAR），别用系统 `tar` 直接打 |
| `awk: bad regex … Invalid contents of {}` | 旧版 `cloudflared-ctl` 的 JSON 切分问题，升级到 v1.0.1+ |
| 菜单不显示 | 确认 `/usr/share/rpcd/acl.d/luci-app-cloudflared.json` 存在且 `rpcd` 已重启；`uci show cloudflared` 能读到配置；浏览器强刷清 LuCI 缓存 |
| 按钮报权限错误 | ACL 未生效，`/etc/init.d/rpcd restart`；确认 `rpcd-mod-file` 与 `luci-base`（cgi-io）已安装 |
| 检查更新失败 | `curl -fsSL https://api.github.com/repos/cloudflare/cloudflared/releases/latest`；未认证 API 限流 60 次/小时，可填 GitHub Token |
| 一直卡在「正在下载」/ 下载失败 | 设备到 GitHub Release CDN 不通：① 直接装对应架构的离线包（推荐）；② 在「设置 → 升级设置 → 下载镜像」填 `https://gh-proxy.com/` 等前缀。升级页会显示当前下载源 |
| 装了架构包但没有二进制 | `uname -m` 与包架构不匹配，`postinst` 主动删除了内置二进制；`logread -e cloudflared` 有记录，换对应架构的包重装即可 |
| 下载成功但服务不运行 | 看 `logread`；Token 是否粘贴、config.yml 是否填了 `tunnel:`、是否点了「启用隧道」 |
| 提示架构不支持 | 官方没有 mips/riscv 二进制；确认 `uname -m` 与 `arch_override` |
| 空间/内存不足 | 升级器会保留旧版本并写明缺多少 KB；清理 flash 或改用外置存储后重试 |
| 升级后异常 | 升级页「回滚到上一版本」，或 `cloudflared-ctl rollback` |

---

## 10. 开发

```sh
sh scripts/check.sh                       # sh -n / JS 语法 / JSON 校验
sh scripts/make-ipk.sh                    # 通用包 _all.ipk
sh scripts/fetch-binaries.sh              # 拉取 5 个架构官方二进制并校验 SHA-256
sh scripts/make-ipk.sh --all              # 通用包 + 5 个架构离线包
sh scripts/make-ipk.sh --arch armhf       # 只构建指定架构包
MIRROR=https://gh-proxy.com/ sh scripts/fetch-binaries.sh   # 本机下载不通时走镜像
tar -tzf dist/luci-app-cloudflared_1.1.0-1_all.ipk         # 查看外层包内容
```

`scripts/fetch-binaries.sh` 从 GitHub API 读取每个资产的 `digest` 并逐一校验，产物在 `dist/bin/`（含 `manifest.json`，记录 tag / digest / size）；`--all` 构建时会再次校验，任何一个二进制与官方摘要不符就中止。`dist/` 与 `dist/bin/` 已被 `.gitignore` 排除，不会把 100 MB 二进制提交进仓库。

CI 在每次 push 跑静态检查、shellcheck（仅 error 级别）并产出通用包；在 `v*` tag 或手动触发时额外构建全部分架构包并上传产物。UI 文案用 `_()` 包裹，便于后续补 `.po` 翻译。

---

## 11. 许可与致谢

- 本项目 MIT，见 [LICENSE](LICENSE)。
- `cloudflared` 是 Cloudflare 的产品，二进制均取自其官方 GitHub Release，本项目不修改；架构离线包只是把原样文件与官方 SHA-256 摘要一起打包，运行时的一键升级仍会校验官方 digest。
- 设计参考：[Coralesoft/OpenwrtCloudflare](https://github.com/Coralesoft/OpenwrtCloudflare)、[OpenWrt LuCI](https://github.com/openwrt/luci) 的 JS view / ACL 规范。
