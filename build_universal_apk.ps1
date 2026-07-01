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

# Extract version
$version = "unknown"
if (Test-Path $pubspecPath) {
    $versionLine = Select-String -Path $pubspecPath -Pattern "^version:\s*(.+)$" | Select-Object -First 1
    if ($versionLine -and $versionLine.Matches.Count -gt 0) {
        $version = $versionLine.Matches[0].Groups[1].Value.Trim()
    }
}
$versionSafe = $version -replace "[^0-9A-Za-z\.\+\-]", "_"

# Prepare output directory
if (Test-Path $outputDir) { Remove-Item -Path $outputDir -Recurse -Force }
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

function Run-Bundletool {
    param([string]$mode, [string]$outFile)
    
    $argsList = @("-jar", $bundletoolPath, "build-apks", "--bundle=$aabPath", "--output=$outFile", "--ks=$keystorePath", "--ks-key-alias=$keyAlias", "--ks-pass=pass:$keystorePassword", "--key-pass=pass:$keyPassword", "--overwrite")
    if ($mode -ne "") { $argsList += "--mode=$mode" }
    
    $outTmp = [System.IO.Path]::GetTempFileName()
    $errTmp = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $javaExe -ArgumentList $argsList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outTmp -RedirectStandardError $errTmp
    if ($proc.ExitCode -ne 0) {
        Write-Host "  ERROR: Failed to build APKs" -ForegroundColor Red
        Get-Content $errTmp -ErrorAction SilentlyContinue
        exit 1
    }
    Remove-Item -Path $outTmp, $errTmp -Force -ErrorAction SilentlyContinue
}

# Build Universal APK set
Write-Host "`nBuilding APK set (universal mode)..." -ForegroundColor Yellow
Run-Bundletool -mode "universal" -outFile "$outputDir\universal.apks"

# Build Split APK set
Write-Host "`nBuilding APK set (split mode)..." -ForegroundColor Yellow
Run-Bundletool -mode "" -outFile "$outputDir\split.apks"

# Extract Universal APK
Write-Host "`nExtracting Universal APK..." -ForegroundColor Yellow
Expand-Archive -Path "$outputDir\universal.apks" -DestinationPath "$outputDir\universal_temp" -Force
Copy-Item "$outputDir\universal_temp\universal.apk" "$outputDir\nivio-$versionSafe-universal.apk" -Force
Remove-Item "$outputDir\universal_temp" -Recurse -Force
Remove-Item "$outputDir\universal.apks" -Force

# Extract Split APKs
Write-Host "Extracting Standalone Split APKs..." -ForegroundColor Yellow
Expand-Archive -Path "$outputDir\split.apks" -DestinationPath "$outputDir\split_temp" -Force

$splits = Get-ChildItem "$outputDir\split_temp\standalones\*.apk"
foreach ($split in $splits) {
    if ($split.Name -match "arm64_v8a") {
        Copy-Item $split.FullName "$outputDir\nivio-$versionSafe.apk" -Force
    } elseif ($split.Name -match "armeabi_v7a") {
        Copy-Item $split.FullName "$outputDir\nivio-$versionSafe-armeabi-v7a.apk" -Force
    } elseif ($split.Name -match "x86_64") {
        Copy-Item $split.FullName "$outputDir\nivio-$versionSafe-x86_64.apk" -Force
    }
}
Remove-Item "$outputDir\split_temp" -Recurse -Force
Remove-Item "$outputDir\split.apks" -Force

Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
Write-Host "Generated APKs in: $outputDir" -ForegroundColor Cyan
Get-ChildItem $outputDir -Filter "*.apk" | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  $($_.Name) ($size MB)"
}
Write-Host "`nUpload the APKs to GitHub Releases for Shorebird distribution." -ForegroundColor White
