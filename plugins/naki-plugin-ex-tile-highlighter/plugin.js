(function () {
  'use strict';
  var lastState = null;
  function apply(ctx) {
    var H = window.__nakiHighlight;
    if (!H || !H.set) return;
    var recs = ctx.recommendations || window.__nakiRecommendations || [];
    var context = ctx.context || window.__nakiRecommendationContext || {};
    var settings = ctx.settings || {};
    // Use Naki's top action, never a lower-ranked discard instead of pass/win.
    var top = recs[0];
    var marks = [];
    if (top && (top.actionType === 'discard' || top.actionType === 'riichi')) {
      var tile = top.tile || top.displayTile;
      if (top.actionType === 'riichi' && !/^(?:[1-9][mps]|5[mps]r|[ESWNPFC])$/.test(tile || '')) {
        var discard = recs.find(function (r) { return r.actionType === 'discard'; });
        tile = discard && (discard.tile || discard.displayTile);
      }
      if (tile && /^(?:[1-9][mps]|5[mps]r|[ESWNPFC])$/.test(tile)) {
        var color = settings.color === 'red' ? [1, 0.45, 0.45]
          : settings.color === 'blue' ? [0.45, 0.65, 1] : [0.45, 1, 0.5];
        marks.push({ tile: tile, color: color });
        if (settings.dimOthers !== false) {
          var seen = Object.create(null);
          (context.hand || []).forEach(function (other) {
            if (other !== tile && !seen[other]) {
              seen[other] = true;
              marks.push({ tile: other, color: [0.62, 0.62, 0.68, 0.55] });
            }
          });
        }
      }
    } else if (top && ['chi', 'pon', 'kan'].indexOf(top.actionType) !== -1) {
      (context.callTiles || []).forEach(function (tile) {
        marks.push({ tile: tile, color: [1, 0.75, 0.4] });
      });
    }
    // Unseen draw signatures also include full-screen effects: opt-in only.
    var popup = settings.experimentalPopup === true && context.isCallOpportunity
      && top && ['chi', 'pon', 'kan', 'hora'].indexOf(top.actionType) !== -1
      ? [0.45, 1, 0.5] : null;
    if (marks.length || popup) H.set(marks, popup);
    else if (H.clear) H.clear();
    var state = JSON.stringify([marks, popup]);
    if (state !== lastState) {
      ctx.log('highlight ' + (top ? top.actionType + ' ' + (top.tile || top.displayTile || '') : 'clear')
        + ' targets=' + marks.length);
      lastState = state;
    }
  }
  window.__nakiPlugins.register({
    id: 'naki-plugin-ex-tile-highlighter',
    onRecommendations: apply,
    onReceive: function (ctx) {
      if (!window.__nakiPlugins.recommendationsChanged) apply(ctx);
    },
    onDisable: function () {
      if (window.__nakiHighlight) window.__nakiHighlight.clear();
      lastState = null;
    }
  });
})();
