# Build Universal APK from AAB using bundletool
# Usage: .\build_universal_apk.ps1

$ErrorActionPreference = "Stop"

# Resolve repo root from script location so it works from any working directory.
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Configuration
$bundletoolPath = "C:\tools\bundletool.jar"
$aabPath = Join-Path $repoRoot "build\app\outputs\bundle\release\app-release.aab"
$apksPath = Join-Path $repoRoot "build\app\outputs\bundle\release\app-release.apks"
$outputDir = Join-Path $repoRoot "build\app\outputs\bundle\release\apks"
$pubspecPath = Join-Path $repoRoot "pubspec.yaml"

# Debug keystore (default Android debug signing)
$keystorePath = "$env:USERPROFILE\.android\debug.keystore"
$keyAlias = "androiddebugkey"
$keystorePassword = "android"
$keyPassword = "android"

function Resolve-JavaPath {
    if ($env:JAVA_HOME) {
        $javaFromHome = Join-Path $env:JAVA_HOME "bin\java.exe"
        if (Test-Path $javaFromHome) {
            return $javaFromHome
        }
    }

    $candidatePaths = @(
        "C:\Program Files\Android\Android Studio\jbr\bin\java.exe",
        "C:\Program Files\Java\jdk-17\bin\java.exe",
        "C:\Program Files\Common Files\Oracle\Java\javapath\java.exe"
    )

    foreach ($candidate in $candidatePaths) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $javaCommand = Get-Command java -ErrorAction SilentlyContinue
    if ($javaCommand -and $javaCommand.Source) {
        return $javaCommand.Source
    }

    return $null
}

Write-Host "=== Nivio Universal APK Builder ===" -ForegroundColor Cyan
Write-Host ""

# Check Java
Write-Host "Checking Java..." -ForegroundColor Yellow
$javaExe = Resolve-JavaPath
if (-not $javaExe) {
    Write-Host "  ERROR: Java not found." -ForegroundColor Red
    Write-Host "  Install JDK 17 or set JAVA_HOME to your JDK path." -ForegroundColor Red
    exit 1
}
$javaVersionStdOut = [System.IO.Path]::GetTempFileName()
$javaVersionStdErr = [System.IO.Path]::GetTempFileName()
try {
    $javaVersionProcess = Start-Process `
        -FilePath $javaExe `
        -ArgumentList "-version" `
        -NoNewWindow `
        -Wait `
        -PassThru `
        -RedirectStandardOutput $javaVersionStdOut `
        -RedirectStandardError $javaVersionStdErr

    $javaVersion = @(
        Get-Content $javaVersionStdErr -ErrorAction SilentlyContinue
        Get-Content $javaVersionStdOut -ErrorAction SilentlyContinue
    ) | Where-Object { $_ -and $_.Trim() -ne "" } | Select-Object -First 1

    if ($javaVersionProcess.ExitCode -ne 0) {
        Write-Host "  ERROR: Java was found but failed to run." -ForegroundColor Red
        Write-Host "  Path: $javaExe" -ForegroundColor Red
        exit 1
    }
} finally {
    Remove-Item -Path $javaVersionStdOut, $javaVersionStdErr -Force -ErrorAction SilentlyContinue
}

Write-Host "  Found: $javaVersion" -ForegroundColor Green
Write-Host "  Path:  $javaExe" -ForegroundColor Green

# Check bundletool
Write-Host "Checking bundletool..." -ForegroundColor Yellow
if (Test-Path $bundletoolPath) {
    Write-Host "  Found: $bundletoolPath" -ForegroundColor Green
} else {
    Write-Host "  Bundletool not found. Downloading..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path (Split-Path $bundletoolPath) | Out-Null
    Invoke-WebRequest -Uri "https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar" -OutFile $bundletoolPath
    Write-Host "  Downloaded to: $bundletoolPath" -ForegroundColor Green
}

# Check AAB file
Write-Host "Checking AAB file..." -ForegroundColor Yellow
if (Test-Path $aabPath) {
    $aabSize = [math]::Round((Get-Item $aabPath).Length / 1MB, 2)
    Write-Host "  Found: $aabPath ($aabSize MB)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: AAB not found at $aabPath" -ForegroundColor Red
    Write-Host "  Run 'shorebird release android' first." -ForegroundColor Red
    exit 1
}

# Check keystore
Write-Host "Checking keystore..." -ForegroundColor Yellow
if (Test-Path $keystorePath) {
    Write-Host "  Found: $keystorePath" -ForegroundColor Green
} else {
    Write-Host "  ERROR: Debug keystore not found at $keystorePath" -ForegroundColor Red
    exit 1
}

# Build APK set
Write-Host ""
Write-Host "Building APK set (universal mode)..." -ForegroundColor Yellow
$buildArgs = @(
    "-jar", $bundletoolPath,
    "build-apks",
    "--bundle=$aabPath",
    "--output=$apksPath",
    "--mode=universal",
    "--ks=$keystorePath",
    "--ks-key-alias=$keyAlias",
    "--ks-pass=pass:$keystorePassword",
    "--key-pass=pass:$keyPassword",
    "--overwrite"
)

$buildStdOut = [System.IO.Path]::GetTempFileName()
$buildStdErr = [System.IO.Path]::GetTempFileName()
$buildProcess = Start-Process `
    -FilePath $javaExe `
    -ArgumentList $buildArgs `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $buildStdOut `
    -RedirectStandardError $buildStdErr

if ($buildProcess.ExitCode -ne 0) {
    Write-Host "  --- bundletool output ---" -ForegroundColor DarkYellow
    Get-Content $buildStdOut -ErrorAction SilentlyContinue
    Get-Content $buildStdErr -ErrorAction SilentlyContinue
    Remove-Item -Path $buildStdOut, $buildStdErr -Force -ErrorAction SilentlyContinue
    Write-Host "  ERROR: Failed to build APK set" -ForegroundColor Red
    exit 1
}
Remove-Item -Path $buildStdOut, $buildStdErr -Force -ErrorAction SilentlyContinue
Write-Host "  APK set created: $apksPath" -ForegroundColor Green

# Extract universal APK
Write-Host ""
Write-Host "Extracting universal APK..." -ForegroundColor Yellow

if (Test-Path $outputDir) {
    Remove-Item -Path $outputDir -Recurse -Force
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

# .apks is a ZIP file, rename and extract
$tempZip = "$apksPath.zip"
Copy-Item $apksPath $tempZip -Force
Expand-Archive -Path $tempZip -DestinationPath $outputDir -Force
Remove-Item $tempZip

$universalApk = Join-Path $outputDir "universal.apk"
if (Test-Path $universalApk) {
    $apkSize = [math]::Round((Get-Item $universalApk).Length / 1MB, 2)
    Write-Host "  Extracted: $universalApk ($apkSize MB)" -ForegroundColor Green
} else {
    Write-Host "  ERROR: universal.apk not found in extracted files" -ForegroundColor Red
    exit 1
}

# Create a versioned copy for release uploads.
$version = "unknown"
if (Test-Path $pubspecPath) {
    $versionLine = Select-String -Path $pubspecPath -Pattern "^version:\s*(.+)$" | Select-Object -First 1
    if ($versionLine -and $versionLine.Matches.Count -gt 0) {
        $version = $versionLine.Matches[0].Groups[1].Value.Trim()
    }
}

$versionSafe = $version -replace "[^0-9A-Za-z\.\+\-]", "_"
$versionedApk = Join-Path $outputDir "nivio-$versionSafe-universal.apk"
Copy-Item -Path $universalApk -Destination $versionedApk -Force

# Done
Write-Host ""
Write-Host "=== SUCCESS ===" -ForegroundColor Green
Write-Host "Universal APK: $universalApk" -ForegroundColor Cyan
Write-Host "Versioned APK: $versionedApk" -ForegroundColor Cyan
Write-Host "Size: $apkSize MB" -ForegroundColor Cyan
Write-Host ""
Write-Host "Upload the APK to GitHub Releases for Shorebird distribution." -ForegroundColor White
