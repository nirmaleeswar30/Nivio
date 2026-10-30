// Nivio Docs: builds the section nav, prev/next links and "On this page"
// list from one list of pages, so adding a page means adding one line here.
(function () {
  var GROUPS = [
    { title: 'Getting started', pages: [
      { slug: '', title: 'Overview', keys: 'start intro what is nivio platforms' },
      { slug: 'install', title: 'Install & update', keys: 'download apk exe appimage windows linux android obtainium update upgrade uninstall smartscreen fuse' },
    ] },
    { title: 'Watching', pages: [
      { slug: 'player', title: 'The player', keys: 'controls gestures keyboard shortcuts lock brightness volume subtitles audio quality server decoder ambient stats pip skip intro next episode' },
      { slug: 'hdr', title: 'HDR & Dolby Vision', keys: 'hdr10 hlg dolby vision dv tone mapping sdr hdr toys bt2020 surface vulkan mediacodec' },
      { slug: 'downloads', title: 'Downloads', keys: 'offline save download watch while downloading resume connections' },
    ] },
    { title: 'What to watch', pages: [
      { slug: 'anime', title: 'Anime', keys: 'anime miruro animetsu animex sub dub filler skip intro aniskip source' },
      { slug: 'torrents', title: 'Torrent streaming', keys: 'torrent p2p magnet nyaa piratebay yts eztv 1337x rqbit' },
      { slug: 'live-tv', title: 'Live TV & IPTV', keys: 'iptv m3u xtream channels sports live tv playlist movies series' },
    ] },
    { title: 'Together', pages: [
      { slug: 'watch-party', title: 'Watch Party', keys: 'party friends sync code link chat' },
    ] },
    { title: 'Devices & accounts', pages: [
      { slug: 'android-tv', title: 'Android TV', keys: 'tv google tv remote dpad sideload downloader shield' },
      { slug: 'sync', title: 'Sync & integrations', keys: 'google sign in cloud anilist myanimelist mal simkl discord rich presence alerts notifications' },
    ] },
    { title: 'Help', pages: [
      { slug: 'faq', title: 'Troubleshooting & FAQ', keys: 'help problem error black screen not loading cloudflare crash bug report sleep' },
    ] },
  ];

  var flat = [];
  GROUPS.forEach(function (g) { g.pages.forEach(function (p) { flat.push(p); }); });

  // Relative links, so the docs work on the site (/docs/player), from a
  // local server, and straight from disk (file:///.../docs/player.html).
  function href(slug) { return (slug || 'index') + '.html'; }
  var last = location.pathname.replace(/\/$/, '').split('/').pop().replace(/\.html$/, '');
  var current = (last === 'docs' || last === 'index') ? '' : last;
  var index = flat.findIndex(function (p) { return p.slug === current; });

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; });
  }

  // Section nav
  var nav = document.getElementById('docs-nav');
  if (nav) {
    var html = '<input class="nav-search" id="nav-search" type="search" placeholder="Search the docs" aria-label="Search the docs">';
    GROUPS.forEach(function (g) {
      html += '<div class="nav-group"><h4>' + esc(g.title) + '</h4>';
      g.pages.forEach(function (p) {
        html += '<a href="' + href(p.slug) + '" data-keys="' + esc((p.title + ' ' + p.keys).toLowerCase()) + '"' +
          (p.slug === current ? ' aria-current="page"' : '') + '>' + esc(p.title) + '</a>';
      });
      html += '</div>';
    });
    html += '<p class="nav-empty" id="nav-empty" hidden>No page matches. Try the FAQ.</p>';
    nav.innerHTML = html;

    var search = document.getElementById('nav-search');
    search.addEventListener('input', function () {
      var q = search.value.trim().toLowerCase();
      var any = false;
      nav.querySelectorAll('.nav-group').forEach(function (group) {
        var shown = 0;
        group.querySelectorAll('a').forEach(function (a) {
          var hit = !q || a.dataset.keys.indexOf(q) !== -1;
          a.hidden = !hit;
          if (hit) shown++;
        });
        group.hidden = shown === 0;
        if (shown) any = true;
      });
      document.getElementById('nav-empty').hidden = any;
    });
  }

  // Mobile menu
  var menu = document.getElementById('menu-btn');
  if (menu) {
    menu.addEventListener('click', function () {
      var open = document.body.classList.toggle('nav-open');
      menu.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
  }

  // Prev / next
  var pager = document.getElementById('pager');
  if (pager && index !== -1) {
    var prev = flat[index - 1];
    var next = flat[index + 1];
    pager.innerHTML =
      (prev ? '<a class="prev" href="' + href(prev.slug) + '"><small>Previous</small>' + esc(prev.title) + '</a>' : '') +
      (next ? '<a class="next" href="' + href(next.slug) + '"><small>Next</small>' + esc(next.title) + '</a>' : '');
  }

  // Heading anchors + "On this page"
  var article = document.querySelector('.prose');
  var toc = document.getElementById('docs-toc');
  if (article) {
    var heads = article.querySelectorAll('h2[id]');
    heads.forEach(function (h) {
      var a = document.createElement('a');
      a.className = 'anchor';
      a.href = '#' + h.id;
      a.setAttribute('aria-label', 'Link to this section');
      a.textContent = '#';
      h.appendChild(a);
    });
    if (toc && heads.length > 1) {
      var t = '<h4>On this page</h4>';
      heads.forEach(function (h) {
        t += '<a href="#' + h.id + '">' + esc(h.firstChild.textContent.trim()) + '</a>';
      });
      toc.innerHTML = t;
      var links = toc.querySelectorAll('a');
      if ('IntersectionObserver' in window) {
        var obs = new IntersectionObserver(function (entries) {
          entries.forEach(function (e) {
            if (!e.isIntersecting) return;
            links.forEach(function (l) { l.classList.toggle('active', l.getAttribute('href') === '#' + e.target.id); });
          });
        }, { rootMargin: '-80px 0px -70% 0px' });
        heads.forEach(function (h) { obs.observe(h); });
      }
    }
  }
})();
