; Inno Setup script for the Multi-AI Windows installer.
;
; This exists because `flutter build windows` does not produce a runnable
; single file — it produces multi_ai.exe plus flutter_windows.dll, the plugin
; DLLs (file_picker, record, and llamadart's ggml-vulkan.dll / mtmd.dll) and a
; data\ directory. Shipping the .exe on its own gives a downloader a program
; that will not launch. Inno wraps the whole tree into one setup .exe, which is
; the thing that actually gets attached to a GitHub release.
;
; What it does NOT contain is the Python dependency stack. torch alone is
; 4.12GB and a GitHub release asset is capped at 2GB, so requirements.txt is
; installed on first launch instead — see app/lib/backend_process.dart.
;
; Compiled by .github/workflows/release.yml, which stages everything under
; installer\staging first. Build locally with:
;   iscc installer\multi-ai.iss /DAppVersion=1.0.0

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif

#define AppName "Multi-AI"
#define AppExeName "multi_ai.exe"

[Setup]
AppId={{8B1D2F4A-6C3E-4A9B-9E2D-7F5A1C8B3D60}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=CAJ654
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
OutputDir=..\dist
OutputBaseFilename=MultiAI-Setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
; The Flutter app and the bundled CPython are both 64-bit only.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
; Per-machine install into Program Files needs elevation once, at install
; time. Nothing at runtime does — the dependency stack deliberately installs
; under %LOCALAPPDATA% so first launch never prompts for admin.
PrivilegesRequired=admin
UninstallDisplayIcon={app}\{#AppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
; The Flutter release tree, staged by the workflow.
Source: "staging\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; The backend payload: embeddable CPython, the Cython-compiled multi_ai
; package, bootstrap.py, pip.pyz and requirements.txt.
Source: "staging\backend\*"; DestDir: "{app}\backend"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; The compiled .pyd files and __pycache__ the backend writes next to itself
; are generated after install, so Inno does not track them and would leave
; {app} behind.
Type: filesandordirs; Name: "{app}\backend"

[Code]
// The ~2.5GB dependency stack and any downloaded model weights live outside
// {app}, so an uninstall leaves them behind by default. That is usually right
// — reinstalling then skips the long first-run download — but it silently
// keeps tens of gigabytes on a machine whose owner thinks they removed the
// app. So ask.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    DataDir := ExpandConstant('{localappdata}\MultiAI');
    if DirExists(DataDir) then
    begin
      if MsgBox('Also delete the downloaded AI runtime (about 2.5 GB)?' + #13#10 + #13#10 +
                'Keep it if you plan to reinstall — it saves repeating the ' +
                'first-run download. Downloaded model weights in your Hugging ' +
                'Face cache are not affected either way.',
                mbConfirmation, MB_YESNO) = IDYES then
        DelTree(DataDir, True, True, True);
    end;
  end;
end;
