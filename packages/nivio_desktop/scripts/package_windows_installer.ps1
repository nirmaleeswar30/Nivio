param(
  [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

function Find-Iscc {
  if (-not [string]::IsNullOrWhiteSpace($env:ISCC_PATH) -and (Test-Path $env:ISCC_PATH)) {
    return $env:ISCC_PATH
  }

  $Command = Get-Command iscc.exe -ErrorAction SilentlyContinue
  if ($Command) {
    return $Command.Source
  }

  $Candidates = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
  )

  foreach ($Candidate in $Candidates) {
    if (Test-Path $Candidate) {
      return $Candidate
    }
  }

  throw "Inno Setup 6 compiler was not found. Install Inno Setup 6 or set ISCC_PATH to ISCC.exe."
}

function Read-AppVersion {
  $Pubspec = Join-Path $RootDir "pubspec.yaml"
  $VersionLine = Select-String -Path $Pubspec -Pattern "^version:\s*(.+)$" | Select-Object -First 1
  if (-not $VersionLine) {
    return "1.0.0"
  }

  $Version = $VersionLine.Matches[0].Groups[1].Value.Trim()
  return ($Version -split "\+")[0]
}

if (-not $SkipBuild) {
  & (Join-Path $RootDir "scripts\build_windows_release.ps1")
}

$SourceDir = Join-Path $RootDir "build\windows\x64\runner\Release"
if ((-not (Test-Path (Join-Path $SourceDir "Nivio.exe"))) -and (-not (Test-Path (Join-Path $SourceDir "nivio.exe")))) {
  $LegacySourceDir = Join-Path $RootDir "build\windows\runner\Release"
  if ((Test-Path (Join-Path $LegacySourceDir "Nivio.exe")) -or (Test-Path (Join-Path $LegacySourceDir "nivio.exe"))) {
    $SourceDir = $LegacySourceDir
  }
}

if ((-not (Test-Path (Join-Path $SourceDir "Nivio.exe"))) -and (-not (Test-Path (Join-Path $SourceDir "nivio.exe")))) {
  throw "Windows release output was not found. Expected Nivio.exe or nivio.exe under build\windows\x64\runner\Release."
}

# If binary is nivio.exe, ensure Nivio.exe is available for the installer
if ((Test-Path (Join-Path $SourceDir "nivio.exe")) -and (-not (Test-Path (Join-Path $SourceDir "Nivio.exe")))) {
  Copy-Item (Join-Path $SourceDir "nivio.exe") (Join-Path $SourceDir "Nivio.exe") -Force
}

$DistDir = Join-Path $RootDir "dist\windows"
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

$Iscc = Find-Iscc
$AppVersion = Read-AppVersion
$ScriptPath = Join-Path $RootDir "installer\windows\nivio.iss"

Write-Host "Compiling Windows Inno Setup installer..."
& $Iscc "/DAppVersion=$AppVersion" "/DSourceDir=$SourceDir" $ScriptPath

$Installer = Join-Path $DistDir "Nivio-Setup-$AppVersion.exe"
if (Test-Path $Installer) {
  $SizeMB = [math]::Round(((Get-Item $Installer).Length / 1MB), 2)
  Write-Host "SUCCESS: Windows installer created: $Installer ($SizeMB MB)" -ForegroundColor Green
} else {
  Write-Warning "Inno Setup finished, check $DistDir for output installer."
}
