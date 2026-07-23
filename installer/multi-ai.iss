; Inno Setup script for the Multi-AI Windows installer.
;
; NO LONGER BUILT. Releases are packaged by Velopack's `vpk` CLI instead — see
; .github/workflows/release.yml — because Velopack ships delta patches between
; versions and updates the app in place from inside the app itself, which Inno
; cannot do. This file is kept for reference only; nothing compiles it, and
; editing it changes nothing about what ships.
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

; --- Upgrading over an existing install ---
; Running a newer setup.exe replaces the installed copy in place; there is no
; need to uninstall first. The AppId above is what ties the two together — Inno
; matches on it, reuses the previous install directory and remembers which
; tasks were ticked. The rest of this block is what makes that safe *here*.
;
; Restart Manager closes whatever is holding files under {app}, which at
; upgrade time means multi_ai.exe and the python.exe backend it spawned. Its
; default filter only scans .exe/.dll, and the backend's compiled modules are
; .pyd, so widen it — otherwise a locked module aborts the copy half-written.
CloseApplications=yes
CloseApplicationsFilter=*.exe,*.dll,*.pyd
; But do not let Restart Manager relaunch the app afterwards. Setup is
; elevated, so anything it restarts inherits the admin token and hits exactly
; the WinError 448 symlink failure that `runasoriginaluser` below exists to
; avoid. The postinstall entry in [Run] is the only launch path that is safe.
RestartApplications=no
; Two copies of setup writing {app} at once leaves a half-replaced payload.
SetupMutex={#AppName}-setup

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

[InstallDelete]
; Cleared before the new payload is copied in, not after. Inno only overwrites
; files it is currently shipping, and two kinds of file under backend\ outlive
; an upgrade otherwise:
;   - .pyd modules a previous release shipped and this one dropped. They stay
;     importable, and _list_models() builds the roster by enumerating the
;     modules present — so a stale one puts a model in the app's list that the
;     rest of this release knows nothing about.
;   - __pycache__ the interpreter writes after install, which Inno never
;     tracked and so never removes.
; Nothing user-created lives here: the pip-installed dependency stack and the
; weights cache are both outside {app}, so this is safe to delete outright.
Type: filesandordirs; Name: "{app}\backend"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\Uninstall {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
; runasoriginaluser is essential, not cosmetic. The installer runs elevated
; (PrivilegesRequired=admin), and without this flag the post-install launch
; inherits that admin token — so the app, and the Python backend it spawns,
; run as administrator. An elevated process refuses to traverse symbolic links
; created by a non-elevated one (Windows' anti-symlink-attack mitigation), and
; the Hugging Face weights cache under %USERPROFILE%\.cache is built entirely
; from such symlinks, so every model load then fails with
; "[WinError 448] ... untrusted mount point". Launching as the original
; (non-elevated) user keeps the app at the same integrity level as every later
; Start-menu launch, so the cache reads consistently.
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallDelete]
; The compiled .pyd files and __pycache__ the backend writes next to itself
; are generated after install, so Inno does not track them and would leave
; {app} behind.
Type: filesandordirs; Name: "{app}\backend"

[Code]
// Where Inno records the installed version for this AppId. Read to tell an
// upgrade from a downgrade; see InitializeSetup below.
const
  UninstallKey =
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{8B1D2F4A-6C3E-4A9B-9E2D-7F5A1C8B3D60}_is1';

function InstalledVersion(var Version: String): Boolean;
begin
  // A release build installs 64-bit (ArchitecturesInstallIn64BitMode), so its
  // key is in the 64-bit view — but check the 32-bit view too rather than
  // assume every copy in the wild was written by a build configured that way.
  Result := False;
  if IsWin64 then
    Result := RegQueryStringValue(HKLM64, UninstallKey, 'DisplayVersion', Version);
  if not Result then
    Result := RegQueryStringValue(HKLM32, UninstallKey, 'DisplayVersion', Version);
end;

// Upgrades run silently — matching AppId, same directory, same tasks, and the
// [InstallDelete] above clears the stale backend. The one case worth stopping
// for is the reverse: running an *older* installer over a newer install, which
// otherwise succeeds quietly and leaves someone wondering where their features
// went.
function InitializeSetup(): Boolean;
var
  Installed: String;
  OldVersion, NewVersion: Int64;
begin
  Result := True;
  if not InstalledVersion(Installed) then
    exit; // nothing installed — an ordinary first install
  // StrToVersion fails on the `0.0.0-dev+sha` that workflow_dispatch builds
  // carry. Those are test builds with no meaningful ordering, so let them
  // install over anything without comment.
  if not (StrToVersion(Installed, OldVersion) and
          StrToVersion('{#AppVersion}', NewVersion)) then
    exit;
  if ComparePackedVersion(NewVersion, OldVersion) < 0 then
    Result := MsgBox('Multi-AI ' + Installed + ' is already installed, and this ' +
                     'installer contains the older version {#AppVersion}.' + #13#10 + #13#10 +
                     'Continue and downgrade?', mbConfirmation, MB_YESNO) = IDYES;
end;

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
    DataDir := ExpandConstant('{localappdata}\MultiAI-Runtime');
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
