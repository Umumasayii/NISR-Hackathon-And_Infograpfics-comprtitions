// SmartIrrigate Rwanda - UI behaviour: animated numbers and multi-select filters
(function () {
  // ---- count-up numbers on stat tiles
  function fmt(v, dec) {
    return v.toLocaleString('en-US', { minimumFractionDigits: dec, maximumFractionDigits: dec });
  }
  function countUp(el) {
    if (el.dataset.done) return;
    var target = parseFloat(el.dataset.count); if (isNaN(target)) return;
    var dec = parseInt(el.dataset.dec || '0', 10), suf = el.dataset.suffix || '', pre = el.dataset.prefix || '';
    el.dataset.done = '1';
    var t0 = null, dur = 900;
    function step(ts) {
      if (!t0) t0 = ts;
      var k = Math.min((ts - t0) / dur, 1), e = 1 - Math.pow(1 - k, 3);
      el.textContent = pre + fmt(target * e, dec) + suf;
      if (k < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }
  function scan(root) {
    (root || document).querySelectorAll('.st-value[data-count]').forEach(countUp);
  }

  // ---- multi-select dropdowns (.mp, built by multi_pick() in R)
  function boxes(mp) { return Array.prototype.slice.call(mp.querySelectorAll('input[type=checkbox]')); }
  function refresh(mp) {
    var all = boxes(mp), on = all.filter(function (b) { return b.checked; });
    var txt = mp.querySelector('.mp-text'), cnt = mp.querySelector('.mp-count');
    if (!txt) return;
    var names = on.map(function (b) { return b.parentNode.textContent.trim(); });
    var t, c, narrowed = !(on.length === 0 || on.length === all.length);
    if (!narrowed) { t = mp.dataset.all; c = String(all.length); }
    else { t = on.length <= 2 ? names.join(', ') : (mp.dataset.nsel || '%d selected').replace('%d', on.length); c = on.length + '/' + all.length; }
    if (txt.textContent !== t) txt.textContent = t;
    if (cnt.textContent !== c) cnt.textContent = c;
    mp.classList.toggle('narrowed', narrowed);
  }
  function fire(mp) {
    var b = boxes(mp)[0]; if (b && window.jQuery) jQuery(b).trigger('change');
    refresh(mp);
  }
  function closeAll(except) {
    document.querySelectorAll('.mp.open').forEach(function (m) {
      if (m !== except) { m.classList.remove('open'); m.querySelector('.mp-btn').setAttribute('aria-expanded', 'false'); }
    });
  }
  document.addEventListener('click', function (e) {
    var mp = e.target.closest('.mp');
    if (!mp) { closeAll(null); return; }
    if (e.target.closest('.mp-btn')) {
      var open = !mp.classList.contains('open');
      closeAll(mp); mp.classList.toggle('open', open);
      mp.querySelector('.mp-btn').setAttribute('aria-expanded', open ? 'true' : 'false');
      var s = mp.querySelector('.mp-search'); if (open && s) s.focus();
    } else if (e.target.closest('.mp-all')) {
      boxes(mp).forEach(function (b) { if (b.closest('.checkbox').style.display !== 'none') b.checked = true; }); fire(mp);
    } else if (e.target.closest('.mp-none')) {
      boxes(mp).forEach(function (b) { b.checked = false; }); fire(mp);
    }
  });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeAll(null); });
  document.addEventListener('input', function (e) {
    if (!e.target.classList.contains('mp-search')) return;
    var q = e.target.value.toLowerCase(), mp = e.target.closest('.mp');
    mp.querySelectorAll('.checkbox').forEach(function (c) {
      c.style.display = c.textContent.toLowerCase().indexOf(q) >= 0 ? '' : 'none';
    });
  });
  document.addEventListener('change', function (e) {
    var mp = e.target.closest && e.target.closest('.mp'); if (mp) refresh(mp);
  });

  document.addEventListener('DOMContentLoaded', function () {
    new MutationObserver(function (muts) {
      muts.forEach(function (m) {
        m.addedNodes.forEach(function (n) { if (n.querySelectorAll) scan(n); });
        // only when Shiny replaces the options (not when we rewrite the button text)
        var og = m.target.closest && m.target.closest('.mp .shiny-options-group, .mp .shiny-input-checkboxgroup');
        if (og) refresh(og.closest('.mp'));
      });
    }).observe(document.body, { childList: true, subtree: true });
    scan();
    document.querySelectorAll('.mp').forEach(refresh);
  });
  // Shiny triggers 'change' via jQuery after updateCheckboxGroupInput()
  if (window.jQuery) jQuery(document).on('change', '.mp input', function () { refresh(this.closest('.mp')); });
})();
