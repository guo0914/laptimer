/* 计时核心 —— 与 UI 无关，可在 Node 里直接测试。
 *
 * 唯一不变量：时间永远由「累计时长 + 起跳时刻」推算，绝不逐帧累加。
 * 所以切后台、锁屏、关掉再开、甚至改系统时间以外的任何情况都不会丢时间。
 *
 * 与 iOS 版 StopwatchEngine.swift / CountdownEngine.swift 一一对应。 */
(function (root) {
  'use strict';

  function defaultState() {
    return {
      stopwatch: {
        startedAt: null, accumulated: 0, isRunning: false, laps: [],
        limit: null, limitAlerted: false, sessionStart: null, pauseCount: 0
      },
      countdown: {
        duration: 300, startedAt: null, accumulated: 0, isRunning: false, finished: false
      },
      history: []
    };
  }

  function normalize(state) {
    var base = defaultState();
    state = state || {};
    if (!state.stopwatch) state.stopwatch = base.stopwatch;
    if (!state.countdown) state.countdown = base.countdown;
    if (!Array.isArray(state.history)) state.history = [];
    if (state.stopwatch.isRunning && !state.stopwatch.startedAt) {
      state.stopwatch.isRunning = false;
    }
    return state;
  }

  /* 时间取自「累计 + 起跳时刻」。at 为毫秒时间戳。 */
  function elapsedOf(snapshot, at) {
    var value = snapshot.accumulated;
    if (snapshot.isRunning && snapshot.startedAt) {
      value += Math.max(0, (at - snapshot.startedAt) / 1000);
    }
    return Math.max(0, value);
  }

  function create(initialState, opts) {
    opts = opts || {};
    var feedback = opts.feedback || {};
    var persist = opts.persist || function () {};
    var onChange = opts.onChange || function () {};
    var onKeepAwake = opts.onKeepAwake || function () {};
    var onEvent = opts.onEvent || function () {};
    var clock = opts.now || function () { return Date.now(); };

    var state = normalize(initialState);
    var sw = state.stopwatch;
    var cd = state.countdown;

    function save() { persist(state); }
    function changed() { onChange(state); }
    function fire(name, payload) {
      if (typeof feedback[name] === 'function') feedback[name]();
      onEvent(name, payload);
    }

    /* ---------------- 正计时 ---------------- */

    var stopwatch = {
      snapshot: function () { return sw; },

      elapsed: function (at) { return elapsedOf(sw, at == null ? clock() : at); },

      isRunning: function () { return sw.isRunning; },

      hasSession: function () {
        return sw.sessionStart != null || sw.laps.length > 0 || sw.accumulated > 0;
      },

      hasAccumulated: function () { return sw.accumulated > 0; },

      laps: function () { return sw.laps; },

      limit: function () { return sw.limit; },

      liveSplit: function (at) {
        var last = sw.laps.length ? sw.laps[sw.laps.length - 1].total : 0;
        return Math.max(0, stopwatch.elapsed(at) - last);
      },

      limitProgress: function (at) {
        if (sw.limit == null || !(sw.limit > 0)) return null;
        return Math.min(1, stopwatch.elapsed(at) / sw.limit);
      },

      limitRemaining: function (at) {
        if (sw.limit == null) return null;
        return sw.limit - stopwatch.elapsed(at);
      },

      isOverLimit: function (at) {
        if (sw.limit == null) return false;
        return stopwatch.elapsed(at) >= sw.limit;
      },

      /* 相对「此前各段平均值」的偏差；第一段返回 null */
      deltaFor: function (lap) {
        var earlier = sw.laps.filter(function (l) { return l.index < lap.index; });
        if (!earlier.length) return null;
        var sum = earlier.reduce(function (a, l) { return a + l.split; }, 0);
        return lap.split - sum / earlier.length;
      },

      fastestId: function () {
        if (sw.laps.length < 2) return null;
        var best = sw.laps[0];
        for (var i = 1; i < sw.laps.length; i++) {
          if (sw.laps[i].split < best.split) best = sw.laps[i];
        }
        return best.id;
      },

      averageSplit: function () {
        if (!sw.laps.length) return null;
        var sum = sw.laps.reduce(function (a, l) { return a + l.split; }, 0);
        return sum / sw.laps.length;
      },

      start: function () {
        if (sw.isRunning) return;
        if (sw.sessionStart == null) {
          sw.sessionStart = clock();
          sw.laps = [];
          sw.accumulated = 0;
          sw.limitAlerted = false;
        }
        sw.startedAt = clock();
        sw.isRunning = true;
        fire('tap');
        onKeepAwake(true);
        save();
        changed();
      },

      pause: function () {
        if (!sw.isRunning) return;
        sw.accumulated = stopwatch.elapsed();
        sw.startedAt = null;
        sw.isRunning = false;
        sw.pauseCount += 1;
        fire('toggle');
        onKeepAwake(false);
        save();
        changed();
      },

      resume: function () {
        if (sw.isRunning || sw.sessionStart == null) return;
        sw.startedAt = clock();
        sw.isRunning = true;
        fire('toggle');
        onKeepAwake(true);
        save();
        changed();
      },

      togglePause: function () {
        if (sw.isRunning) stopwatch.pause();
        else stopwatch.resume();
      },

      addLap: function () {
        if (sw.sessionStart == null) return null;
        var now = clock();
        var total = stopwatch.elapsed(now);
        var previousTotal = sw.laps.length ? sw.laps[sw.laps.length - 1].total : 0;
        var split = Math.max(0, total - previousTotal);
        var record = {
          id: 'l' + now + '-' + sw.laps.length,
          index: sw.laps.length + 1,
          split: split,
          total: total,
          recordedAt: now
        };
        sw.laps.push(record);
        sw.limitAlerted = sw.limit != null && stopwatch.elapsed(now) >= sw.limit;
        fire('lap');
        save();
        changed();
        return record;
      },

      deleteLastLap: function () {
        if (!sw.laps.length) return;
        sw.laps.pop();
        fire('tap');
        save();
        changed();
      },

      setLimit: function (value) {
        sw.limit = value;
        sw.limitAlerted = value != null && stopwatch.elapsed() >= value;
        save();
        changed();
      },

      /* 结束并返回可入库的会话；没有有效时长时返回 null */
      finish: function () {
        var now = clock();
        var total = stopwatch.elapsed(now);
        var sessionStart = sw.sessionStart;
        var laps = sw.laps.slice();
        var limit = sw.limit;

        stopwatch.resetSnapshot();
        onKeepAwake(false);

        if (sessionStart == null || total <= 0) return null;
        return {
          id: 's' + now,
          startedAt: sessionStart,
          endedAt: now,
          total: total,
          limit: limit,
          laps: laps
        };
      },

      discard: function () {
        stopwatch.resetSnapshot();
        onKeepAwake(false);
        changed();
      },

      resetSnapshot: function () {
        sw.startedAt = null;
        sw.accumulated = 0;
        sw.isRunning = false;
        sw.laps = [];
        sw.limit = null;
        sw.limitAlerted = false;
        sw.sessionStart = null;
        sw.pauseCount = 0;
        save();
      },

      /* 到达限时只提醒，不打断计时 */
      checkLimit: function () {
        if (!sw.isRunning || sw.limit == null || sw.limitAlerted) return false;
        if (stopwatch.elapsed() < sw.limit) return false;
        sw.limitAlerted = true;
        fire('limitReached');
        save();
        return true;
      },

      /* 进入后台：把运行态折叠成累计值，避免依赖计时器 */
      persistForBackground: function () {
        if (sw.isRunning) {
          sw.accumulated = stopwatch.elapsed();
          sw.startedAt = clock();
        }
        save();
      }
    };

    /* ---------------- 倒计时 ---------------- */

    var countdown = {
      snapshot: function () { return cd; },

      elapsed: function (at) { return elapsedOf(cd, at == null ? clock() : at); },

      remaining: function (at) {
        return Math.max(0, cd.duration - countdown.elapsed(at));
      },

      duration: function () { return cd.duration; },

      isRunning: function () { return cd.isRunning; },

      hasStarted: function () {
        return cd.accumulated > 0 || cd.isRunning || cd.finished;
      },

      /* 由真实时钟推算，不能只依赖定时器置位 */
      isFinished: function () {
        if (cd.finished) return true;
        return !cd.isRunning && countdown.hasStarted() && countdown.remaining() <= 0;
      },

      progress: function () {
        if (!(cd.duration > 0)) return 0;
        return Math.min(1, Math.max(0, 1 - countdown.remaining() / cd.duration));
      },

      setDuration: function (value) {
        cd.duration = Math.max(1, value);
        cd.startedAt = null;
        cd.accumulated = 0;
        cd.isRunning = false;
        cd.finished = false;
        save();
        changed();
      },

      start: function () {
        if (cd.isRunning) return;
        if (cd.finished) {
          cd.accumulated = 0;
          cd.finished = false;
        }
        cd.startedAt = clock();
        cd.isRunning = true;
        fire('tap');
        onKeepAwake(true);
        save();
        changed();
      },

      pause: function () {
        if (!cd.isRunning) return;
        cd.accumulated = countdown.elapsed();
        cd.startedAt = null;
        cd.isRunning = false;
        fire('toggle');
        onKeepAwake(false);
        save();
        changed();
      },

      resume: function () {
        if (cd.isRunning || cd.finished) return;
        cd.startedAt = clock();
        cd.isRunning = true;
        fire('toggle');
        onKeepAwake(true);
        save();
        changed();
      },

      reset: function () {
        cd.startedAt = null;
        cd.accumulated = 0;
        cd.isRunning = false;
        cd.finished = false;
        onKeepAwake(false);
        save();
        changed();
      },

      extend: function (seconds) {
        cd.duration += seconds;
        if (cd.finished) {
          cd.finished = false;
          cd.accumulated = Math.min(cd.accumulated, cd.duration - 1);
        }
        save();
        changed();
      },

      checkFinished: function () {
        if (cd.finished) return false;
        if (countdown.remaining() > 0) return false;
        cd.accumulated = cd.duration;
        cd.startedAt = null;
        cd.isRunning = false;
        cd.finished = true;
        fire('finished');
        onKeepAwake(false);
        save();
        changed();
        return true;
      },

      persistForBackground: function () {
        if (cd.isRunning) {
          cd.accumulated = countdown.elapsed();
          cd.startedAt = clock();
        }
        save();
      }
    };

    /* ---------------- 历史 ---------------- */

    var history = {
      list: function () { return state.history; },

      add: function (session) {
        state.history.unshift(session);
        if (state.history.length > 200) state.history.length = 200;
        save();
        changed();
      },

      remove: function (id) {
        state.history = state.history.filter(function (s) { return s.id !== id; });
        save();
        changed();
      },

      get: function (id) {
        return state.history.filter(function (s) { return s.id === id; })[0] || null;
      }
    };

    return {
      state: state,
      sw: sw,
      cd: cd,
      stopwatch: stopwatch,
      countdown: countdown,
      history: history
    };
  }

  var api = { create: create, defaultState: defaultState, normalize: normalize, elapsedOf: elapsedOf };
  root.TimerCore = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
