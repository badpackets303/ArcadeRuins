# The Windows side of CI, on the owner's Windows machine (ADR-079's second amendment): what the
# workflows' windows-latest jobs do - MSVC build, every CTest test, Steinberg's VST3 validator,
# pluginval at strictness 10 with the validator handed to it.
#
# Needs, once:  Visual Studio 2022 or 2026 (any edition, Community included, or the Build Tools)
#               with "Desktop development with C++", and Git. Run it from the Start menu's
#               "Developer PowerShell for VS": that puts Visual Studio's OWN CMake first on PATH,
#               which matters for VS 2026 - CMake only knows that version from 4.2 on, and an
#               older CMake installed by itself will say it cannot find any Visual Studio.
#
# Run from the repository:
#     powershell -ExecutionPolicy Bypass -File Scripts\validate-windows.ps1
#
# The first run takes a while (it fetches and compiles JUCE, and builds the validator from
# Steinberg's SDK); later runs only rebuild what changed. It ends with a block between two
# lines of ===== : paste that block back. Everything it writes is under build\ (ignored by git).
# If the working tree has edits of its own, the block names them AND prints them, so a fix made
# here reaches the repository with the run that needed it.
#
# pluginval is Tracktion's release binary, pinned by version and SHA-256 - the same archive and
# checksum the workflow uses. Steinberg's validator is built here from the SDK, pinned by tag
# and commit.

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$Vst3SdkTag        = "v3.8.0_build_66"
$Vst3SdkCommit     = "9fad9770f2ae8542ab1a548a68c1ad1ac690abe0"
$PluginvalVersion  = "v1.0.4"
$PluginvalSha256   = "c08e61ce3b96db41636f8ec7e76f4c7e2c13ebdac7fa1b5a1f52b4f32ec715ab"

$Build   = "build\plugin"
$Work    = "build\validation"
$Plugin  = Join-Path (Get-Location) "$Build\Sources\S1Plugin\ArcadeRuins_artefacts\Release\VST3\Arcade Ruins.vst3"
$Report  = New-Object System.Collections.Generic.List[string]
$Failed  = $false
$Broken  = New-Object System.Collections.Generic.List[string]   # steps that failed; see Step
$BuildStep = "configure and build (MSVC, Release)"
$TestStep  = "every CTest test"
New-Item -ItemType Directory -Force -Path $Work | Out-Null

function Step {
    # `Needs` names a step this one cannot mean anything without. The owner, 2026-09-20: the
    # script twice reported "ok" for the tests and the validators AFTER the build had failed,
    # because the test programs and the .vst3 from the previous run were still on disk. A stale
    # pass is worse than no result, so a step whose ground has gone reports "not run" and its
    # body is never executed. Name the step a result really depends on, and no more: what a step
    # needs is usually a fresh BUILD, not a green test run (the owner again, 2026-09-21 — a failing
    # check skipped a measurement whose binaries were perfectly current).
    param([string]$Name, [scriptblock]$Body, [string]$Needs = "")
    Write-Host ""
    Write-Host "---- $Name"
    if ($Needs -and $script:Broken -contains $Needs) {
        # A step that did not run has no result either, so whatever needs THIS one skips too.
        $script:Broken.Add($Name) | Out-Null
        $script:Report.Add(("not run  {0}: {1} did not pass, so anything left on disk is from an older build" -f $Name, $Needs))
        Write-Host ("NOT RUN: " + $Needs + " did not pass")
        return
    }
    try {
        $result = & $Body
        $script:Report.Add(("ok    {0}: {1}" -f $Name, $result))
    } catch {
        $script:Failed = $true
        $script:Broken.Add($Name) | Out-Null
        $script:Report.Add(("FAIL  {0}: {1}" -f $Name, $_.Exception.Message))
        Write-Host ("FAILED: " + $_.Exception.Message)
    }
}

function Native([string]$Log, [string]$Exe, [string[]]$Arguments) {
    # Runs a program with everything it prints in a log file, and returns its exit code.
    # Windows PowerShell 5.1 turns a native program's stderr into error records, which "Stop"
    # would throw on - and cmake and git write progress there. So: "Continue" for the call.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Exe @Arguments 2>&1 | ForEach-Object { "$_" } | Out-File -Encoding utf8 $Log
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    return $code
}

function Run([string]$Log, [string]$Exe, [string[]]$Arguments) {
    # The same, and throws with the log's tail when the program fails.
    $code = Native $Log $Exe $Arguments
    if ($code -ne 0) {
        $tail = (Get-Content $Log -Tail 25) -join "`n"
        throw ("exit code {0}; see {1}`n{2}" -f $code, $Log, $tail)
    }
}

Step "the tools" {
    foreach ($tool in @("cmake", "ctest", "git")) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "$tool is not on PATH - run this from 'Developer PowerShell for VS' (Start menu), with 'Desktop development with C++' and Git installed"
        }
    }
    $cmakeVersion = ((& cmake --version) | Select-Object -First 1) -replace "cmake version ", ""
    $studio = ""
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $studio = ((& $vswhere -latest -products * -property catalog_productDisplayVersion) | Select-Object -First 1)
        $major = 0
        if ($studio -match "^(\d+)\.") { $major = [int]$Matches[1] }
        # Visual Studio 2026 is version 18; CMake has a generator for it from 4.2.
        if ($major -ge 18 -and ([version]($cmakeVersion -replace "[^0-9.].*$", "")) -lt [version]"4.2") {
            throw "CMake $cmakeVersion is older than 4.2 and does not know Visual Studio $studio. Use Visual Studio's own CMake: run this from 'Developer PowerShell for VS 2026'."
        }
    }
    "CMake $cmakeVersion; Visual Studio $studio; $((& git --version))"
}

if ($Failed) {
    # Nothing below can work without the tools; say so once instead of failing six more times.
    Write-Host ""
    foreach ($line in $Report) { Write-Host $line }
    Write-Host "RESULT: NOT RUN - set the tools up and run it again"
    exit 1
}

Step $BuildStep {
    Run "$Work\configure.log" "cmake" @("-S", ".", "-B", $Build, "-DS1_BUILD_PLUGIN=ON")
    Run "$Work\build.log" "cmake" @("--build", $Build, "--config", "Release", "--parallel", "8")
    "built"
}

Step $TestStep -Needs $BuildStep {
    $code = Native "$Work\ctest.log" "ctest" @("--test-dir", $Build, "-C", "Release", "--output-on-failure", "--verbose")
    $summary = (Select-String -Path "$Work\ctest.log" -Pattern "tests passed|tests failed" | Select-Object -Last 1).Line
    if ($code -ne 0) {
        $failedTests = (Select-String -Path "$Work\ctest.log" -Pattern "\*\*\*Failed|\(Failed\)" | ForEach-Object { $_.Line.Trim() }) -join "; "
        throw ("{0} -- {1} -- see {2}" -f $summary, $failedTests, "$Work\ctest.log")
    }
    $summary
}

# It needs a FRESH BINARY, not a green test run: the owner, 2026-09-21, when one unrelated check
# failed and a perfectly valid x86 measurement was skipped as "from an older build". The build is
# what makes the binaries current; gating on the tests threw away good data.
Step "what the denormal test measured here (x86)" -Needs $BuildStep {
    $lines = Select-String -Path "$Work\ctest.log" -Pattern "note  plugin" | ForEach-Object { ($_.Line -replace "^\s*\d+:\s*", "").Trim() }
    if (-not $lines) {
        [void](Native "$Work\denormals.log" "$Build\Tests\Plugin\PluginDenormalTests_artefacts\Release\PluginDenormalTests.exe" @())
        $lines = Select-String -Path "$Work\denormals.log" -Pattern "note  plugin" | ForEach-Object { $_.Line.Trim() }
    }
    "`n      " + ($lines -join "`n      ")
}

# ADR-096: this renderer draws "Pitch Trac" where the others draw "Pitch Track", and the width
# check passes here because it measures at 1x. The probe prints what THIS machine measures and what
# JUCE's own fitter does with it, so the machine that has the fault reports the numbers.
Step "what the caption probe measured here (ADR-096)" -Needs $BuildStep {
    $lines = Select-String -Path "$Work\ctest.log" -Pattern "^\s*\d+:\s*probe " | ForEach-Object { ($_.Line -replace "^\s*\d+:\s*", "").Trim() }
    if (-not $lines) {
        [void](Native "$Work\typeface.log" "$Build\Tests\Plugin\PluginTypefaceTests_artefacts\Release\PluginTypefaceTests.exe" @())
        $lines = Select-String -Path "$Work\typeface.log" -Pattern "^probe " | ForEach-Object { $_.Line.Trim() }
    }
    "`n      " + ($lines -join "`n      ")
}

$Validator = $null
Step "Steinberg's validator, built from the SDK at $Vst3SdkTag" {
    if (-not (Test-Path "$Work\vst3sdk\.git")) {
        Run "$Work\vst3sdk-clone.log" "git" @("clone", "--quiet", "--depth", "1", "--branch", $Vst3SdkTag, "https://github.com/steinbergmedia/vst3sdk.git", "$Work\vst3sdk")
    }
    $head = (& git -C "$Work\vst3sdk" rev-parse HEAD).Trim()
    if ($head -ne $Vst3SdkCommit) { throw "the SDK checkout is at $head, not $Vst3SdkCommit" }
    Run "$Work\vst3sdk-submodules.log" "git" @("-C", "$Work\vst3sdk", "submodule", "update", "--quiet", "--init", "--depth", "1", "base", "cmake", "pluginterfaces", "public.sdk")
    Run "$Work\vst3sdk-configure.log" "cmake" @("-S", "$Work\vst3sdk", "-B", "$Work\vst3sdk-build", "-DSMTG_ENABLE_VSTGUI_SUPPORT=OFF", "-DSMTG_ENABLE_VST3_PLUGIN_EXAMPLES=OFF", "-DSMTG_ENABLE_VST3_HOSTING_EXAMPLES=ON", "-DSMTG_RUN_VST_VALIDATOR=OFF")
    Run "$Work\vst3sdk-build.log" "cmake" @("--build", "$Work\vst3sdk-build", "--config", "Release", "--target", "validator", "--parallel", "8")
    $found = Get-ChildItem -Path "$Work\vst3sdk-build" -Recurse -Filter "validator.exe" | Select-Object -First 1
    if (-not $found) { throw "validator.exe was not built" }
    $script:Validator = $found.FullName
    "built"
}

Step "Steinberg's validator -e on the plugin" -Needs $BuildStep {
    if (-not $script:Validator) { throw "no validator" }
    $code = Native "$Work\vst3-validator.txt" $script:Validator @("-e", $Plugin)
    $result = (Select-String -Path "$Work\vst3-validator.txt" -Pattern "^Result" | Select-Object -Last 1).Line
    if ($code -ne 0) {
        $errors = (Select-String -Path "$Work\vst3-validator.txt" -Pattern "^ERROR" | ForEach-Object { $_.Line.Trim() }) -join "; "
        throw ("{0} -- {1} -- see {2}" -f $result, $errors, "$Work\vst3-validator.txt")
    }
    $result
}

Step "pluginval $PluginvalVersion, strictness 10" -Needs $BuildStep {
    $zip = "$Work\pluginval_Windows.zip"
    if (-not (Test-Path $zip)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://github.com/Tracktion/pluginval/releases/download/$PluginvalVersion/pluginval_Windows.zip" -OutFile $zip
    }
    $sum = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($sum -ne $PluginvalSha256) { Remove-Item $zip; throw "pluginval's archive has SHA-256 $sum, not the pinned $PluginvalSha256 - deleted, not run" }
    if (-not (Test-Path "$Work\pluginval-bin\pluginval.exe")) { Expand-Archive -Path $zip -DestinationPath "$Work\pluginval-bin" -Force }
    if (-not $script:Validator) { throw "no validator to hand to pluginval" }
    New-Item -ItemType Directory -Force -Path "$Work\pluginval-logs" | Out-Null
    $arguments = @("--strictness-level", "10", "--validate-in-process", "--verbose", "--vst3validator", $script:Validator, "--output-dir", "$Work\pluginval-logs", "--validate", $Plugin)
    $process = Start-Process -FilePath "$Work\pluginval-bin\pluginval.exe" -ArgumentList ($arguments | ForEach-Object { '"' + $_ + '"' }) -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$Work\pluginval-console.txt" -RedirectStandardError "$Work\pluginval-errors.txt"
    if ($process.ExitCode -ne 0) {
        $bangs = (Select-String -Path "$Work\pluginval-console.txt" -Pattern "!!!" | Select-Object -First 8 | ForEach-Object { $_.Line.Trim() }) -join "; "
        throw ("exit code {0} -- {1} -- see {2}" -f $process.ExitCode, $bangs, "$Work\pluginval-console.txt")
    }
    $skipped = Select-String -Path "$Work\pluginval-console.txt" -Pattern "Skipping" | Where-Object { $_.Line -notmatch "auval" }
    if ($skipped) { throw ("pluginval skipped a test: " + $skipped[0].Line.Trim()) }
    (Get-Content "$Work\pluginval-console.txt" -Tail 1)
}

$commit = (& git rev-parse --short HEAD).Trim()
$branch = (& git rev-parse --abbrev-ref HEAD).Trim()
# What is dirty, not just THAT something is: a run of 2026-09-20 reported "+ uncommitted changes"
# and the tree turned out to be clean afterwards, because `git status --porcelain` counts UNTRACKED
# files (Visual Studio's own .vs\, CMakeUserPresets.json) and `git diff` does not show those. The
# block now names them, so the next reader can tell a real edit from the IDE's litter.
$changes = @(& git status --porcelain)
$dirty   = if ($changes.Count) { " + uncommitted changes (listed below)" } else { "" }
$os     = (Get-CimInstance Win32_OperatingSystem).Caption
$cpu    = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim()

Write-Host ""
Write-Host "====================================================================="
Write-Host ("Arcade Ruins - Windows validation - {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm"))
Write-Host ("{0} @ {1}{2}" -f $branch, $commit, $dirty)
Write-Host ("{0} / {1}" -f $os, $cpu)
foreach ($line in $Report) { Write-Host $line }
if ($changes.Count) {
    Write-Host ("note  the working tree is not clean: {0} entr{1} (?? is untracked, M is edited)" -f $changes.Count, $(if ($changes.Count -eq 1) { "y" } else { "ies" }))
    foreach ($entry in ($changes | Select-Object -First 12)) { Write-Host ("      {0}" -f $entry.Trim()) }
    if ($changes.Count -gt 12) { Write-Host ("      ... and {0} more" -f ($changes.Count - 12)) }
    # And the EDITS themselves, in the block. Twice now a Windows fix has lived only in this
    # working tree, and each time getting it back cost a round trip. A tracked change is small
    # enough to carry here; anything bigger says so and is asked for by hand.
    $diff = @(& git diff --unified=3)
    if ($diff.Count -gt 0 -and $diff.Count -le 200) {
        Write-Host "note  what is edited, to be put in the repository:"
        foreach ($line in $diff) { Write-Host ("      {0}" -f $line) }
    } elseif ($diff.Count -gt 200) {
        Write-Host ("note  the edits are {0} lines: too long to print. Send 'git diff' separately." -f $diff.Count)
    }
}
if ($Failed) { Write-Host "RESULT: FAILED" } else { Write-Host "RESULT: PASSED" }
Write-Host "====================================================================="
# Where what was built is, to try by hand (ADR-081's list: open the standalone, play a keyboard
# without touching a setting, change the audio device while it sounds, quit and reopen).
$standalone = Get-ChildItem -Path "$Build\Sources\S1Plugin\ArcadeRuins_artefacts\Release\Standalone" -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($standalone) { Write-Host ("The standalone: " + $standalone.FullName) }
Write-Host ("The VST3:       " + $Plugin)
if ($Failed) { exit 1 }
