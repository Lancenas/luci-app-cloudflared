# Changelog

## 1.0.1 (2026-11-06)

真机安装测试后修复（Kwrt 24.10-SNAPSHOT / x86_64 / QEMU，opkg + nginx + LuCI 26.x）：

- **修复 ipk 根本装不上**：v1.0.0 误把 `.ipk` 打成 Debian `ar` 容器；官方格式是 gzip 压缩的 tar（已用 OpenWrt 24.10 官方 feed 样本 `1f 8b` 文件头与 opkg `deb_extract()` 源码核实）。`opkg install` 曾报 `pkg_init_from_file: Malformed package file`。
- **修复 macOS 构建包「安装成功但没有文件」**：bsdtar 写入的 PAX `PaxHeader/` 条目被 opkg 记录成真实文件；打包器改为 Python 生成纯 USTAR，并在构建时自检禁止 PAX / AppleDouble 条目。
- **修复 `check` 在 busybox awk 上失败**：`split_objects()` 的 `gsub(/},{/ …)` 触发 `awk: bad regex … Invalid contents of {}`，导致误报「版本没有提供资产」；改用 POSIX sed 插入换行，资产匹配改用 grep。
- CI 改为校验 gzip/tar 外层成员与 PAX，不再用 `ar t`。
- 已在真机完整验证：菜单/JS/ACL、一键升级（SHA-256 + 自检 + 备份）、指定 tag 降级、界面回滚、UCI 保存后 procd reload。

## 1.0.0 (2026-11-06)

> 已废弃，请勿使用（ipk 容器格式错误 + busybox awk 解析失败），升级到 1.0.1。

- 首个可用版本：标准 OpenWrt 软件包（`PKGARCH:=all`），UCI 配置 + procd 服务。
- LuCI 三个页面：状态、设置、升级（现代 JavaScript view + menu.d + rpcd ACL）。
- 「升级到最新版」：GitHub `/releases/latest` → 资产 digest SHA-256 校验 → 二进制自检 → 原子替换 → 重启隧道。
- 后台升级任务（`flock` 防并发）、实时日志、状态轮询、中断自动恢复服务。
- 升级通道 `stable` / `preview` / `pinned` 与指定 tag 升级；可选 GitHub Token 提升 API 限流。
- 备份 `/usr/sbin/cloudflared.bak` 与界面一键回滚。
- 定时自动升级（cron，由 UCI 开关与表达式生成）。
- Token 文件 0600 + `--token-file`；`config.yml` 界面编辑。
- 架构自动识别（amd64 / arm64 / armhf / arm / 386）与 `arch_override`。
- sysupgrade 保留清单 + `rc.local` 恢复钩子。
- `scripts/make-ipk.sh` 免 SDK 打 noarch ipk；SSH 直装/卸载脚本；本地静态检查与 CI。
