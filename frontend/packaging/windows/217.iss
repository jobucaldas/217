; Inno Setup script for the Windows release build.
; Compile with: iscc /DAppVersion=1.0.0 packaging\windows\217.iss
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{6C1F1E0A-2170-4A17-9F0D-217A0C0DE217}
AppName=217
AppVersion={#AppVersion}
AppPublisher=jobucaldas
DefaultDirName={autopf}\217
DefaultGroupName=217
; Per-user install by default, so no admin prompt.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\..\build
OutputBaseFilename=217-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\a217.exe
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\217"; Filename: "{app}\a217.exe"
Name: "{autodesktop}\217"; Filename: "{app}\a217.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Run]
Filename: "{app}\a217.exe"; Description: "Launch 217"; Flags: nowait postinstall skipifsilent
