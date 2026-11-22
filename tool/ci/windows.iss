[Setup]
AppId=Sableen
AppName=Sableen
AppVersion={#GetEnv("APP_VERSION")}
DefaultDirName={localappdata}\Programs\Sableen
DefaultGroupName=Sableen
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=Sableen-windows-x64-setup
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\sableen.exe
SetupIconFile=..\..\windows\runner\resources\app_icon.ico

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; Excludes: "*.pdb"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#GetEnv("SABLEEN_VC_REDIST")}\*.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Sableen"; Filename: "{app}\sableen.exe"
