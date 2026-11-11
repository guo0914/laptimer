/* 时间格式化与时长解析 —— 与 iOS 版 TimeFormatting.swift 一一对应。
 * 纯函数，无 DOM 依赖，便于在 Node 里直接跑断言。 */
(function (root) {
  'use strict';

  function pad(n, w) {
    w = w || 2;
    var s = String(Math.abs(Math.trunc(n)));
    while (s.length < w) s = '0' + s;
    return (n < 0 ? '-' : '') + s;
  }

  var TimeText = {
    /* 正计时主显示：mm:ss + 百分秒；超过 1 小时变 h:mm:ss */
    stopwatchParts: function (sec) {
      var centis = Math.floor(Math.max(0, sec) * 100);
      var hundredths = centis % 100;
      var totalSeconds = Math.floor(centis / 100);
      var h = Math.floor(totalSeconds / 3600);
      var m = Math.floor(totalSeconds / 60) % 60;
      var s = totalSeconds % 60;
      return {
        main: h > 0 ? h + ':' + pad(m) + ':' + pad(s) : pad(m) + ':' + pad(s),
        fraction: pad(hundredths)
      };
    },

    /* 时钟式显示，向下取整 */
    clock: function (sec) {
      var t = Math.floor(Math.max(0, sec));
      var h = Math.floor(t / 3600);
      var m = Math.floor(t / 60) % 60;
      var s = t % 60;
      return h > 0 ? h + ':' + pad(m) + ':' + pad(s) : pad(m) + ':' + pad(s);
    },

    /* 倒计时：向上取整，避免最后一秒提前归零 */
    countdown: function (sec) {
      var t = Math.ceil(Math.max(0, sec));
      var h = Math.floor(t / 3600);
      var m = Math.floor(t / 60) % 60;
      var s = t % 60;
      return h > 0 ? h + ':' + pad(m) + ':' + pad(s) : pad(m) + ':' + pad(s);
    },

    /* 分段用时：mm:ss.cc，分钟不截断到 60 */
    lap: function (sec) {
      var centis = Math.floor(Math.max(0, sec) * 100);
      var cs = centis % 100;
      var totalSeconds = Math.floor(centis / 100);
      return pad(Math.floor(totalSeconds / 60)) + ':' + pad(totalSeconds % 60) + '.' + pad(cs);
    },

    /* 与本段之前平均值的偏差 */
    delta: function (sec) {
      var v = Math.round(sec);
      if (v === 0) return '持平';
      if (v > 0) return '+' + v + '"';
      return '−' + Math.abs(v) + '"';
    },

    /* 解析用户输入的时长。纯数字默认按分钟。
     * 支持 30 / 30:00 / 1:30 / 1:30:00 / 90s / 90秒 / 2h / 2小时 / 0.5 */
    parseDuration: function (raw) {
      if (typeof raw !== 'string') return null;
      var text = raw.trim();
      if (!text) return null;
      text = text.replace(/：/g, ':').replace(/[’＇]/g, "'");

      var scale = 60;
      var units = [
        ['小时', 3600], ['时', 3600], ['h', 3600],
        ['分钟', 60], ['分', 60], ['m', 60],
        ['秒钟', 1], ['秒', 1], ['s', 1]
      ];
      var lower = text.toLowerCase();
      for (var i = 0; i < units.length; i++) {
        var suffix = units[i][0];
        if (lower.length > suffix.length && lower.slice(-suffix.length) === suffix) {
          scale = units[i][1];
          text = text.slice(0, text.length - suffix.length).trim();
          break;
        }
      }
      if (!text) return null;

      if (text.indexOf(':') >= 0) {
        var parts = text.split(':');
        var mult;
        if (parts.length === 3) mult = [3600, 60, 1];
        else if (parts.length === 2) mult = [60, 1];
        else if (parts.length === 1) mult = [60];
        else return null;

        var total = 0;
        for (var j = 0; j < parts.length; j++) {
          var p = parts[j].trim();
          if (p === '') continue;
          var num = Number(p.replace(',', '.'));
          if (!isFinite(num) || num < 0) return null;
          total += num * mult[j];
        }
        return total > 0 ? total : null;
      }

      var value = Number(text.replace(',', '.'));
      if (!isFinite(value) || value <= 0) return null;
      return value * scale;
    },

    /* 反向回读：把秒数写回输入框 */
    durationInputText: function (sec) {
      var t = Math.floor(Math.max(0, sec));
      var h = Math.floor(t / 3600);
      var m = Math.floor(t / 60) % 60;
      var s = t % 60;
      if (h > 0) return h + ':' + pad(m) + ':' + pad(s);
      if (s > 0) return m + ':' + pad(s);
      return String(Math.floor(t / 60));
    },

    clockTime: function (ts) {
      var d = new Date(ts);
      return d.getHours() + ':' + pad(d.getMinutes());
    },

    stamp: function (ts) {
      var d = new Date(ts);
      return (d.getMonth() + 1) + '月' + d.getDate() + '日 ' +
        d.getHours() + ':' + pad(d.getMinutes());
    },

    pad: pad
  };

  root.TimeText = TimeText;
  if (typeof module !== 'undefined' && module.exports) module.exports = TimeText;
})(typeof globalThis !== 'undefined' ? globalThis : this);
