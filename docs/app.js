/* 分段计时 · 网页版
 * 逻辑与 iOS 原生版一一对应：
 *   时间永远由「累计时长 + 起跳时刻」推算，不做逐秒累加，
 *   所以切后台、锁屏、关掉再开都不会丢时间。 */
(function () {
  'use strict';

  /* ================= 时间格式 ================= */

  var TimeText = window.TimeText;
  if (!TimeText) {
    document.body.innerHTML = '<p style="padding:40px;color:#888">缺少 time.js，请刷新重试。</p>';
    return;
  }
  var pad = TimeText.pad;

  /* ================= 存储 ================= */

  var STORE_KEY = 'laptimer.v1';

  function loadState() {
    try {
      var raw = localStorage.getItem(STORE_KEY);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (e) {
      return null;
    }
  }

  function saveState() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(state));
    } catch (e) { /* 隐私模式忽略 */ }
  }

  /* 状态结构、默认值与修复逻辑统一在 core.js，避免两处实现走偏 */
  var state = loadState() || {};

  /* ================= 声音 / 触感反馈 ================= */

  var audioCtx = null;

  function ensureAudio() {
    if (audioCtx) return audioCtx;
    try {
      var Ctx = window.AudioContext || window.webkitAudioContext;
      if (!Ctx) return null;
      audioCtx = new Ctx();
    } catch (e) {
      return null;
    }
    return audioCtx;
  }

  function beep(freq, dur, gain) {
    var ctx = ensureAudio();
    if (!ctx) return;
    if (ctx.state === 'suspended') ctx.resume();
    try {
      var osc = ctx.createOscillator();
      var g = ctx.createGain();
      osc.type = 'sine';
      osc.frequency.value = freq;
      g.gain.value = gain == null ? 0.06 : gain;
      osc.connect(g);
      g.connect(ctx.destination);
      var now = ctx.currentTime;
      g.gain.setValueAtTime(g.gain.value, now);
      g.gain.exponentialRampToValueAtTime(0.0001, now + dur);
      osc.start(now);
      osc.stop(now + dur);
    } catch (e) { /* ignore */ }
  }

  var Feedback = {
    tap: function () { beep(660, 0.045, 0.03); },
    lap: function () { beep(880, 0.06, 0.05); },
    toggle: function () { beep(520, 0.05, 0.04); },
    finished: function () {
      beep(880, 0.12, 0.08);
      setTimeout(function () { beep(1180, 0.16, 0.08); }, 150);
      setTimeout(function () { beep(1480, 0.22, 0.08); }, 320);
    },
    limitReached: function () {
      beep(720, 0.1, 0.07);
      setTimeout(function () { beep(720, 0.1, 0.07); }, 190);
      setTimeout(function () { beep(960, 0.2, 0.07); }, 380);
    }
  };

  /* ================= 屏幕常亮 ================= */

  var wakeLock = null;

  function keepAwake(on) {
    if (!('wakeLock' in navigator)) return;
    if (on) {
      if (wakeLock) return;
      navigator.wakeLock.request('screen').then(function (lock) {
        wakeLock = lock;
        lock.addEventListener('release', function () { wakeLock = null; });
      }).catch(function () { /* ignore */ });
    } else if (wakeLock) {
      try { wakeLock.release(); } catch (e) { /* ignore */ }
      wakeLock = null;
    }
  }

  /* ================= 核心逻辑（core.js） ================= */

  var TimerCore = window.TimerCore;
  if (!TimerCore) {
    document.body.innerHTML = '<p style="padding:40px;color:#888">缺少 core.js，请刷新重试。</p>';
    return;
  }

  var engine = TimerCore.create(state, {
    feedback: Feedback,
    persist: function () { saveState(); },
    onChange: function () { renderAll(); },
    onKeepAwake: keepAwake,
    onEvent: function (name) {
      if (name === 'limitReached') {
        toast('已到限时 ' + TimeText.clock(sw.limit) + '，计时继续');
      } else if (name === 'finished') {
        toast('倒计时结束');
      }
    }
  });

  state = engine.state;
  var sw = engine.sw;
  var cd = engine.cd;
  var stopwatch = engine.stopwatch;
  var countdown = engine.countdown;
  var history = engine.history;

  /* ================= DOM ================= */

  function $(id) { return document.getElementById(id); }

  var el = {
    glow: $('glow'),
    modeSeg: $('modeSeg'),
    historyBtn: $('historyBtn'),
    viewStopwatch: $('viewStopwatch'),
    viewCountdown: $('viewCountdown'),
    limitZone: $('limitZone'),
    bigTime: $('bigTime'),
    btMain: $('btMain'),
    btFrac: $('btFrac'),
    subtitle: $('subtitle'),
    lapList: $('lapList'),
    ringProg: $('ringProg'),
    ringStatus: $('ringStatus'),
    ringTime: $('ringTime'),
    ringDur: $('ringDur'),
    presetGrid: $('presetGrid'),
    controls: $('controls'),
    backdrop: $('backdrop'),
    limitSheet: $('limitSheet'),
    limitInput: $('limitInput'),
    limitHint: $('limitHint'),
    limitClear: $('limitClear'),
    limitPresets: $('limitPresets'),
    limitRemove: $('limitRemove'),
    limitDone: $('limitDone'),
    limitCancel: $('limitCancel'),
    durationSheet: $('durationSheet'),
    durInput: $('durInput'),
    durMinus: $('durMinus'),
    durPlus: $('durPlus'),
    durDone: $('durDone'),
    durCancel: $('durCancel'),
    historySheet: $('historySheet'),
    historyBody: $('historyBody'),
    historyDone: $('historyDone'),
    confirmDialog: $('confirmDialog'),
    toast: $('toast'),
    installTip: $('installTip'),
    installTipClose: $('installTipClose')
  };

  var mode = 'stopwatch';
  var historyOpen = false;
  var historyDetail = null;

  /* ================= 渲染：正计时 ================= */

  function renderLimit() {
    var limit = sw.limit;
    if (limit == null) {
      el.limitZone.innerHTML =
        '<button class="limit-empty" id="setLimitBtn">' +
        '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.8">' +
        '<circle cx="12" cy="13" r="8"></circle><path d="M12 9.5V13l2.5 1.6"></path>' +
        '<path d="M9.5 2.5h5"></path></svg>设置限时</button>';
      var btn = $('setLimitBtn');
      if (btn) btn.addEventListener('click', function () { openLimitSheet(); Feedback.tap(); });
      return;
    }

    var elapsed = stopwatch.elapsed();
    var over = elapsed >= limit;
    var progress = limit > 0 ? Math.min(1, elapsed / limit) : 0;
    var usedText = TimeText.clock(Math.min(elapsed, limit)) + ' / ' + TimeText.clock(limit);
    var remainText = over
      ? '已超时 ' + TimeText.clock(elapsed - limit)
      : '剩余 ' + TimeText.clock(limit - elapsed);

    el.limitZone.innerHTML =
      '<div class="limit-bar" id="limitBar">' +
      '<div class="limit-row">' +
      '<span class="limit-label">限时</span>' +
      '<span class="limit-used" id="limitUsed">' + usedText + '</span>' +
      '<span class="limit-remain' + (over ? ' over' : '') + '" id="limitRemain">' + remainText + '</span>' +
      '</div>' +
      '<div class="limit-track"><div class="limit-fill' + (over ? ' over' : '') +
      '" id="limitFill" style="width:' + (progress * 100).toFixed(2) + '%"></div></div>' +
      '</div>';

    var bar = $('limitBar');
    if (bar) bar.addEventListener('click', function () { openLimitSheet(); Feedback.tap(); });
  }

  function updateLimitLive() {
    if (sw.limit == null) return;
    var fill = $('limitFill');
    var used = $('limitUsed');
    var remain = $('limitRemain');
    if (!fill || !used || !remain) { renderLimit(); return; }

    var elapsed = stopwatch.elapsed();
    var over = elapsed >= sw.limit;
    fill.style.width = (Math.min(1, elapsed / sw.limit) * 100).toFixed(2) + '%';
    fill.classList.toggle('over', over);
    used.textContent = TimeText.clock(Math.min(elapsed, sw.limit)) + ' / ' + TimeText.clock(sw.limit);
    remain.textContent = over
      ? '已超时 ' + TimeText.clock(elapsed - sw.limit)
      : '剩余 ' + TimeText.clock(sw.limit - elapsed);
    remain.classList.toggle('over', over);
  }

  function renderSubtitle() {
    if (sw.sessionStart == null) {
      el.subtitle.textContent = sw.limit != null
        ? '限时 ' + TimeText.clock(sw.limit) + ' · 点「开始」计时，随时可记段'
        : '点「开始」计时，随时可记段';
      return;
    }
    var startText = TimeText.clockTime(sw.sessionStart);
    if (sw.isRunning) {
      el.subtitle.textContent = startText + ' 开始 · 第 ' + (sw.laps.length + 1) + ' 段进行中';
    } else {
      el.subtitle.textContent = startText + ' 开始 · 已暂停 · 共 ' + sw.laps.length + ' 段';
    }
  }

  function lapRowHTML(lap) {
    var delta = stopwatch.deltaFor(lap);
    var fastest = lap.id === stopwatch.fastestId();
    var cls = 'lap-row' + (fastest ? ' fastest' : '');
    var deltaText = '—';
    var deltaCls = 'muted';
    if (delta != null) {
      if (fastest) { deltaText = '最快'; deltaCls = 'fast'; }
      else {
        deltaText = TimeText.delta(delta);
        deltaCls = delta > 1 ? 'slow' : (delta < -1 ? 'better' : '');
      }
    }
    return '<div class="' + cls + '">' +
      '<span class="c-idx">' + pad(lap.index) + '</span>' +
      '<span class="c-split">' + TimeText.lap(lap.split) + '</span>' +
      '<span class="c-total">' + TimeText.lap(lap.total) + '</span>' +
      '<span class="c-delta ' + deltaCls + '">' + deltaText + '</span>' +
      '</div>';
  }

  function renderLaps() {
    if (!sw.laps.length && !stopwatch.hasSession()) {
      el.lapList.innerHTML =
        '<div class="lap-empty">' +
        '<div class="flag">⚑</div>' +
        '<div class="t1">还没有分段</div>' +
        '<div class="t2">开始后点「记段」，每段用时与累计会记在这里。</div>' +
        '</div>';
      return;
    }

    var html = '';
    if (stopwatch.hasSession()) {
      html += '<div class="lap-row live" id="liveRow">' +
        '<span class="c-idx">' + pad(sw.laps.length + 1) + '</span>' +
        '<span class="c-split" id="liveSplit">' + TimeText.lap(stopwatch.liveSplit()) + '</span>' +
        '<span class="c-total">' + (sw.isRunning ? '进行中' : '已暂停') + '</span>' +
        '<span class="c-delta">—</span>' +
        '</div>';
    }
    for (var i = sw.laps.length - 1; i >= 0; i--) {
      html += lapRowHTML(sw.laps[i]);
    }
    el.lapList.innerHTML = html;
  }

  /* ================= 渲染：倒计时 ================= */

  var CD_PRESETS = [1, 3, 5, 10, 15, 25, 45, 60];

  function renderPresets() {
    var show = !countdown.hasStarted();
    el.presetGrid.classList.toggle('is-hidden', !show);
    if (!show) return;
    var html = '';
    var minutes = Math.round(cd.duration / 60);
    for (var i = 0; i < CD_PRESETS.length; i++) {
      var v = CD_PRESETS[i];
      html += '<button class="preset' + (v === minutes ? ' is-on' : '') + '" data-min="' + v + '">' + v + '′</button>';
    }
    html += '<button class="custom-link" id="customDurBtn">自定义时长</button>';
    el.presetGrid.innerHTML = html;
  }

  function renderCountdownRing() {
    var C = 2 * Math.PI * 130;
    var p = countdown.progress();
    /* 必须写内联样式：CSS 里的 stroke-dashoffset 优先级高于同名的表现属性 */
    el.ringProg.style.strokeDasharray = C.toFixed(1);
    el.ringProg.style.strokeDashoffset = (C * (1 - p)).toFixed(1);
    el.ringProg.classList.toggle('done', countdown.isFinished());
  }

  function updateCountdownLive() {
    var remaining = countdown.remaining();
    el.ringTime.textContent = TimeText.countdown(remaining);
    el.ringTime.classList.toggle('done', countdown.isFinished());
    renderCountdownRing();
  }

  function renderCountdownStatus() {
    if (countdown.isFinished()) el.ringStatus.textContent = '已结束';
    else if (cd.isRunning) el.ringStatus.textContent = '倒计时中';
    else if (countdown.hasStarted()) el.ringStatus.textContent = '已暂停';
    else el.ringStatus.textContent = '准备就绪';
    el.ringDur.textContent = '时长 ' + TimeText.clock(cd.duration);
  }

  /* ================= 渲染：底部按钮 ================= */

  var ICON = {
    stop: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><rect x="6" y="6" width="12" height="12" rx="2.5"/></svg>',
    reset: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M3.6 12a8.4 8.4 0 1 0 2.6-6.1"></path><path d="M3.3 4.8v4.5h4.5"></path></svg>',
    pause: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><rect x="7" y="5.5" width="3.6" height="13" rx="1.4"/><rect x="13.4" y="5.5" width="3.6" height="13" rx="1.4"/></svg>',
    play: '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M8 5.6c0-.8.9-1.3 1.6-.9l8 6.4a1.1 1.1 0 0 1 0 1.8l-8 6.4c-.7.4-1.6 0-1.6-.9V5.6Z"/></svg>',
    timer: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="13" r="8"></circle><path d="M12 9.5V13l2.5 1.6"></path><path d="M9.5 2.5h5"></path></svg>',
    plus: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 6v12M6 12h12"></path></svg>',
    slider: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M4 8h9M17 8h3M4 16h3M11 16h9"></path><circle cx="15" cy="8" r="2"></circle><circle cx="9" cy="16" r="2"></circle></svg>'
  };

  function renderControls() {
    var html = '';
    if (mode === 'stopwatch') {
      var has = stopwatch.hasSession();
      html += '<button class="circle secondary" id="btnLeft"' +
        ((has || stopwatch.hasAccumulated()) ? '' : ' disabled') + '>' +
        (has ? ICON.stop : ICON.reset) + '<span>' + (has ? '结束' : '重置') + '</span></button>';

      html += has
        ? '<button class="circle primary" id="btnCenter"><span>记段</span></button>'
        : '<button class="circle primary" id="btnCenter"><span>开始</span></button>';

      if (has) {
        html += '<button class="circle secondary ' + (sw.isRunning ? 'tint-accent' : 'tint-warn') + '" id="btnRight">' +
          (sw.isRunning ? ICON.pause : ICON.play) +
          '<span>' + (sw.isRunning ? '暂停' : '继续') + '</span></button>';
      } else {
        html += '<button class="circle secondary" id="btnRight">' + ICON.timer + '<span>限时</span></button>';
      }
    } else {
      var started = countdown.hasStarted();
      html += '<button class="circle secondary" id="btnLeft">' +
        (started ? ICON.reset : ICON.slider) +
        '<span>' + (started ? '重置' : '自定义') + '</span></button>';

      var centerTitle, centerWarm = false;
      if (countdown.isFinished()) { centerTitle = '再来'; centerWarm = true; }
      else if (cd.isRunning) { centerTitle = '暂停'; centerWarm = true; }
      else if (started) centerTitle = '继续';
      else centerTitle = '开始';

      html += '<button class="circle primary' + (centerWarm ? ' warm' : '') + '" id="btnCenter"><span>' +
        centerTitle + '</span></button>';

      var canExtend = cd.isRunning || started;
      html += '<button class="circle secondary tint-warn" id="btnRight"' +
        (canExtend ? '' : ' disabled') + '>' + ICON.plus + '<span>+1′</span></button>';
    }
    el.controls.innerHTML = html;
    bindControls();
  }

  function bindControls() {
    var left = $('btnLeft');
    var center = $('btnCenter');
    var right = $('btnRight');

    if (left) left.addEventListener('click', function () {
      if (mode === 'stopwatch') {
        if (stopwatch.hasSession()) {
          el.confirmDialog.classList.add('on');
        } else {
          stopwatch.discard();
          toast('已重置');
        }
      } else {
        if (countdown.hasStarted()) { countdown.reset(); }
        else { openDurationSheet(); }
        Feedback.tap();
      }
    });

    if (center) {
      center.addEventListener('click', function () {
        if (mode === 'stopwatch') {
          if (stopwatch.hasSession()) stopwatch.addLap();
          else stopwatch.start();
        } else {
          if (countdown.isFinished()) { countdown.reset(); countdown.start(); }
          else if (cd.isRunning) countdown.pause();
          else if (countdown.hasStarted()) countdown.resume();
          else countdown.start();
        }
      });

      if (mode === 'stopwatch' && stopwatch.hasSession()) {
        attachLongPress(center, function () {
          if (!sw.laps.length) return;
          stopwatch.deleteLastLap();
          toast('已撤销最近一段');
        });
      }
    }

    if (right) right.addEventListener('click', function () {
      if (mode === 'stopwatch') {
        if (stopwatch.hasSession()) stopwatch.togglePause();
        else { openLimitSheet(); Feedback.tap(); }
      } else {
        countdown.extend(60);
        Feedback.tap();
      }
    });
  }

  function attachLongPress(node, handler) {
    var timer = null;
    var fired = false;
    function start() {
      fired = false;
      timer = setTimeout(function () {
        fired = true;
        handler();
      }, 550);
    }
    function stop() {
      if (timer) { clearTimeout(timer); timer = null; }
    }
    node.addEventListener('touchstart', start, { passive: true });
    node.addEventListener('touchend', stop);
    node.addEventListener('touchcancel', stop);
    node.addEventListener('mousedown', start);
    node.addEventListener('mouseup', stop);
    node.addEventListener('mouseleave', stop);
    node.addEventListener('click', function (e) {
      if (fired) { e.stopImmediatePropagation(); e.preventDefault(); fired = false; }
    }, true);
  }

  /* ================= Toast ================= */

  var toastTimer = null;

  function toast(text) {
    el.toast.textContent = text;
    el.toast.classList.add('on');
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.toast.classList.remove('on'); }, 1800);
  }

  /* ================= 面板 ================= */

  var openSheet = null;

  function showSheet(node) {
    closeSheet();
    openSheet = node;
    el.backdrop.classList.add('on');
    node.classList.add('on');
  }

  function closeSheet() {
    if (openSheet) openSheet.classList.remove('on');
    openSheet = null;
    el.backdrop.classList.remove('on');
  }

  var LIMIT_PRESETS = [5, 10, 15, 20, 30, 45, 60, 90];

  function renderLimitSheet() {
    el.limitInput.value = sw.limit != null ? TimeText.durationInputText(sw.limit) : '';
    el.limitRemove.classList.toggle('is-hidden', sw.limit == null);

    var html = '';
    for (var i = 0; i < LIMIT_PRESETS.length; i++) {
      html += '<button class="preset-cell" data-min="' + LIMIT_PRESETS[i] + '">' +
        LIMIT_PRESETS[i] + '′</button>';
    }
    el.limitPresets.innerHTML = html;

    el.limitPresets.querySelectorAll('.preset-cell').forEach(function (btn) {
      btn.addEventListener('click', function () {
        el.limitInput.value = btn.getAttribute('data-min');
        el.limitInput.blur();
        validateLimit();
        Feedback.tap();
      });
    });

    validateLimit();
  }

  function validateLimit() {
    var raw = el.limitInput.value;
    var parsed = TimeText.parseDuration(raw);
    el.limitClear.classList.toggle('is-hidden', raw === '');

    el.limitInput.classList.remove('ok', 'bad');
    el.limitHint.classList.remove('ok', 'bad');

    if (raw.trim() === '') {
      el.limitHint.textContent = '纯数字按分钟计算，也可写 1:30 或 90s';
      el.limitDone.disabled = true;
    } else if (parsed != null) {
      el.limitInput.classList.add('ok');
      el.limitHint.classList.add('ok');
      el.limitHint.textContent = '= ' + TimeText.clock(parsed);
      el.limitDone.disabled = false;
    } else {
      el.limitInput.classList.add('bad');
      el.limitHint.classList.add('bad');
      el.limitHint.textContent = '无法识别，试试 30、1:30 或 90s';
      el.limitDone.disabled = true;
    }

    var matched = parsed != null && LIMIT_PRESETS.some(function (v) { return v * 60 === parsed; });
    var target = parsed != null ? parsed / 60 : null;
    el.limitPresets.querySelectorAll('.preset-cell').forEach(function (btn) {
      var on = matched && Number(btn.getAttribute('data-min')) === target;
      btn.classList.toggle('is-on', on);
    });
  }

  function openLimitSheet() {
    renderLimitSheet();
    showSheet(el.limitSheet);
    setTimeout(function () {
      if (sw.limit == null) el.limitInput.focus();
    }, 320);
  }

  function openDurationSheet() {
    el.durInput.value = String(Math.max(1, Math.round(cd.duration / 60)));
    showSheet(el.durationSheet);
  }

  /* ================= 历史 ================= */

  function renderHistory() {
    if (historyDetail) { renderHistoryDetail(historyDetail); return; }

    if (!state.history.length) {
      el.historyBody.innerHTML =
        '<div class="hist-empty">' +
        '<div style="font-size:26px;opacity:.5">◷</div>' +
        '<div class="t1">还没有记录</div>' +
        '<div class="t2">结束一次正计时后，分段会保存在这里。</div>' +
        '</div>';
      return;
    }

    var html = '';
    for (var i = 0; i < state.history.length; i++) {
      var s = state.history[i];
      var fastest = null;
      if (s.laps && s.laps.length) {
        fastest = s.laps[0];
        for (var j = 1; j < s.laps.length; j++) {
          if (s.laps[j].split < fastest.split) fastest = s.laps[j];
        }
      }
      html += '<div class="hist-item" data-id="' + s.id + '">' +
        '<div class="hist-top">' +
        '<span class="hist-total">' + TimeText.clock(s.total) + '</span>' +
        '<span class="hist-count">' + (s.laps ? s.laps.length : 0) + ' 段</span>' +
        '</div>' +
        '<div class="hist-meta">' +
        '<span>' + TimeText.stamp(s.startedAt) + '</span>' +
        (s.limit != null ? '<span>限时 ' + TimeText.clock(s.limit) + '</span>' : '') +
        (fastest ? '<span>最快 ' + TimeText.lap(fastest.split) + '</span>' : '') +
        '</div></div>';
    }
    el.historyBody.innerHTML = html;

    el.historyBody.querySelectorAll('.hist-item').forEach(function (node) {
      node.addEventListener('click', function () {
        var id = node.getAttribute('data-id');
        historyDetail = state.history.filter(function (s) { return s.id === id; })[0] || null;
        renderHistory();
      });
    });
  }

  function renderHistoryDetail(session) {
    var laps = session.laps || [];
    var sum = 0;
    for (var i = 0; i < laps.length; i++) sum += laps[i].split;
    var average = laps.length ? sum / laps.length : null;

    var lines = [];
    lines.push('总计 ' + TimeText.clock(session.total));
    if (session.limit != null) lines.push('限时 ' + TimeText.clock(session.limit));
    if (average != null) lines.push('平均分段 ' + TimeText.lap(average));
    lines.push('共 ' + laps.length + ' 段');
    lines.push('开始 ' + TimeText.stamp(session.startedAt));
    lines.push('结束 ' + TimeText.stamp(session.endedAt));

    var html = '<button class="hist-back" id="histBack">‹ 返回</button>' +
      '<div class="hist-detail-head">' +
      '<div class="big">' + TimeText.clock(session.total) + '</div>' +
      '<div class="sum">' + lines.join('\n') + '</div>' +
      '</div>';

    for (var k = 0; k < laps.length; k++) {
      html += '<div class="hist-lap">' +
        '<span class="i">' + pad(laps[k].index) + '</span>' +
        '<span class="s">' + TimeText.lap(laps[k].split) + '</span>' +
        '<span class="t">' + TimeText.lap(laps[k].total) + '</span>' +
        '</div>';
    }

    html += '<div class="hist-actions">' +
      '<button class="hist-btn" id="histShare">分享分段表</button>' +
      '<button class="hist-btn destructive" id="histDelete">删除</button>' +
      '</div>';

    el.historyBody.innerHTML = html;

    $('histBack').addEventListener('click', function () {
      historyDetail = null;
      renderHistory();
    });

    $('histDelete').addEventListener('click', function () {
      history.remove(session.id);
      historyDetail = null;
      renderHistory();
      toast('已删除');
    });

    $('histShare').addEventListener('click', function () {
      var text = ['计时记录 ' + TimeText.stamp(session.startedAt), lines.join('\n'), '', '段次\t本段\t累计'];
      for (var m = 0; m < laps.length; m++) {
        text.push(laps[m].index + '\t' + TimeText.lap(laps[m].split) + '\t' + TimeText.lap(laps[m].total));
      }
      var payload = text.join('\n');
      if (navigator.share) {
        navigator.share({ title: '计时记录', text: payload }).catch(function () {});
      } else if (navigator.clipboard) {
        navigator.clipboard.writeText(payload).then(function () { toast('已复制到剪贴板'); });
      }
    });
  }

  /* ================= 总渲染 ================= */

  function renderAll() {
    renderLimit();
    renderSubtitle();
    renderLaps();
    renderControls();
    renderPresets();
    renderCountdownStatus();
    renderCountdownRing();
  }

  function setMode(next) {
    if (mode === next) return;
    mode = next;
    el.modeSeg.querySelectorAll('.seg').forEach(function (b) {
      b.classList.toggle('is-on', b.getAttribute('data-mode') === next);
    });
    el.viewStopwatch.classList.toggle('is-hidden', next !== 'stopwatch');
    el.viewCountdown.classList.toggle('is-hidden', next !== 'countdown');
    el.glow.classList.toggle('warm', next === 'countdown');
    renderControls();
  }

  /* ================= 动画帧 ================= */

  var lastSecond = -1;

  function frame() {
    var now = Date.now();

    if (mode === 'stopwatch') {
      var parts = TimeText.stopwatchParts(stopwatch.elapsed(now));
      if (el.btMain.textContent !== parts.main) el.btMain.textContent = parts.main;
      if (el.btFrac.textContent !== '.' + parts.fraction) el.btFrac.textContent = '.' + parts.fraction;
      el.bigTime.classList.toggle('dim', !sw.isRunning && stopwatch.hasSession());

      var live = $('liveSplit');
      if (live) {
        var text = TimeText.lap(stopwatch.liveSplit(now));
        if (live.textContent !== text) live.textContent = text;
      }
      if (sw.limit != null) updateLimitLive();
      if (sw.isRunning) stopwatch.checkLimit();

      var sec = Math.floor(stopwatch.elapsed(now));
      if (sec !== lastSecond) { lastSecond = sec; }
    } else {
      updateCountdownLive();
      if (cd.isRunning) countdown.checkFinished();
    }

    requestAnimationFrame(frame);
  }

  /* ================= 事件绑定 ================= */

  el.modeSeg.addEventListener('click', function (e) {
    var btn = e.target.closest('.seg');
    if (!btn) return;
    setMode(btn.getAttribute('data-mode'));
    Feedback.tap();
  });

  el.historyBtn.addEventListener('click', function () {
    historyDetail = null;
    renderHistory();
    showSheet(el.historySheet);
    Feedback.tap();
  });

  el.historyDone.addEventListener('click', closeSheet);
  el.backdrop.addEventListener('click', closeSheet);

  el.limitCancel.addEventListener('click', closeSheet);
  el.limitDone.addEventListener('click', function () {
    var parsed = TimeText.parseDuration(el.limitInput.value);
    if (parsed == null) return;
    stopwatch.setLimit(parsed);
    closeSheet();
    toast('限时 ' + TimeText.clock(parsed));
  });
  el.limitRemove.addEventListener('click', function () {
    stopwatch.setLimit(null);
    closeSheet();
    toast('已清除限时');
  });
  el.limitClear.addEventListener('click', function () {
    el.limitInput.value = '';
    el.limitInput.focus();
    validateLimit();
    Feedback.tap();
  });
  el.limitInput.addEventListener('input', validateLimit);
  el.limitInput.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      var parsed = TimeText.parseDuration(el.limitInput.value);
      if (parsed != null) {
        stopwatch.setLimit(parsed);
        closeSheet();
        toast('限时 ' + TimeText.clock(parsed));
      }
    }
  });

  el.presetGrid.addEventListener('click', function (e) {
    var btn = e.target.closest('.preset');
    if (btn) {
      countdown.setDuration(Number(btn.getAttribute('data-min')) * 60);
      Feedback.tap();
      return;
    }
    if (e.target.closest('#customDurBtn')) {
      openDurationSheet();
      Feedback.tap();
    }
  });

  el.durCancel.addEventListener('click', closeSheet);
  el.durDone.addEventListener('click', function () {
    var v = Math.max(1, Math.min(600, Math.round(Number(el.durInput.value) || 1)));
    countdown.setDuration(v * 60);
    closeSheet();
    toast('时长 ' + v + ' 分钟');
  });
  el.durMinus.addEventListener('click', function () {
    el.durInput.value = String(Math.max(1, (Math.round(Number(el.durInput.value) || 1)) - 1));
    Feedback.tap();
  });
  el.durPlus.addEventListener('click', function () {
    el.durInput.value = String(Math.min(600, (Math.round(Number(el.durInput.value) || 1)) + 1));
    Feedback.tap();
  });

  $('confirmSave').addEventListener('click', function () {
    el.confirmDialog.classList.remove('on');
    var session = stopwatch.finish();
    if (session) {
      history.add(session);
      toast('已保存 ' + session.laps.length + ' 段');
    }
    renderAll();
  });
  $('confirmDiscard').addEventListener('click', function () {
    el.confirmDialog.classList.remove('on');
    stopwatch.discard();
    toast('已丢弃');
  });
  $('confirmCancel').addEventListener('click', function () {
    el.confirmDialog.classList.remove('on');
  });

  el.installTipClose.addEventListener('click', function () {
    el.installTip.classList.add('is-hidden');
    try { localStorage.setItem('laptimer.tip', '1'); } catch (e) {}
  });

  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') {
      /* 把运行态折叠成「累计 + 起跳时刻」，回来时按墙上时钟重算即可 */
      stopwatch.persistForBackground();
      countdown.persistForBackground();
    } else {
      renderAll();
      if (sw.isRunning) keepAwake(true);
      if (cd.isRunning) keepAwake(true);
    }
  });

  window.addEventListener('pagehide', function () {
    stopwatch.persistForBackground();
    countdown.persistForBackground();
  });

  /* 第一次触摸时解锁音频，否则 iOS 不允许播放 */
  document.addEventListener('touchstart', function once() {
    ensureAudio();
    if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume();
    document.removeEventListener('touchstart', once);
  }, { passive: true });

  /* ================= 启动 ================= */

  function boot() {
    renderAll();
    setMode('stopwatch');
    requestAnimationFrame(frame);

    if (sw.isRunning) keepAwake(true);
    if (cd.isRunning) keepAwake(true);

    var standalone = window.navigator.standalone === true ||
      (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);
    var tipSeen = false;
    try { tipSeen = localStorage.getItem('laptimer.tip') === '1'; } catch (e) {}
    if (!standalone && !tipSeen) {
      setTimeout(function () { el.installTip.classList.remove('is-hidden'); }, 1200);
    }

    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.register('sw.js').catch(function () {});
    }
  }

  boot();
})();
