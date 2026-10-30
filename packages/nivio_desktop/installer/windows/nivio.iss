#define MyAppName "Nivio"
#define MyAppPublisher "Nivio"
#define MyAppExeName "Nivio.exe"

#ifndef AppVersion
#define AppVersion "2.2.3"
#endif

#ifndef SourceDir
#define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Stable, app-unique GUID: never change it, or new versions install next to
; the old one instead of upgrading it.
AppId={{6F55CF32-4F03-49DB-926A-82FB1E1175D4}
AppName={#MyAppName}
AppVersion={#AppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\dist\windows
OutputBaseFilename=Nivio-Setup-{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayIcon={app}\{#MyAppExeName}
; Installing over an older version: close a running Nivio instead of failing
; on files it has open (see also PrepareToInstall below). Nivio relaunches
; itself after a silent in-app update ([Run] below), so Windows doesn't need to.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[InstallDelete]
; Clear the previous version's program files first, so libraries or assets a
; newer version no longer ships can't linger and clash with it. User data lives
; in %APPDATA% / %LOCALAPPDATA%, not here.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "*.lib,*.exp,*.pdb,*.WebView2\*,*.WebView2"

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
; In-app updates run this installer with /SILENT: start the new version when done.
Filename: "{app}\{#MyAppExeName}"; Flags: nowait runasoriginaluser; Check: WizardSilent

[Code]
// A Nivio left running (even with no window, e.g. one that is still shutting
// down) keeps its files locked, and the new version would hand off to it and
// quit on launch (single-instance check). Make sure none is running.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM {#MyAppExeName}', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
  // taskkill returns 128 when no such process is running; either way, go on.
  Sleep(500);
  Result := '';
end;
