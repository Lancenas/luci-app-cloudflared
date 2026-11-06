'use strict';
'require view';
'require form';
'require uci';
'require fs';
'require ui';
'require view.cloudflared.common as cf';

var TOKEN_FILE = '/etc/cloudflared/tunnel-token';
var CONFIG_FILE = '/etc/cloudflared/config.yml';

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('cloudflared'),
			L.resolveDefault(fs.read(CONFIG_FILE), ''),
			cf.status()
		]);
	},

	render: function(data) {
		var configText = data[1] || '';
		var st = data[2] || {};
		var m, s, o;

		m = new form.Map('cloudflared', _('Cloudflared 隧道设置'),
			_('所有选项写入 /etc/config/cloudflared，点击「保存并应用」后由 procd 自动重载服务。'));

		/* ---------------- basic tunnel options ---------------- */
		s = m.section(form.NamedSection, 'main', 'cloudflared', _('基本设置'));

		o = s.option(form.Flag, 'enabled', _('启用隧道'),
			_('关闭后 init 脚本不会启动 cloudflared；升级二进制不受影响。'));
		o.default = o.disabled;

		o = s.option(form.ListValue, 'mode', _('隧道模式'),
			_('Token：Cloudflare Zero Trust 远程管理（推荐）；config.yml：本地管理，需要证书 JSON 与 ingress 规则。'));
		o.value('token', _('Token（远程管理）'));
		o.value('config', _('config.yml（本地管理）'));

		o = s.option(form.ListValue, 'protocol', _('传输协议'),
			_('auto 由 cloudflared 自动选择；网络对 UDP 限制较严时可强制 http2。'));
		o.value('auto', 'auto');
		o.value('quic', 'quic');
		o.value('http2', 'http2');

		o = s.option(form.ListValue, 'loglevel', _('日志级别'));
		o.value('debug', 'debug');
		o.value('info', 'info');
		o.value('warn', 'warn');
		o.value('error', 'error');
		o.value('fatal', 'fatal');

		o = s.option(form.Value, 'metrics_addr', _('Metrics 监听地址'),
			_('留空表示关闭；例如 127.0.0.1:20241，可用于 Prometheus 抓取。'));
		o.placeholder = '127.0.0.1:20241';
		o.rmempty = true;

		o = s.option(form.Flag, 'tune_rmem', _('优化 UDP 接收缓冲区'),
			_('启动时设置 net.core.rmem_max=2500000，对 QUIC 隧道有帮助。'));

		o = s.option(form.Value, 'extra_args', _('附加启动参数'),
			_('按空格分隔附加到命令行末尾，例如：--edge-ip-version 4。不支持引号与通配符。'));
		o.rmempty = true;

		o = s.option(form.Value, 'config_file', _('本地配置文件路径'));
		o.default = CONFIG_FILE;

		/* ---------------- update options ---------------- */
		s = m.section(form.NamedSection, 'update', 'update', _('升级设置'),
			_('升级页可一键安装/升级到最新版本；这里控制默认通道、定时升级与安全校验。'));

		o = s.option(form.ListValue, 'channel', _('更新通道'));
		o.value('stable', _('stable — 最新正式版（GitHub releases/latest）'));
		o.value('preview', _('preview — 包含预发布版'));
		o.value('pinned', _('pinned — 锁定指定版本'));

		o = s.option(form.Value, 'pinned_version', _('锁定版本号'),
			_('例如 2026.10.7。定时升级与「按通道升级」都会安装这个版本。'));
		o.placeholder = '2026.10.7';
		o.depends('channel', 'pinned');

		o = s.option(form.Flag, 'auto_update', _('启用定时自动升级'),
			_('写入 /etc/crontabs/root，任务会对比版本后再决定是否下载。'));

		o = s.option(form.Value, 'auto_update_time', _('定时计划（cron 表达式）'),
			_('默认每天 03:30。仅允许数字、* / , - 与字母。'));
		o.value('30 3 * * *', _('每天 03:30'));
		o.value('0 */6 * * *', _('每 6 小时'));
		o.value('30 3 * * 0', _('每周日 03:30'));
		o.default = '30 3 * * *';
		o.depends('auto_update', '1');

		o = s.option(form.Value, 'github_token', _('GitHub Token（可选）'),
			_('未认证时 GitHub API 限流 60 次/小时；填写只读 token 可提升到 5000 次/小时。'));
		o.password = true;
		o.rmempty = true;

		o = s.option(form.ListValue, 'arch_override', _('架构覆盖'),
			_('自动识别 uname -m；异常设备可手动指定官方二进制后缀。mips 等架构官方不提供二进制。'));
		o.value('auto', _('自动识别'));
		o.value('amd64', 'amd64 (x86_64)');
		o.value('arm64', 'arm64 (aarch64)');
		o.value('armhf', 'armhf (armv7 hard-float)');
		o.value('arm', 'arm (armv6/v5)');
		o.value('386', '386 (x86 32-bit)');

		o = s.option(form.Flag, 'verify_sha256', _('校验官方 SHA-256'),
			_('强烈建议开启：安装前比对 GitHub Release 发布的 digest，避免下载到损坏或被篡改的二进制。'));

		o = s.option(form.Flag, 'keep_backup', _('保留上一版本备份'),
			_('保存 /usr/sbin/cloudflared.bak，可在升级页一键回滚。'));

		return m.render().then(function(node) {
			/* ---------------- tunnel token (never stored in UCI) ---------------- */
			var tokenState = E('div', { 'class': 'cbi-section-descr' },
				st.token_set ? _('已保存 Token（0600，仅 root 可读）。粘贴新值将覆盖。')
					: _('尚未保存 Token。请在 Cloudflare Zero Trust → Networks → Tunnels 复制。'));
			var tokenInput = E('input', {
				'type': 'password',
				'class': 'cbi-input-text',
				'autocomplete': 'off',
				'placeholder': _('粘贴 Tunnel Token'),
				'style': 'width:100%;max-width:640px'
			});
			var tokenBtn = cf.button(_('保存 Token 并重启'), function(ev) {
				var value = (tokenInput.value || '').trim();
				if (!value) {
					cf.notify(_('请先粘贴 Token'), 'error');
					return;
				}
				ev.target.disabled = true;
				fs.write(TOKEN_FILE, value + '\n', 384).then(function() {
					tokenInput.value = '';
					tokenState.textContent = _('Token 已更新。');
					cf.notify(_('Token 已写入 /etc/cloudflared/tunnel-token（0600）'), 'info');
					return cf.service('restart');
				}).catch(function(e) {
					cf.notify(_('保存失败：') + e, 'error');
				}).then(function() {
					ev.target.disabled = false;
				});
			});

			node.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('隧道 Token')),
				tokenState,
				E('p', {}, _('Token 不写入 UCI 配置，也不出现在进程命令行（cloudflared ≥ 2025.4.0 使用 --token-file）。')),
				E('div', { 'class': 'cbi-value' }, [
					E('label', { 'class': 'cbi-value-title' }, _('Tunnel Token')),
					E('div', { 'class': 'cbi-value-field' }, [tokenInput, ' ', tokenBtn])
				]),
				E('div', { 'class': 'cbi-section-descr' },
					_('如需切换为本地管理模式，请在上方把「隧道模式」改为 config.yml 并保存并应用。'))
			]));

			/* ---------------- config.yml editor ---------------- */
			var cfgArea = E('textarea', {
				'class': 'cbi-input-textarea',
				'wrap': 'off',
				'spellcheck': 'false',
				'style': 'width:100%;min-height:260px;font-family:monospace;font-size:12px;'
			}, configText);
			var cfgBtn = cf.button(_('保存 config.yml 并重启'), function(ev) {
				ev.target.disabled = true;
				fs.write(CONFIG_FILE, cfgArea.value, 420).then(function() {
					cf.notify(_('config.yml 已保存'), 'info');
					return cf.service('restart');
				}).catch(function(e) {
					cf.notify(_('保存失败：') + e, 'error');
				}).then(function() {
					ev.target.disabled = false;
				});
			});

			node.appendChild(E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('本地 config.yml')),
				E('div', { 'class': 'cbi-section-descr' },
					_('仅在「config.yml（本地管理）」模式下生效。证书 JSON 请用 SSH 放入 /etc/cloudflared/ 并 chmod 600。')),
				cfgArea,
				E('div', { 'class': 'control-group', 'style': 'margin-top:8px' }, [cfgBtn])
			]));

			return node;
		});
	}
});
