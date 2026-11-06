'use strict';
'require baseclass';
'require fs';
'require ui';

/*
 * Shared helpers for the three Cloudflared views.
 * LuCI modules must return a class, so this is a baseclass singleton whose
 * methods are exposed on the instance (cf.status(), cf.check(), ...).
 */
return baseclass.extend({
	CTL: '/usr/sbin/cloudflared-ctl',

	/* All backend calls go through cgi-exec so long upgrades can stream. */
	ctl: function(args, type, withStderr) {
		return L.resolveDefault(
			fs.exec_direct(this.CTL, args || [], type || 'text', false, withStderr === true),
			type === 'json' ? {} : ''
		).catch(function() {
			return type === 'json' ? { ok: false, error: '后端调用失败' } : '';
		});
	},

	status: function() {
		return this.ctl(['status'], 'json').then(function(res) {
			return (res && typeof res === 'object') ? res : {};
		});
	},

	check: function() {
		return this.ctl(['check'], 'json').then(function(res) {
			return (res && typeof res === 'object') ? res : { ok: false, error: '返回格式错误' };
		});
	},

	log: function() {
		return this.ctl(['log'], 'text', true);
	},

	service: function(action) {
		return L.resolveDefault(
			fs.exec_direct('/etc/init.d/cloudflared', [action], 'text', false, true),
			''
		);
	},

	notify: function(message, type) {
		ui.addNotification(null, E('p', {}, message), type || 'info');
	},

	badge: function(text, state) {
		var colors = {
			ok: '#2e7d32',
			err: '#b00020',
			warn: '#b26a00',
			idle: '#546e7a'
		};
		return E('span', {
			'style': 'display:inline-block;padding:2px 9px;border-radius:10px;' +
				'font-size:12px;font-weight:600;color:#fff;background:' + (colors[state] || colors.idle)
		}, text);
	},

	bytes: function(n) {
		var v = Number(n) || 0;
		if (v < 1024) return v + ' B';
		if (v < 1048576) return (v / 1024).toFixed(1) + ' KB';
		return (v / 1048576).toFixed(1) + ' MB';
	},

	time: function(ts) {
		var v = Number(ts) || 0;
		if (v <= 0) return '—';
		return new Date(v * 1000).toLocaleString();
	},

	button: function(label, handler, style) {
		return E('button', {
			'class': 'cbi-button ' + (style || 'cbi-button-action'),
			'click': handler
		}, label);
	},

	row: function(label, key, initial, store) {
		var holder = E('span', { 'id': 'cf-' + key }, initial);
		store[key] = holder;
		return E('div', { 'class': 'cbi-value' }, [
			E('label', { 'class': 'cbi-value-title' }, label),
			E('div', { 'class': 'cbi-value-field' }, holder)
		]);
	}
});
