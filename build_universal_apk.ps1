# Build Universal APK from AAB using bundletool
# Usage: .\build_universal_apk.ps1 [-BuildType shorebird|normal] [-SkipBuild] [-Force]

param(
    [switch]$SkipBuild,
    [ValidateSet("shorebird", "normal")]
    [string]$BuildType = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Resolve repo root from script location so it works from any working directory.
$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $repoRoot) {
    $repoRoot = $PSScriptRoot
}

# Configuration
$mobileDir = Join-Path $repoRoot "packages\nivio_mobile"
$aabPath = Join-Path $mobileDir "build\app\outputs\bundle\release\app-release.aab"
$outputDir = Join-Path $mobileDir "build\app\outputs\bundle\release\apks"
$pubspecPath = Join-Path $mobileDir "pubspec.yaml"
$bundletoolPath = "C:\tools\bundletool.jar"

# Debug keystore (default Android debug signing)
$keystorePath = "$env:USERPROFILE\.android\debug.keystore"
$keyAlias = "androiddebugkey"
$keystorePassword = "android"
$keyPassword = "android"

Write-Host "=== Nivio Universal APK Builder ===" -ForegroundColor Cyan
Write-Host ""

# Prompt for build type if not provided and not skipping build
if (-not $SkipBuild -and [string]::IsNullOrWhiteSpace($BuildType)) {
    Write-Host "Select Android Release Type:" -ForegroundColor Cyan
    Write-Host "  [1] Shorebird Release (Enables Over-the-Air Dart code pushes)"
    Write-Host "  [2] Normal Release (Standard Flutter AAB build)"
    Write-Host "  [3] Skip Build (Only bundle APKs from existing AAB)"
    $choice = Read-Host "Enter choice [1, 2, or 3] (Default: 1)"
    if ($choice -eq "2") {
        $BuildType = "normal"
    } elseif ($choice -eq "3") {
        $SkipBuild = $true
    } else {
        $BuildType = "shorebird"
    }
}

# Step 1: Build the AAB release bundle if not skipping
if (-not $SkipBuild) {
    if (-not (Test-Path $mobileDir)) {
        throw "Mobile package directory not found at $mobileDir."
    }

    if ($BuildType -eq "shorebird") {
        Write-Host ""
        Write-Host "Checking Shorebird CLI..." -ForegroundColor Yellow
        $ShorebirdCmd = Get-Command shorebird -ErrorAction SilentlyContinue
        if (-not $ShorebirdCmd) {
            $ShorebirdCandidates = @(
                "$env:USERPROFILE\.shorebird\bin\shorebird.ps1",
                "$env:USERPROFILE\.shorebird\bin\shorebird.bat",
                "$env:USERPROFILE\.shorebird\bin\shorebird.cmd"
            )
            foreach ($cand in $ShorebirdCandidates) {
                if (Test-Path $cand) {
                    $ShorebirdCmd = $cand
                    break
                }
            }
        }

        if (-not $ShorebirdCmd) {
            throw "Shorebird CLI was not found. Please install Shorebird (https://docs.shorebird.dev) to build Shorebird releases."
        }

        # Verify if logged in to Shorebird
        Write-Host "Verifying Shorebird credentials..." -ForegroundColor Yellow
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c shorebird apps list"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()
        $appsOutput = $proc.StandardOutput.ReadToEnd() + " " + $proc.StandardError.ReadToEnd()

        if ($appsOutput -match "shorebird login" -or $appsOutput -match "rejected your stored credentials" -or $appsOutput -match "Failed to refresh credentials") {
            Write-Host ""
            Write-Host "Shorebird is not logged in or credentials have expired." -ForegroundColor Yellow
            Write-Host "Launching 'shorebird login'..." -ForegroundColor Cyan
            & cmd.exe /c shorebird login
            if ($LASTEXITCODE -ne 0) {
                throw "Shorebird login was unsuccessful. Cannot proceed with Shorebird release."
            }
        }

        Write-Host "Building Shorebird Android Release (AAB + OTA)..." -ForegroundColor Green
        Push-Location $mobileDir
        try {
            $shorebirdArgs = @("release", "android", "--artifact=aab")
            if ($Force) { $shorebirdArgs += "--force" }
            & cmd.exe /c shorebird @shorebirdArgs
            if ($LASTEXITCODE -ne 0) {
                throw "Shorebird release android failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "Building Standard Flutter Android Release (AAB)..." -ForegroundColor Cyan
        Push-Location $mobileDir
        try {
            & flutter build appbundle --release
            if ($LASTEXITCODE -ne 0) {
                throw "flutter build appbundle failed with exit code $LASTEXITCODE."
            }
        } finally {
            Pop-Location
        }
    }
}

function Resolve-PythonPath {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd -and $pythonCmd.Source -and (Test-Path $pythonCmd.Source)) { return $pythonCmd.Source }
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd -and $pyCmd.Source -and (Test-Path $pyCmd.Source)) { return $pyCmd.Source }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Python\bin\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python311\python.exe'),
        'C:\Python312\python.exe',
        'C:\Python311\python.exe'
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $found = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Python') -Filter 'python.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

function Resolve-AndroidBuildTools {
    $sdkRoots = @(
        $env:ANDROID_HOME,
        $env:ANDROID_SDK_ROOT,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk')
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($sdk in $sdkRoots) {
        $buildToolsDir = Join-Path $sdk "build-tools"
        if (Test-Path $buildToolsDir) {
            $latestTools = Get-ChildItem -Directory $buildToolsDir | Sort-Object Name -Descending | Select-Object -First 1
            if ($latestTools) {
                $zipalign = Join-Path $latestTools.FullName "zipalign.exe"
                $apksigner = Join-Path $latestTools.FullName "apksigner.bat"
                if ((Test-Path $zipalign) -and (Test-Path $apksigner)) {
                    return @{
                        Zipalign = $zipalign
                        Apksigner = $apksigner
                        Dir = $latestTools.FullName
                    }
                }
            }
        }
    }
    return $null
}

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

# Check Java
Write-Host ""
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
    Write-Host "  Run without -SkipBuild to compile the AAB first." -ForegroundColor Red
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

# Extract version (check root pubspec first, then fallback to mobile package pubspec)
$version = "unknown"
$candidatePubspecs = @(
    (Join-Path $repoRoot "pubspec.yaml"),
    $pubspecPath
)
foreach ($p in $candidatePubspecs) {
    if (Test-Path $p) {
        $versionLine = Select-String -Path $p -Pattern "^version:\s*(.+)$" | Select-Object -First 1
        if ($versionLine -and $versionLine.Matches.Count -gt 0) {
            $version = $versionLine.Matches[0].Groups[1].Value.Trim()
            break
        }
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

# Extract Universal APK
Write-Host "`nExtracting Universal APK..." -ForegroundColor Yellow
$universalZip = "$outputDir\universal.zip"
if (Test-Path "$outputDir\universal.apks") {
    Rename-Item -Path "$outputDir\universal.apks" -NewName "universal.zip" -Force
}
if (Test-Path "$outputDir\universal_temp") {
    Remove-Item -Path "$outputDir\universal_temp" -Recurse -Force
}
Expand-Archive -Path $universalZip -DestinationPath "$outputDir\universal_temp" -Force
$universalApkPath = "$outputDir\nivio-$versionSafe-universal.apk"
Copy-Item "$outputDir\universal_temp\universal.apk" $universalApkPath -Force
Remove-Item "$outputDir\universal_temp" -Recurse -Force
if (Test-Path $universalZip) { Remove-Item $universalZip -Force }

# Build Architecture-Specific Split APKs using Python stripper
Write-Host "`nBuilding Architecture-Specific Split APKs (Shorebird compatible)..." -ForegroundColor Yellow
$pythonExe = Resolve-PythonPath
$buildTools = Resolve-AndroidBuildTools
$stripScript = Join-Path $repoRoot "scripts\strip_apk.py"

if ($pythonExe -and $buildTools -and (Test-Path $stripScript)) {
    Write-Host "  Using Python: $pythonExe" -ForegroundColor Green
    Write-Host "  Using Build Tools: $($buildTools.Dir)" -ForegroundColor Green

    $abiTargets = @(
        @{ Abi = "arm64-v8a"; Output = "$outputDir\nivio-$versionSafe.apk" },
        @{ Abi = "armeabi-v7a"; Output = "$outputDir\nivio-$versionSafe-armeabi-v7a.apk" },
        @{ Abi = "x86_64"; Output = "$outputDir\nivio-$versionSafe-x86_64.apk" }
    )

    foreach ($target in $abiTargets) {
        $abi = $target.Abi
        $finalApk = $target.Output
        $unalignedApk = [System.IO.Path]::ChangeExtension($finalApk, ".unaligned.apk")

        Write-Host "  Processing $abi..." -ForegroundColor Yellow
        & $pythonExe $stripScript $universalApkPath $unalignedApk $abi
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $unalignedApk)) {
            Write-Host "    WARNING: Failed to strip APK for $abi" -ForegroundColor Red
            continue
        }

        # Align
        if (Test-Path $finalApk) { Remove-Item $finalApk -Force }
        & $buildTools.Zipalign -f -p 4 $unalignedApk $finalApk
        Remove-Item $unalignedApk -Force -ErrorAction SilentlyContinue

        # Sign
        & $buildTools.Apksigner sign --ks $keystorePath --ks-key-alias $keyAlias --ks-pass "pass:$keystorePassword" --key-pass "pass:$keyPassword" $finalApk
        if ($LASTEXITCODE -ne 0) {
            Write-Host "    WARNING: Failed to sign APK for $abi" -ForegroundColor Red
        } else {
            $createdSize = [math]::Round((Get-Item $finalApk).Length / 1MB, 2)
            Write-Host "    Created: $(Split-Path -Leaf $finalApk) ($createdSize MB)" -ForegroundColor Green
        }
    }
    Remove-Item "$outputDir\*.idsig" -Force -ErrorAction SilentlyContinue
} else {
    if (-not $pythonExe) { Write-Host "  Notice: Python was not found; skipping architecture-specific split APKs." -ForegroundColor Yellow }
    if (-not $buildTools) { Write-Host "  Notice: Android SDK build-tools (zipalign/apksigner) not found; skipping architecture-specific split APKs." -ForegroundColor Yellow }
}

Write-Host "`n=== SUCCESS ===" -ForegroundColor Green
Write-Host "Generated APKs in: $outputDir" -ForegroundColor Cyan
Get-ChildItem $outputDir -Filter "*.apk" | ForEach-Object {
    $size = [math]::Round($_.Length / 1MB, 2)
    Write-Host "  $($_.Name) ($size MB)"
}
Write-Host "`nUpload the APKs to GitHub Releases for distribution." -ForegroundColor White
