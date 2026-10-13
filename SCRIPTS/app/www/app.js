// SmartIrrigate Rwanda - small UI touches: animated numbers and card reveal
(function () {
  function fmt(v, dec) {
    return v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec });
  }
  function countUp(el) {
    if (el.dataset.done) return;
    var target = parseFloat(el.dataset.count); if (isNaN(target)) return;
    var dec = parseInt(el.dataset.dec || '0', 10), suf = el.dataset.suffix || '';
    el.dataset.done = '1';
    var t0 = null, dur = 900;
    function step(ts) {
      if (!t0) t0 = ts;
      var k = Math.min((ts - t0) / dur, 1), e = 1 - Math.pow(1 - k, 3);
      el.textContent = fmt(target * e, dec) + suf;
      if (k < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }
  function scan(root) {
    (root || document).querySelectorAll('.st-value[data-count]').forEach(countUp);
  }
  document.addEventListener('DOMContentLoaded', function () {
    new MutationObserver(function (muts) {
      muts.forEach(function (m) { m.addedNodes.forEach(function (n) { if (n.querySelectorAll) scan(n); }); });
    }).observe(document.body, { childList: true, subtree: true });
    scan();
  });
})();
