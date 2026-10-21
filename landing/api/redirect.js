/**
 * Vercel Serverless Function for Nivio Deep Links & Watch Party Sharing
 * Handles dynamic Open Graph & Twitter Cards for social media crawlers
 * (WhatsApp, Discord, Telegram, Twitter, iMessage, etc.)
 */

function escapeHtml(str) {
  if (!str) return '';
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

export default async function handler(req, res) {
  const {
    url,
    code,
    party,
    title,
    poster,
    desc,
    type,
    id
  } = req.query;

  const partyCode = (code || party || '').trim().toUpperCase();
  const isParty = Boolean(partyCode);
  const mediaId = (id || '').trim();
  const mediaType = (type || 'movie').trim();

  // Decode or construct the deep link
  let deepLink = '';
  if (url) {
    try {
      deepLink = Buffer.from(url, 'base64').toString('utf-8');
    } catch (_) {
      deepLink = url;
    }
  } else if (isParty) {
    deepLink = `nivio://open/party?code=${encodeURIComponent(partyCode)}`;
  } else if (mediaId) {
    deepLink = `nivio://open/media/${encodeURIComponent(mediaId)}?type=${encodeURIComponent(mediaType)}`;
  } else {
    deepLink = 'nivio://open/home';
  }

  // Ensure poster has absolute URL
  let fullPosterUrl = '';
  if (poster) {
    if (poster.startsWith('http://') || poster.startsWith('https://')) {
      fullPosterUrl = poster;
    } else if (poster.startsWith('/')) {
      fullPosterUrl = `https://image.tmdb.org/t/p/w780${poster}`;
    } else {
      fullPosterUrl = `https://image.tmdb.org/t/p/w780/${poster}`;
    }
  }

  // Build metadata
  let pageTitle = '';
  let pageDesc = '';

  if (isParty) {
    pageTitle = title
      ? `🍿 Watch Party: ${title} • Room ${partyCode}`
      : `🍿 Join Nivio Watch Party • Room ${partyCode}`;
    pageDesc = desc || `Join my watch party on Nivio! Perfectly synced playback with sub-20ms latency. Room code: ${partyCode}`;
  } else {
    pageTitle = title ? `${title} • Watch on Nivio` : 'Nivio • Stream Movies, Shows & Anime';
    pageDesc = desc || 'Stream movies, series, and anime with multi-source failover, zero ads, and real-time watch parties.';
  }

  // Fetch metadata for short media links to enrich social cards
  if (!isParty && mediaId && (!fullPosterUrl || !desc)) {
    if (mediaType === 'anime') {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 1800);
        const anilistRes = await fetch('https://graphql.anilist.co', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'User-Agent': 'NivioApp/1.0'
          },
          body: JSON.stringify({
            query: `query ($id: Int) {
              Media (id: $id, type: ANIME) {
                title { english romaji }
                description(asHtml: false)
                coverImage { extraLarge large }
              }
            }`,
            variables: { id: parseInt(mediaId, 10) }
          }),
          signal: controller.signal
        });
        clearTimeout(timeoutId);
        if (anilistRes.ok) {
          const json = await anilistRes.json();
          const animeData = json?.data?.Media;
          if (animeData) {
            const resolvedTitle = animeData.title?.english || animeData.title?.romaji;
            if (resolvedTitle && !title) {
              pageTitle = `${resolvedTitle} • Watch on Nivio`;
            }
            if (animeData.description && !desc) {
              pageDesc = animeData.description.replace(/<[^>]*>?/gm, '').trim();
            }
            const cover = animeData.coverImage?.extraLarge || animeData.coverImage?.large;
            if (cover && !fullPosterUrl) {
              fullPosterUrl = cover;
            }
          }
        }
      } catch (_) {
        // Gracefully fall back to query params or defaults
      }
    } else if (/^\d+$/.test(mediaId)) {
      try {
        const tmdbType = mediaType === 'tv' ? 'tv' : 'movie';
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 1500);
        const tmdbRes = await fetch(
          `https://api.themoviedb.org/3/${tmdbType}/${encodeURIComponent(mediaId)}?api_key=d39245e111947eb92b947e3a8aacc89f`,
          { signal: controller.signal }
        );
        clearTimeout(timeoutId);
        if (tmdbRes.ok) {
          const tmdbData = await tmdbRes.json();
          const resolvedTitle = tmdbData.title || tmdbData.name;
          if (resolvedTitle && !title) {
            pageTitle = `${resolvedTitle} • Watch on Nivio`;
          }
          if (tmdbData.overview && !desc) {
            pageDesc = tmdbData.overview;
          }
          if (tmdbData.poster_path && !fullPosterUrl) {
            fullPosterUrl = `https://image.tmdb.org/t/p/w780${tmdbData.poster_path}`;
          }
        }
      } catch (_) {
        // Gracefully fall back to query params or defaults
      }
    }
  }

  let pageImage = fullPosterUrl;
  if (isParty) {
    pageImage = 'https://nivio.nirmaleeswar.dev/appicon.png';
  } else if (!pageImage) {
    pageImage = 'https://nivio.nirmaleeswar.dev/appicon.png';
  }

  const safeTitle = escapeHtml(pageTitle);
  const safeDesc = escapeHtml(pageDesc);
  const safeImage = escapeHtml(pageImage);
  const safeDeepLink = escapeHtml(deepLink);
  const safePartyCode = escapeHtml(partyCode);
  const safeMediaTitle = escapeHtml(title || '');

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <title>${safeTitle}</title>

  <!-- Open Graph & Social Cards (WhatsApp, Discord, Telegram, Twitter, etc.) -->
  <meta name="description" content="${safeDesc}">
  <meta property="og:type" content="video.other">
  <meta property="og:site_name" content="Nivio">
  <meta property="og:title" content="${safeTitle}">
  <meta property="og:description" content="${safeDesc}">
  <meta property="og:image" content="${safeImage}">
  <meta property="og:image:alt" content="${safeTitle}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:site" content="@NivioApp">
  <meta name="twitter:title" content="${safeTitle}">
  <meta name="twitter:description" content="${safeDesc}">
  <meta name="twitter:image" content="${safeImage}">
  <meta name="theme-color" content="#e5231a">

  <!-- Immediate automatic redirect attempt -->
  <meta http-equiv="refresh" content="0;url=${safeDeepLink}">

  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=Space+Grotesk:wght@600;700&display=swap" rel="stylesheet">

  <style>
    :root {
      --bg: #090604;
      --card-bg: rgba(255, 255, 255, 0.035);
      --border: rgba(255, 255, 255, 0.08);
      --amber: #ff8a3c;
      --red: #e5231a;
      --grad: linear-gradient(135deg, #e5231a 0%, #ff8a3c 100%);
      --text: #f5efe9;
      --muted: #9c8e82;
      --font-s: 'Plus Jakarta Sans', -apple-system, sans-serif;
      --font-d: 'Space Grotesk', sans-serif;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: var(--bg);
      color: var(--text);
      font-family: var(--font-s);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 20px;
      position: relative;
      overflow-x: hidden;
    }
    .ambient-glow {
      position: fixed;
      width: 500px;
      height: 500px;
      border-radius: 50%;
      background: radial-gradient(circle, rgba(229, 35, 26, 0.22) 0%, transparent 65%);
      filter: blur(80px);
      top: -100px;
      left: 50%;
      transform: translateX(-50%);
      pointer-events: none;
      z-index: 0;
    }
    .card {
      position: relative;
      z-index: 1;
      width: 100%;
      max-width: 440px;
      background: var(--card-bg);
      border: 1px solid var(--border);
      border-radius: 24px;
      padding: 28px 24px;
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      box-shadow: 0 30px 60px -15px rgba(0, 0, 0, 0.8), 0 0 40px -10px rgba(229, 35, 26, 0.15);
      text-align: center;
    }
    .logo-badge {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid rgba(255, 255, 255, 0.1);
      font-family: var(--font-d);
      font-size: 12px;
      font-weight: 700;
      color: var(--amber);
      margin-bottom: 20px;
      letter-spacing: 0.04em;
    }
    .logo-badge i {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: #4ade80;
      box-shadow: 0 0 8px #4ade80;
    }
    .poster-wrap {
      width: 140px;
      height: 210px;
      margin: 0 auto 18px;
      border-radius: 14px;
      overflow: hidden;
      border: 1px solid rgba(255, 255, 255, 0.14);
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.7);
      background: #18100a;
    }
    .poster-wrap img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }
    .party-box {
      background: rgba(0, 0, 0, 0.45);
      border: 1px solid rgba(255, 255, 255, 0.1);
      border-radius: 16px;
      padding: 16px;
      margin: 14px 0 20px;
    }
    .party-label {
      font-family: var(--font-d);
      font-size: 11px;
      font-weight: 700;
      color: var(--muted);
      letter-spacing: 0.08em;
      margin-bottom: 8px;
    }
    .party-code-digits {
      display: flex;
      justify-content: center;
      gap: 6px;
      margin-bottom: 12px;
    }
    .party-code-digits b {
      font-family: var(--font-d);
      font-size: 22px;
      font-weight: 700;
      width: 38px;
      height: 48px;
      display: grid;
      place-items: center;
      border-radius: 8px;
      background: linear-gradient(180deg, #251a13, #120b07);
      border: 1px solid rgba(255, 138, 60, 0.35);
      color: var(--amber);
      box-shadow: 0 4px 14px rgba(229, 35, 26, 0.25);
    }
    .copy-pill {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 6px 14px;
      border-radius: 999px;
      background: rgba(255, 255, 255, 0.08);
      border: 1px solid rgba(255, 255, 255, 0.14);
      font-family: var(--font-d);
      font-size: 11px;
      font-weight: 600;
      color: var(--text);
      cursor: pointer;
      transition: all 0.2s;
    }
    .copy-pill:hover {
      background: rgba(255, 255, 255, 0.14);
      border-color: var(--amber);
    }
    h1 {
      font-size: 20px;
      font-weight: 700;
      margin-bottom: 8px;
      color: #fff;
      line-height: 1.3;
    }
    p.desc {
      font-size: 13.5px;
      color: var(--muted);
      line-height: 1.5;
      margin-bottom: 24px;
      display: -webkit-box;
      -webkit-line-clamp: 3;
      -webkit-box-orient: vertical;
      overflow: hidden;
    }
    .actions {
      display: flex;
      flex-direction: column;
      gap: 10px;
    }
    .btn {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      padding: 13px 20px;
      border-radius: 12px;
      font-family: var(--font-d);
      font-size: 14px;
      font-weight: 700;
      text-decoration: none;
      transition: all 0.2s;
      cursor: pointer;
    }
    .btn-primary {
      background: var(--grad);
      color: #fff;
      box-shadow: 0 6px 20px rgba(229, 35, 26, 0.45);
    }
    .btn-primary:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 26px rgba(229, 35, 26, 0.65);
    }
    .btn-secondary {
      background: rgba(255, 255, 255, 0.06);
      border: 1px solid rgba(255, 255, 255, 0.12);
      color: var(--text);
    }
    .btn-secondary:hover {
      background: rgba(255, 255, 255, 0.1);
    }
    .spinner {
      width: 24px;
      height: 24px;
      border: 2.5px solid rgba(255, 255, 255, 0.15);
      border-top-color: var(--amber);
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
      margin: 10px auto 14px;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
  </style>
</head>
<body>
  <div class="ambient-glow"></div>

  <div class="card">
    <div class="logo-badge">
      <i></i> ${isParty ? 'NIVIO WATCH PARTY' : 'OPEN IN NIVIO'}
    </div>

    ${fullPosterUrl ? `
    <div class="poster-wrap">
      <img src="${safeImage}" alt="${safeTitle}">
    </div>` : ''}

    ${isParty ? `
    <div class="party-box">
      <div class="party-label">ROOM CODE</div>
      <div class="party-code-digits">
        ${partyCode.split('').map(char => `<b>${escapeHtml(char)}</b>`).join('')}
      </div>
      <button class="copy-pill" id="copyCodeBtn" type="button">
        📋 <span id="copyText">Copy Room Code</span>
      </button>
    </div>` : ''}

    <h1>${isParty && safeMediaTitle ? safeMediaTitle : (safeTitle.replace(' • Watch on Nivio', ''))}</h1>
    <p class="desc">${safeDesc}</p>

    <div class="spinner" id="spinner"></div>

    <div class="actions">
      <a class="btn btn-primary" id="openAppBtn" href="${safeDeepLink}">
        ${isParty ? 'Join Watch Party in App' : 'Open in Nivio App'}
      </a>
      <a class="btn btn-secondary" href="/">
        Get Nivio (Android & Desktop)
      </a>
    </div>
  </div>

  <script>
    // Copy code handler
    const copyBtn = document.getElementById('copyCodeBtn');
    if (copyBtn) {
      copyBtn.addEventListener('click', () => {
        navigator.clipboard.writeText('${safePartyCode}').then(() => {
          const text = document.getElementById('copyText');
          if (text) {
            text.textContent = 'Copied!';
            setTimeout(() => { text.textContent = 'Copy Room Code'; }, 1800);
          }
        });
      });
    }

    // Trigger app intent immediately for mobile / desktop
    try {
      window.location.href = '${safeDeepLink}';
    } catch (_) {}

    // Hide spinner after redirect attempt
    setTimeout(() => {
      const spinner = document.getElementById('spinner');
      if (spinner) spinner.style.display = 'none';
    }, 1500);
  </script>
</body>
</html>`;

  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300');
  res.status(200).send(html);
}
