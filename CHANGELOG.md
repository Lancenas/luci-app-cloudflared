# Changelog

## 1.0.0 (2026-11-06)

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
