(function () {
  function apply(ctx) {
    var H = window.__nakiHighlight;
    if (!H || !H.set) return;

    var recs = ctx.recommendations || window.__nakiRecommendations || [];
    var best = null;
    var bestP = -1;

    for (var i = 0; i < recs.length; i++) {
      var r = recs[i];
      if (r.actionType === 'discard' && r.tile && r.probability > bestP) {
        best = r;
        bestP = r.probability;
      }
    }

    if (!best) {
      if (H.clear) H.clear();
      return;
    }

    var color = (ctx.settings && ctx.settings.color) || 'green';
    var rgb = color === 'red'
      ? [1, 0.2, 0.2]
      : color === 'blue'
        ? [0.3, 0.5, 1]
        : [0.2, 1, 0.4];

    H.set([{ tile: best.tile, color: rgb }], null);
    ctx.log('highlight ' + best.tile + ' p=' + best.probability.toFixed(2));
  }

  window.__nakiPlugins.register({
    id: 'naki-plugin-ex-tile-highlighter',

    onRecommendations: function (ctx) {
      apply(ctx);
    },

    // 舊版 runtime 沒有 recommendationsChanged 時才走這條，避免新版重複染色。
    onReceive: function (ctx) {
      if (window.__nakiPlugins && window.__nakiPlugins.recommendationsChanged) return;
      ctx.recommendations = window.__nakiRecommendations || [];
      apply(ctx);
    }
  });
})();
