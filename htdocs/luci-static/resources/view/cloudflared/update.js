'use strict';
'require view';
'require dom';
'require poll';
'require uci';
'require ui';
'require view.cloudflared.common as cf';

return view.extend({
	load: function() {
		return Promise.all([
			cf.status(),
			cf.log(),
			uci.load('cloudflared').catch(function() { return null; })
		]);
	},

	render: function(data) {
		var fields = {};
		var self = this;

		function row(label, key, initial) {
			return cf.row(label, key, initial, fields);
		}

		function text(key, value) {
			if (fields[key]) fields[key].textContent = value || '—';
		}

		var logArea = E('textarea', {
			'id': 'cf-update-log',
			'class': 'cbi-input-textarea',
			'readonly': 'readonly',
			'wrap': 'off',
			'style': 'width:100%;min-height:300px;font-family:monospace;font-size:12px;'
		}, data[1] || '');

		var versionInput = E('input', {
			'type': 'text',
			'class': 'cbi-input-text',
			'placeholder': '2026.10.7',
			'style': 'width:190px'
		});

		var busy = [];

		function applyStatus(s) {
			s = s || {};
			text('version', s.version || '未安装');
			text('latest', s.latest || '尚未检查');
			text('checked', cf.time(s.latest_checked));
			text('asset', (s.asset || '—') + '  /  ' + (s.arch || '—'));
			text('size', s.latest_size ? cf.bytes(s.latest_size) : '—');
			text('digest', s.latest_digest ? s.latest_digest.substring(0, 16) + '…' : '—');
			text('channel', uci.get('cloudflared', 'update', 'channel') || 'stable');
			text('last', s.last_update || '—');
			text('verify', s.verify_sha256 === '0' || s.verify_sha256 === 0
				? '已关闭（不推荐）' : '开启（校验 GitHub Release digest）');
			text('mirror', s.download_mirror || '官方直连（未设置镜像）');

			var state = s.update_state || 'idle';
			dom.content(fields.state, [
				state === 'running' || state === 'pending' ? cf.badge('● 升级进行中', 'warn')
					: (state === 'error' ? cf.badge('● 上次失败', 'err')
						: (state === 'done' ? cf.badge('● 已完成', 'ok') : cf.badge('○ 空闲', 'idle')))
			]);
			text('message', s.update_message || '—');

			var isBusy = (state === 'running' || state === 'pending');
			busy.forEach(function(btn) { btn.disabled = isBusy; });
		}

		function refresh() {
			return Promise.all([cf.status(), cf.log()]).then(function(res) {
				applyStatus(res[0]);
				var atBottom = logArea.scrollHeight - logArea.scrollTop - logArea.clientHeight < 30;
				logArea.value = res[1] || '';
				if (atBottom) logArea.scrollTop = logArea.scrollHeight;
			}).catch(function() {});
		}

		function action(btn, args, message) {
			btn.disabled = true;
			return cf.ctl(args, 'json').then(function(res) {
				if (!res || res.ok === false)
					cf.notify(_('操作失败：') + ((res && res.error) || '后端无响应'), 'error');
				else
					cf.notify(message, 'info');
			}).catch(function(e) {
				cf.notify(_('操作失败：') + e, 'error');
			}).then(function() {
				return refresh();
			});
		}

		var checkBtn = cf.button(_('检查最新版本'), function(ev) {
			ev.target.disabled = true;
			return cf.check().then(function(res) {
				if (res.ok) {
					cf.notify(_('最新版本：') + res.tag + '（' + cf.bytes(res.size) + '）' +
						(res.update_available ? _('，可升级') : _('，已是最新')), 'info');
				} else {
					cf.notify(_('检查失败：') + (res.error || '未知错误'), 'error');
				}
			}).catch(function(e) {
				cf.notify(_('检查失败：') + e, 'error');
			}).then(function() { ev.target.disabled = false; return refresh(); });
		}, 'cbi-button-neutral');

		var latestBtn = cf.button(_('升级到最新版（stable）'), function(ev) {
			return action(ev.target, ['start-update', '--latest', '--force'],
				_('已开始升级到最新正式版，下方日志会实时刷新。'));
		});

		var channelBtn = cf.button(_('按当前通道升级'), function(ev) {
			return action(ev.target, ['start-update', '--force'],
				_('已按设置的通道开始升级。'));
		}, 'cbi-button-neutral');

		var versionBtn = cf.button(_('升级到指定版本'), function(ev) {
			var tag = (versionInput.value || '').trim();
			if (!/^[A-Za-z0-9._-]+$/.test(tag)) {
				cf.notify(_('请输入合法版本号，例如 2026.10.7'), 'error');
				return;
			}
			return action(ev.target, ['start-update', '--version', tag, '--force'],
				_('已开始升级到 ') + tag);
		}, 'cbi-button-neutral');

		var rollbackBtn = cf.button(_('回滚到上一版本'), function(ev) {
			return action(ev.target, ['rollback'], _('已回滚到备份版本。'));
		}, 'cbi-button-neutral');

		busy.push(latestBtn, channelBtn, versionBtn, rollbackBtn);

		var node = E('div', { 'class': 'cbi-map' }, [
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-descr' },
					_('从 Cloudflare 官方 GitHub Release 下载对应架构的 cloudflared，校验 SHA-256 后原子替换，并保留上一版本以便回滚。')),
				row(_('已安装版本'), 'version', '—'),
				row(_('最新版本'), 'latest', '—'),
				row(_('最近检查时间'), 'checked', '—'),
				row(_('更新通道'), 'channel', '—'),
				row(_('目标资产 / 架构'), 'asset', '—'),
				row(_('发布包大小'), 'size', '—'),
				row(_('官方 SHA-256'), 'digest', '—'),
				row(_('完整性校验'), 'verify', '—'),
				row(_('下载镜像'), 'mirror', '—'),
				row(_('升级任务状态'), 'state', '—'),
				row(_('任务消息'), 'message', '—'),
				row(_('上次升级时间'), 'last', '—')
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('升级操作')),
				E('div', { 'class': 'control-group' }, [
					checkBtn, ' ', latestBtn, ' ', channelBtn
				]),
				E('div', { 'class': 'control-group', 'style': 'margin-top:8px' }, [
					versionInput, ' ', versionBtn, ' ', rollbackBtn, ' ',
					E('a', {
						'class': 'cbi-button cbi-button-neutral',
						'href': 'https://github.com/cloudflare/cloudflared/releases',
						'target': '_blank',
						'rel': 'noreferrer noopener'
					}, _('查看 GitHub Releases'))
				]),
				E('div', { 'class': 'cbi-section-descr' },
					_('升级过程在后台运行（flock 防并发），即使关闭页面也会继续；完成后自动重启隧道服务。'))
			]),
			E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('实时升级日志')),
				logArea
			])
		]);

		this.refresh = refresh;
		applyStatus(data[0] || {});
		this._pollFn = refresh;
		poll.add(this._pollFn, 2);

		return node;
	},

	unload: function() {
		if (this._pollFn) {
			poll.remove(this._pollFn);
			this._pollFn = null;
		}
	}
});
