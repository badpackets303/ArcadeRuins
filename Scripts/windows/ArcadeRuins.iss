; X4-1 (ADR-094): the Windows installer - Inno Setup 6. Compiled by Scripts\release-windows.ps1,
; which passes the version and where the built products are:
;     ISCC /DAppVersion=0.5.0 /DArtefacts=<...\ArcadeRuins_artefacts\Release> /DOutput=<dir> ArcadeRuins.iss
;
; It places the VST3 where every Windows host looks (Common Files\VST3) and the standalone under
; Program Files, each as a choice. The uninstaller Inno Setup writes removes exactly those; what
; a person made - %APPDATA%\BadPackets\Arcade Ruins: banks, tunings, settings - is never touched.

#ifndef AppVersion
  #error AppVersion is not defined: run Scripts\release-windows.ps1
#endif

[Setup]
; This GUID is the product's identity to Windows' "Apps" list. Never change it: a new one makes
; the next version install BESIDE the old one instead of over it.
AppId={{6F1C2B7E-3D5A-4E8B-9A41-7C0E5B2D9F13}
AppName=Arcade Ruins
AppVersion={#AppVersion}
AppPublisher=BadPackets
AppPublisherURL=https://github.com/badpackets303
DefaultDirName={autopf}\Arcade Ruins
DefaultGroupName=Arcade Ruins
DisableProgramGroupPage=yes
LicenseFile={#Licence}
OutputDir={#Output}
OutputBaseFilename=ArcadeRuins-{#AppVersion}-Windows-x64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayName=Arcade Ruins
WizardStyle=modern

[Types]
Name: "full"; Description: "VST3 plugin and standalone application"
Name: "custom"; Description: "Choose"; Flags: iscustom

[Components]
Name: "vst3"; Description: "VST3 plugin (Live, Reaper, Bitwig, FL Studio, Cubase...)"; Types: full custom
Name: "app"; Description: "Standalone application"; Types: full custom

[Files]
Source: "{#Artefacts}\VST3\Arcade Ruins.vst3\*"; DestDir: "{commoncf64}\VST3\Arcade Ruins.vst3"; Components: vst3; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#Artefacts}\Standalone\Arcade Ruins.exe"; DestDir: "{app}"; Components: app; Flags: ignoreversion
Source: "{#Notice}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Licence}"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{group}\Arcade Ruins"; Filename: "{app}\Arcade Ruins.exe"; Components: app

[UninstallDelete]
; the bundle's folder, in case a host wrote beside the binary
Type: filesandordirs; Name: "{commoncf64}\VST3\Arcade Ruins.vst3"
