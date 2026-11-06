'use strict';
'require view';
'require dom';
'require poll';
'require ui';
'require view.cloudflared.common as cf';

return view.extend({
	load: function() {
		return Promise.all([cf.status(), cf.log()]);
	},

	render: function(data) {
		var st = data[0] || {};
		var logText = data[1] || '';
		var fields = {};
		var self = this;

		function row(label, key, value) {
			return cf.row(label, key, value, fields);
		}

		function text(key, value) {
			if (fields[key]) fields[key].textContent = value || '—';
		}

		var logArea = E('textarea', {
			'id': 'cf-log',
			'class': 'cbi-input-textarea',
			'readonly': 'readonly',
			'wrap': 'off',
			'style': 'width:100%;min-height:180px;font-family:monospace;font-size:12px;'
		}, logText);

		function applyStatus(s) {
			s = s || {};
			dom.content(fields.running, [
				s.running ? cf.badge('● 运行中 PID ' + (s.pid || '?'), 'ok') : cf.badge('○ 已停止', 'err')
			]);
			dom.content(fields.enabled, [
				s.enabled ? cf.badge('开机自启已开启', 'ok') : cf.badge('开机自启已关闭', 'warn')
			]);
			text('version', s.version || '未安装（请在「升级」页安装）');
			text('latest', s.latest || '尚未检查');
			text('checked', cf.time(s.latest_checked));
			text('arch', (s.arch || '—') + '  /  ' + (s.asset || '—'));
			text('channel', s.channel || 'stable');
			dom.content(fields.tunnel, [
				s.mode === 'config'
					? (s.config_valid ? cf.badge('config.yml 已配置', 'ok') : cf.badge('config.yml 未填写', 'warn'))
					: (s.token_set ? cf.badge('Token 已保存', 'ok') : cf.badge('Token 未设置', 'warn'))
			]);
			dom.content(fields.backup, [
				s.backup_version ? cf.badge('可回滚 ' + s.backup_version, 'idle') : cf.badge('无备份', 'idle')
			]);
			dom.content(fields.update, [
				s.update_state === 'running' || s.update_state === 'pending'
					? cf.badge('升级进行中', 'warn')
					: (s.update_state === 'error' ? cf.badge('上次升级失败', 'err')
						: (s.update_state === 'done' ? cf.badge('已完成', 'ok') : cf.badge('空闲', 'idle')))
			]);
			text('message', s.update_message || '—');
			text('last', s.last_update || '—');
		}

		function withBusy(button, promise) {
			button.disabled = true;
			return Promise.resolve(promise)
				.catch(function(e) { cf.notify('操作失败：' + e, 'error'); })
				.then(function() { button.disabled = false; return self.refresh(); });
		}

		var startBtn = cf.button(_('启动'), function(ev) {
			return withBusy(ev.target, cf.service('start'));
		}, 'cbi-button-neutral');
		var stopBtn = cf.button(_('停止'), function(ev) {
			return withBusy(ev.target, cf.service('stop'));
		}, 'cbi-button-neutral');
		var restartBtn = cf.button(_('重启'), function(ev) {
			return withBusy(ev.target, cf.service('restart'));
		}, 'cbi-button-neutral');
		var checkBtn = cf.button(_('检查最新版本'), function(ev) {
			return withBusy(ev.target, cf.check().then(function(res) {
				if (res.ok)
					cf.notify('最新版本：' + res.tag + (res.update_available ? '（可升级）' : '（已是最新）'), 'info');
				else
					cf.notify('检查失败：' + (res.error || '未知错误'), 'error');
			}));
		});

		var node = E('div', { 'class': 'cbi-map' }, [
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-descr' },
					_('Cloudflared 隧道运行状态。二进制由本插件从 Cloudflare 官方 GitHub Release 下载并校验，不随固件打包。')),
				row(_('服务状态'), 'running', '—'),
				row(_('开机自启'), 'enabled', '—'),
				row(_('已安装版本'), 'version', '—'),
				row(_('最新版本'), 'latest', '—'),
				row(_('最近检查时间'), 'checked', '—'),
				row(_('架构 / 下载资产'), 'arch', '—'),
				row(_('更新通道'), 'channel', '—'),
				row(_('隧道凭据'), 'tunnel', '—'),
				row(_('备份版本'), 'backup', '—'),
				row(_('升级任务'), 'update', '—'),
				row(_('任务消息'), 'message', '—'),
				row(_('上次升级'), 'last', '—')
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('快捷操作')),
				E('div', { 'class': 'control-group' }, [
					startBtn, ' ', stopBtn, ' ', restartBtn, ' ', checkBtn, ' ',
					E('a', {
						'class': 'cbi-button cbi-button-action',
						'href': L.url('admin/services/cloudflared/update')
					}, _('前往升级页面'))
				])
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('最近升级日志')),
				logArea
			])
		]);

		this.refresh = function() {
			return Promise.all([cf.status(), cf.log()]).then(function(res) {
				applyStatus(res[0]);
				var atBottom = logArea.scrollHeight - logArea.scrollTop - logArea.clientHeight < 30;
				logArea.value = res[1] || '';
				if (atBottom) logArea.scrollTop = logArea.scrollHeight;
			}).catch(function() {});
		};

		applyStatus(st);
		this._pollFn = this.refresh;
		poll.add(this._pollFn, 4);

		return node;
	},

	unload: function() {
		if (this._pollFn) {
			poll.remove(this._pollFn);
			this._pollFn = null;
		}
	}
});
