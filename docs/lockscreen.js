/* lockscreen.js — 锁屏「正在播放」卡片 + 后台保活
 *
 * 原理：iOS 只让「有音频在播」的页面占据锁屏媒体卡，并且锁屏后仍会继续跑 JS。
 * 所以这里放一段几乎听不见的循环音频（幅度 1/32768，约 -90dB），再用
 * Media Session API 把计时信息写到锁屏 / 控制中心上。
 *
 * 副作用（必须让用户知道）：
 *   - 会占用系统音频会话，正在放的歌会被顶掉
 *   - 锁屏卡片上会显示「分段计时」
 */
(function (root) {
  'use strict';

  var RATE = 8000;
  var SECONDS = 10;

  var audio = null;
  var url = null;
  var on = false;
  var handlers = {};
  var lastMeta = null;
  var lastArt = null;
  var artUrl = null;

  function supported() {
    return !!(root.MediaMetadata && root.navigator && root.navigator.mediaSession);
  }

  /* 把倒计时数字画成一张图，塞进锁屏卡片的封面位。
   * 锁屏卡片上标题字小、封面位最大，所以「满屏」只能靠封面图。
   * progress 传 null 时不画环（正计时没有总时长，画满环会误导）。 */
  function renderArtwork(text, sub, warm, progress) {
    var hasRing = typeof progress === 'number';
    var key = text + '|' + (sub || '') + '|' + (warm ? 'w' : 'c') + '|' + (hasRing ? progress.toFixed(3) : '-');
    if (key === lastArt && artUrl) return artUrl;

    var S = 512;
    var cv = document.createElement('canvas');
    cv.width = S;
    cv.height = S;
    var g = cv.getContext('2d');

    g.fillStyle = '#07090F';
    g.fillRect(0, 0, S, S);

    var grd = g.createRadialGradient(S / 2, S * 0.42, 0, S / 2, S * 0.42, S * 0.72);
    grd.addColorStop(0, warm ? 'rgba(245,196,107,0.18)' : 'rgba(94,234,212,0.18)');
    grd.addColorStop(1, 'rgba(7,9,15,0)');
    g.fillStyle = grd;
    g.fillRect(0, 0, S, S);

    var cx = S / 2;
    var cy = S * 0.44;
    var r = S * 0.36;

    /* 进度环：跟主界面一样，剩下的时间越少环越短 */
    if (hasRing) {
      g.lineWidth = S * 0.026;
      g.strokeStyle = 'rgba(255,255,255,0.10)';
      g.beginPath();
      g.arc(cx, cy, r, 0, Math.PI * 2);
      g.stroke();

      if (progress > 0.001) {
        g.strokeStyle = warm ? '#F5C46B' : '#5EEAD4';
        g.lineCap = 'round';
        g.beginPath();
        g.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress);
        g.stroke();
      }
    }

    /* 数字太长就自动缩字号，保证不溢出环 */
    var size = text.length <= 4 ? S * 0.30 : (text.length <= 5 ? S * 0.25 : S * 0.20);
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillStyle = '#EEF2FA';
    g.font = '200 ' + size + 'px -apple-system, "SF Pro Display", "Helvetica Neue", Arial, sans-serif';
    g.fillText(text, cx, cy);

    if (sub) {
      g.fillStyle = warm ? '#F5C46B' : '#5EEAD4';
      g.font = '500 ' + Math.round(S * 0.062) + 'px -apple-system, "SF Pro Text", "PingFang SC", Arial, sans-serif';
      g.fillText(sub, cx, S * 0.90);
    }

    lastArt = key;
    artUrl = cv.toDataURL('image/png');
    return artUrl;
  }

  /* 生成 10 秒极低幅度 WAV：人耳听不见，但音频会话是真实活跃的 */
  function silentWavUrl() {
    var n = RATE * SECONDS;
    var buf = new ArrayBuffer(44 + n * 2);
    var v = new DataView(buf);

    function str(off, s) {
      for (var i = 0; i < s.length; i++) v.setUint8(off + i, s.charCodeAt(i));
    }

    str(0, 'RIFF');
    v.setUint32(4, 36 + n * 2, true);
    str(8, 'WAVE');
    str(12, 'fmt ');
    v.setUint32(16, 16, true);
    v.setUint16(20, 1, true);            /* PCM */
    v.setUint16(22, 1, true);            /* 单声道 */
    v.setUint32(24, RATE, true);
    v.setUint32(28, RATE * 2, true);
    v.setUint16(32, 2, true);
    v.setUint16(34, 16, true);
    str(36, 'data');
    v.setUint32(40, n * 2, true);

    for (var i = 0; i < n; i++) {
      v.setInt16(44 + i * 2, (i % 2) ? 1 : -1, true);
    }

    return URL.createObjectURL(new Blob([buf], { type: 'audio/wav' }));
  }

  function bindActions() {
    var ms = root.navigator && root.navigator.mediaSession;
    if (!ms || !ms.setActionHandler) return;

    function set(name, fn) {
      try { ms.setActionHandler(name, fn || null); } catch (e) { /* 不支持的 action 直接跳过 */ }
    }

    set('play', function () { if (handlers.onResume) handlers.onResume(); });
    set('pause', function () { if (handlers.onPause) handlers.onPause(); });
    set('nexttrack', function () { if (handlers.onNext) handlers.onNext(); });
  }

  /* 开始播放保活音频；必须在用户手势里调用，否则 iOS 会拒绝 */
  function enable() {
    if (!supported()) return false;

    if (!audio) {
      url = silentWavUrl();
      audio = new Audio(url);
      audio.loop = true;
      audio.preload = 'auto';
      audio.setAttribute('playsinline', '');
      audio.setAttribute('webkit-playsinline', '');
    }

    var p;
    try { p = audio.play(); } catch (e) { return false; }

    if (p && p.catch) {
      p.catch(function () { on = false; });
    }

    on = true;
    bindActions();
    return true;
  }

  function disable() {
    on = false;
    lastMeta = null;
    if (audio) {
      try { audio.pause(); } catch (e) { /* ignore */ }
    }
    var ms = root.navigator && root.navigator.mediaSession;
    if (ms) {
      try { ms.metadata = null; } catch (e) { /* ignore */ }
      try { ms.playbackState = 'none'; } catch (e) { /* ignore */ }
    }
  }

  function isOn() { return on; }

  function configure(next) {
    handlers = next || {};
    if (on) bindActions();
  }

  /* info: { title, subtitle, elapsed, duration, paused, big, warm } */
  function update(info) {
    if (!on || !supported() || !info) return;

    var ms = root.navigator.mediaSession;

    var art = null;
    if (info.big) {
      try {
        /* artProgress 为数字才画环；传 null / undefined 表示没有总时长 */
        var frac = typeof info.artProgress === 'number' ? info.artProgress : null;
        art = renderArtwork(info.big, info.artSub || '', !!info.warm,
          frac == null ? null : Math.max(0, Math.min(1, frac)));
      } catch (e) { art = null; }
    }

    if (!lastMeta || lastMeta.title !== info.title || lastMeta.subtitle !== info.subtitle || lastMeta.art !== art) {
      try {
        var meta = {
          title: info.title,
          artist: info.subtitle || '分段计时',
          album: '分段计时'
        };
        meta.artwork = art
          ? [{ src: art, sizes: '512x512', type: 'image/png' }]
          : [
            { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
            { src: 'icon-512.png', sizes: '512x512', type: 'image/png' }
          ];
        ms.metadata = new root.MediaMetadata(meta);
      } catch (e) { /* ignore */ }
      lastMeta = { title: info.title, subtitle: info.subtitle, art: art };
    }

    try {
      ms.playbackState = info.paused ? 'paused' : 'playing';
    } catch (e) { /* ignore */ }

    /* 只有知道总时长（限时 / 倒计时）才有进度条，正计时不设限时就没有 */
    if (info.duration > 0) {
      try {
        ms.setPositionState({
          duration: info.duration,
          playbackRate: 1,
          position: Math.min(Math.max(0, info.elapsed || 0), info.duration)
        });
      } catch (e) { /* ignore */ }
    }
  }

  root.LockScreen = {
    supported: supported,
    enable: enable,
    disable: disable,
    isOn: isOn,
    configure: configure,
    update: update
  };
})(window);
