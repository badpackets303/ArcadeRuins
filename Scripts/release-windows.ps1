# X4-1 / X4-2 (ADR-094): the Windows release, on the owner's Windows machine - a Release build
# with the C runtime linked IN, every CTest test on those binaries, and an Inno Setup installer
# for the VST3 and the standalone. Signed with Authenticode when a certificate is given; the
# owner holds every certificate and types every password, as on the Mac.
#
# Needs, once:  what Scripts\validate-windows.ps1 needs, and Inno Setup 6 (https://jrsoftware.org/isinfo.php;
#               `winget install JRSoftware.InnoSetup`). Run from "Developer PowerShell for VS":
#     powershell -ExecutionPolicy Bypass -File Scripts\release-windows.ps1
#     powershell -ExecutionPolicy Bypass -File Scripts\release-windows.ps1 -CertificateThumbprint <thumbprint>
#
# WHY THE RUNTIME IS LINKED IN (-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded): MSVC's default needs
# the "Visual C++ Redistributable" on the machine. A developer's has it; a musician's clean
# Windows may not, and a plugin that cannot find VCRUNTIME140.dll does not say so - the host
# simply never lists it. The validation build uses the default; THIS build is the one tested here.
#
# Output: build\release-windows\ArcadeRuins-<version>-Windows-x64.exe and its SHA-256, and a
# block between two lines of ===== to paste back.
param([string]$CertificateThumbprint = "", [string]$TimestampUrl = "http://timestamp.digicert.com")

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
$Build = "build\release-plugin"
$Out   = Join-Path (Get-Location) "build\release-windows"
$Version = (Select-String -Path CMakeLists.txt -Pattern '^project\(ArcadeRuins VERSION ([0-9.]+)').Matches[0].Groups[1].Value
$Artefacts = Join-Path (Get-Location) "$Build\Sources\S1Plugin\ArcadeRuins_artefacts\Release"
$Report = New-Object System.Collections.Generic.List[string]
function Say($line) { $Report.Add($line); Write-Host $line }

$Iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe", "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Iscc) { throw "Inno Setup 6 is not installed: winget install JRSoftware.InnoSetup" }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$Dirty = (git status --porcelain)
Say "====================================================================="
Say "Arcade Ruins - Windows release - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Say "$(git rev-parse --abbrev-ref HEAD) @ $(git rev-parse --short HEAD), version $Version$(if ($Dirty) { '  (UNCOMMITTED EDITS - not a release build of a commit)' })"

cmake -S . -B $Build -DS1_BUILD_PLUGIN=ON -DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded | Out-Null
if ($LASTEXITCODE -ne 0) { throw "configure failed" }
cmake --build $Build --config Release --parallel | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Say "ok    built, Release, C runtime linked in"

$Tests = (ctest --test-dir $Build -C Release 2>&1 | Select-String "tests passed|tests failed").ToString().Trim()
Say "$(if ($LASTEXITCODE -eq 0) { 'ok  ' } else { 'FAIL' })  every CTest test on the release binaries: $Tests"
if ($LASTEXITCODE -ne 0) { Say "RESULT: FAILED"; Say "====================================================================="; exit 1 }

# What the plugin still asks Windows for. VCRUNTIME / MSVCP here would mean the runtime is NOT linked in.
$Dll = Get-ChildItem "$Artefacts\VST3\Arcade Ruins.vst3\Contents\x86_64-win\*.vst3" | Select-Object -First 1
$Imports = (dumpbin /dependents $Dll.FullName | Select-String "\.dll" | ForEach-Object { $_.ToString().Trim() }) -join " "
$NeedsRedistributable = $Imports -match "VCRUNTIME|MSVCP"
Say "$(if ($NeedsRedistributable) { 'FAIL' } else { 'ok  ' })  the plugin imports: $Imports"

function Sign($path) {
    if (-not $CertificateThumbprint) { return }
    signtool sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $path | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "signtool failed on $path" }
}
Sign $Dll.FullName
Sign "$Artefacts\Standalone\Arcade Ruins.exe"

& $Iscc /Qp "/DAppVersion=$Version" "/DArtefacts=$Artefacts" "/DOutput=$Out" "/DLicence=$((Get-Location).Path)\LICENSE" "/DNotice=$((Get-Location).Path)\NOTICE.md" Scripts\windows\ArcadeRuins.iss
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
$Installer = Join-Path $Out "ArcadeRuins-$Version-Windows-x64.exe"
Sign $Installer
$Hash = (Get-FileHash $Installer -Algorithm SHA256).Hash.ToLower()
"$Hash  $(Split-Path $Installer -Leaf)" | Out-File -Encoding ascii "$Installer.sha256"
Say "ok    installer: $(Split-Path $Installer -Leaf), $([math]::Round((Get-Item $Installer).Length / 1MB, 1)) MB"
Say "      sha256 $Hash"
Say "$(if ($CertificateThumbprint) { 'ok    signed (Authenticode, SHA-256, timestamped)' } else { 'note  NOT SIGNED: SmartScreen will warn. Pass -CertificateThumbprint once there is a certificate.' })"
Say "RESULT: $(if ($NeedsRedistributable) { 'FAILED' } else { 'BUILT' })"
Say "====================================================================="
