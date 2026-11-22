"""Package a Shorebird iOS archive for sideloading."""

import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile


APP_ROOT = Path(__file__).resolve().parents[1]


def package_archive():
    apps = list((APP_ROOT / "build/ios/archive").glob("*.xcarchive/Products/Applications/*.app"))
    if len(apps) != 1:
        raise ValueError("Expected exactly one archived iOS app")
    app = apps[0]
    with (app / "Info.plist").open("rb") as plist:
        info = plistlib.load(plist)
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if info["CFBundleIdentifier"] != "com.nirmal.nivio":
        raise ValueError("Archived app has the wrong bundle ID")
    if build != os.environ["BUILD_NUMBER"] or not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Archived app version or build number does not match the release inputs")

    for framework in ("App", "Flutter", "Mpv", "RqbitEngine", "CurlImpersonate"):
        if not (app / f"Frameworks/{framework}.framework/{framework}").is_file():
            raise ValueError(f"Archived app is missing {framework}.framework")
    assets = app / "Frameworks/App.framework/flutter_assets"
    if (assets / ".env").read_bytes() != (APP_ROOT / ".env").read_bytes():
        raise ValueError("Archived app configuration differs from the build configuration")

    output = APP_ROOT / "build/shorebird-package"
    output.mkdir(exist_ok=True)
    name = f"Nivio-{version}.ipa"
    with tempfile.TemporaryDirectory() as workspace:
        payload = Path(workspace) / "Payload"
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        archive = Path(workspace) / name
        subprocess.run(["zip", "-qry", name, "Payload"], cwd=workspace, check=True)
        shutil.move(archive, output / name)

    ipa = output / name
    with ipa.open("rb") as file:
        digest = hashlib.file_digest(file, "sha256").hexdigest()
    (output / "SHA256SUMS").write_text(f"{digest}  {name}\n", encoding="utf-8")
    print(f"Packaged {name} ({ipa.stat().st_size:,} bytes)")


if __name__ == "__main__":
    try:
        package_archive()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"iOS release preparation failed: {error}") from error
