; TX Chat setup. Installs the official Stoat app when needed, then adds shortcuts
; that open it on https://txchat.duckdns.org. The original Stoat shortcut is kept.
;
; Compile with Inno Setup 6:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" TXChat.iss

#define AppVersion "1.0.1"
#define Repo ".."

[Setup]
AppId={{03D84DD8-A4C7-407C-8DA4-1CFBD60CEE42}
AppName=TX Chat
AppVersion={#AppVersion}
AppPublisher=Philip Miller
AppCopyright=Copyright (c) 2026 Philip Miller
DefaultDirName={localappdata}\Programs\TX Chat
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#Repo}
OutputBaseFilename=tx_chat
Compression=lzma2
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
Uninstallable=yes
UninstallDisplayName=TX Chat
SetupIconFile={#Repo}\tx-icon.ico
UninstallDisplayIcon={app}\tx-icon.ico
InfoBeforeFile=info.txt
VersionInfoVersion=1.0.1.0
VersionInfoProductName=TX Chat
VersionInfoCompany=Philip Miller
VersionInfoDescription=Opens Stoat on a private server
CloseApplications=yes

[Messages]
WelcomeLabel2=This installs TX Chat for this Windows account.
InfoBeforeLabel=TX Chat redirects Stoat to a private server.
InfoBeforeClickLabel=When you are ready to continue, click Next.
FinishedLabel=TX Chat redirects Stoat to the private server.%n%nOpen the TX Chat shortcut for the private server. Stoat no longer opens by itself at sign-in. Quit TX Chat before using the original Stoat shortcut for the public server.
ConfirmUninstall=Uninstall TX Chat? This removes the TX Chat shortcuts. Stoat and the original Stoat shortcut stay installed.

[Files]
Source: "{#Repo}\tx-icon.ico"; DestDir: "{app}"
Source: "info.txt"; DestDir: "{app}"; DestName: "Private server.txt"
Source: "{#Repo}\app\Ensure-Stoat.ps1"; Flags: dontcopy
Source: "{#Repo}\app\Open-TXChat.ps1"; DestDir: "{app}"
Source: "{#Repo}\app\Open-TXChat.vbs"; DestDir: "{app}"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "stoat-desktop"; Flags: deletevalue

[Icons]
Name: "{autoprograms}\TX Chat"; Filename: "{sys}\wscript.exe"; Parameters: "//B ""{app}\Open-TXChat.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\tx-icon.ico"; Comment: "Stoat on the private server txchat.duckdns.org"
Name: "{autodesktop}\TX Chat"; Filename: "{sys}\wscript.exe"; Parameters: "//B ""{app}\Open-TXChat.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\tx-icon.ico"; Comment: "Stoat on the private server txchat.duckdns.org"

[UninstallDelete]
Type: files; Name: "{autoprograms}\TX Chat.lnk"
Type: files; Name: "{autodesktop}\TX Chat.lnk"

[Code]
var
  DownloadPage: TDownloadWizardPage;
  StoatPrepared: Boolean;

procedure InitializeWizard;
begin
  DownloadPage := CreateDownloadPage('Downloading Stoat',
    'TX Chat uses the official Stoat app. The download can take a few minutes.',
    nil);
  DownloadPage.ShowBaseNameInsteadOfUrl := True;
end;

function StoatStubPath: String;
begin
  Result := ExpandConstant('{localappdata}\Stoat\stoat-desktop.exe');
end;

function StoatErrorText: String;
var
  ErrorFile: String;
  ErrorText: AnsiString;
begin
  Result := 'Stoat could not be installed.';
  ErrorFile := ExpandConstant('{%TEMP}\txchat-stoat-error.txt');
  if LoadStringFromFile(ErrorFile, ErrorText) then
    Result := Trim(String(ErrorText));
end;

function RunOfficialSetup: String;
var
  ProgressPage: TOutputProgressWizardPage;
  ResultCode: Integer;
  Params: String;
  ScriptPath: String;
  SetupPath: String;
begin
  Result := '';
  ScriptPath := ExpandConstant('{tmp}\Ensure-Stoat.ps1');
  SetupPath := ExpandConstant('{tmp}\stoat-desktop-setup.exe');
  ExtractTemporaryFile('Ensure-Stoat.ps1');
  if not FileExists(SetupPath) then begin
    Result := 'The Stoat installer download is missing.';
    Exit;
  end;

  ProgressPage := CreateOutputProgressPage('Installing Stoat',
    'The official Stoat setup is running. If Stoat opens on the public server, this setup closes that window. Use the TX Chat shortcut for the private server.');
  ProgressPage.SetText('Installing the official Stoat app...', '');
  ProgressPage.Show;
  try
    Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" "' + SetupPath + '"';
    if not Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      Params, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
      Result := 'Windows PowerShell could not start.'
    else if ResultCode <> 0 then
      Result := StoatErrorText
    else if not FileExists(StoatStubPath) then
      Result := 'Stoat setup finished without the Stoat app in place.';
  finally
    ProgressPage.Hide;
  end;
end;

function PrepareStoat: String;
begin
  Result := '';
  if StoatPrepared or FileExists(StoatStubPath) then begin
    StoatPrepared := True;
    Exit;
  end;

  DownloadPage.Clear;
  DownloadPage.Add(
    'https://github.com/stoatchat/for-desktop/releases/latest/download/stoat-desktop-setup.exe',
    'stoat-desktop-setup.exe',
    '');
  if not WizardSilent then
    DownloadPage.Show;
  try
    try
      DownloadPage.Download;
    except
      if DownloadPage.AbortedByUser then
        Result := 'Stoat download was cancelled.'
      else
        Result := 'Stoat could not be downloaded. ' + GetExceptionMessage;
    end;
  finally
    if not WizardSilent then
      DownloadPage.Hide;
  end;
  if Result <> '' then
    Exit;

  Result := RunOfficialSetup;
  if Result = '' then
    StoatPrepared := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  Error: String;
begin
  Result := True;
  if CurPageID <> wpInfoBefore then
    Exit;
  Error := PrepareStoat;
  if Error <> '' then begin
    SuppressibleMsgBox(Error, mbCriticalError, MB_OK, IDOK);
    Result := False;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := PrepareStoat;
end;
