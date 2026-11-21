(async function () {
  const statuses = document.querySelectorAll('[data-ios-status]');
  if (!statuses.length) return;

  try {
    const response = await fetch('/altstore.json');
    if (!response.ok) throw new Error('Could not check for the iOS release');
    const source = await response.json();
    const latest = source.apps.find(app => app.bundleIdentifier === 'com.nirmal.nivio')?.versions[0];
    if (!latest) {
      statuses.forEach(status => { status.textContent = 'The public iOS IPA is pending.'; });
      return;
    }

    statuses.forEach(status => { status.textContent = `iOS ${latest.version} (build ${latest.buildVersion}) is available to sideload.`; });
    document.querySelectorAll('[data-ios-available]').forEach(element => { element.hidden = false; });
    document.querySelectorAll('[data-ios-ipa]').forEach(link => {
      link.href = latest.downloadURL;
      link.hidden = false;
    });
  } catch (_) {
    statuses.forEach(status => { status.textContent = 'Could not check iOS download availability. Check GitHub Releases.'; });
  }
})();
