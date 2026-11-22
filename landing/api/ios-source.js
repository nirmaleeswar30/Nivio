const SITE = 'https://nivio.nirmaleeswar.dev';
const RELEASES = 'https://api.github.com/repos/nirmaleeswar30/Nivio/releases';
const DOWNLOADS = 'https://github.com/nirmaleeswar30/Nivio/releases/download/';
const IPA_NAME = /^Nivio-(\d+\.\d+\.\d+)\.ipa$/i;
// Older IPAs put the build number in the name.
const LEGACY_IPA_NAME = /^Nivio-(\d+\.\d+\.\d+)[+._-]([1-9]\d*)-shorebird-unsigned\.ipa$/i;
const IOS_BUILD_MARKER = /<!--\s*nivio-ios-build:\s*([1-9]\d*)\s*-->/;

export default async function handler(req, res) {
  try {
    const versions = new Map();
    for (let page = 1; ; page += 1) {
      const response = await fetch(`${RELEASES}?per_page=100&page=${page}`, {
        headers: { Accept: 'application/vnd.github+json' },
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) throw new Error(`GitHub releases returned ${response.status}`);

      const releases = await response.json();
      for (const release of releases) {
        if (release.draft || release.prerelease) continue;
        const releaseBuild = IOS_BUILD_MARKER.exec(release.body ?? '')?.[1] ?? '1';
        for (const asset of release.assets) {
          const match = IPA_NAME.exec(asset.name) ?? LEGACY_IPA_NAME.exec(asset.name);
          if (!match || asset.state !== 'uploaded' || asset.size <= 0 ||
              !asset.browser_download_url.startsWith(DOWNLOADS)) continue;

          const [, version, buildVersion = releaseBuild] = match;
          const key = `${version}+${buildVersion}`;
          const date = asset.created_at || release.published_at;
          if (!versions.has(key) || date > versions.get(key).date) {
            versions.set(key, {
              version, buildVersion, date, downloadURL: asset.browser_download_url,
              size: asset.size, minOSVersion: '15.0',
            });
          }
        }
      }
      if (!response.headers.get('link')?.includes('rel="next"')) break;
    }

    const ordered = Array.from(versions.values()).sort((a, b) =>
      b.version.localeCompare(a.version, 'en', { numeric: true }) ||
      Number(b.buildVersion) - Number(a.buildVersion));
    const iconURL = `${SITE}/nivio.png`;
    const tintColor = '#E5231A';
    res.setHeader('Cache-Control', 'public, max-age=60, s-maxage=300, stale-while-revalidate=600');
    res.status(200).json({
      name: 'Nivio',
      website: SITE,
      iconURL,
      tintColor,
      apps: ordered.length ? [{
        name: 'Nivio',
        bundleIdentifier: 'com.nirmal.nivio',
        developerName: 'Nirmal Eeswar',
        subtitle: 'Movies, TV, anime and live IPTV',
        localizedDescription: 'An open-source player for iPhone and iPad with Watch Parties, offline downloads, subtitles and Picture-in-Picture.',
        iconURL,
        tintColor,
        category: 'entertainment',
        versions: ordered,
        appPermissions: {
          entitlements: [],
          privacy: {
            NSLocalNetworkUsageDescription: 'Nivio connects to peers on your local network when streaming torrents.',
            NSPhotoLibraryUsageDescription: 'Nivio only reads files you pick, such as subtitle files or custom fonts.',
          },
        },
      }] : [],
      news: [],
    });
  } catch (error) {
    console.error('Could not load Nivio iOS releases', error);
    res.setHeader('Cache-Control', 'no-store');
    res.status(502).json({ error: 'Could not load Nivio iOS releases.' });
  }
}
