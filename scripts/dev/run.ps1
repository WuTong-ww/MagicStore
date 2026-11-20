param([switch]$Editor, [switch]$Test, [switch]$Export, [string[]]$GameArgs = @())
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
function Invoke-Godot([string[]]$GodotArgs) {
    $output = & $engine @GodotArgs 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|ERROR:').Count -gt 0) { throw "Godot validation failed (exit $code)." }
}
# Redirect only this process and its children; never change machine/user settings.
# Godot still uses user://. Its Windows APPDATA parent is now on the project drive.
$savedEnvironment = @{}
$savedCondaDllSearch = [Environment]::GetEnvironmentVariable('CONDA_DLL_SEARCH_MODIFICATION_ENABLE', 'Process')
$runtimePaths = @{
    APPDATA = Join-Path $repo '.runtime/appdata'
    LOCALAPPDATA = Join-Path $repo '.runtime/localappdata'
    TEMP = Join-Path $repo '.runtime/temp'
    TMP = Join-Path $repo '.runtime/temp'
}
if ($Test) {
    $runtimePaths.APPDATA = Join-Path $repo '.tools/test-appdata'
    $runtimePaths.LOCALAPPDATA = Join-Path $repo '.tools/test-localappdata'
    $runtimePaths.TEMP = Join-Path $repo '.tools/test-temp'
    $runtimePaths.TMP = $runtimePaths.TEMP
}
foreach ($name in $runtimePaths.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    if ($Test) {
        # Conda Python on Windows needs its bundled OpenSSL DLL search enabled.
        # This affects this test process and its children only.
        [Environment]::SetEnvironmentVariable('CONDA_DLL_SEARCH_MODIFICATION_ENABLE', '1', 'Process')
    }
    foreach ($name in $runtimePaths.Keys) {
        New-Item -ItemType Directory -Force -Path $runtimePaths[$name] | Out-Null
        [Environment]::SetEnvironmentVariable($name, $runtimePaths[$name], 'Process')
    }
    if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
    # Fresh source ZIPs do not include Godot's generated .godot/imported cache.
    # Import once before launching the runtime/editor so FontFile and PNG resources exist.
    $fontImportDir = Join-Path $repo '.godot/imported'
    $fontImportExists = $false
    if (Test-Path -LiteralPath $fontImportDir) {
        $fontImportExists = [bool](Get-ChildItem -LiteralPath $fontImportDir -Filter 'NotoSansSC*.fontdata' -ErrorAction SilentlyContinue | Select-Object -First 1)
    }
    if (!$fontImportExists -and !$Test) {
        Invoke-Godot @('--headless', '--path', $repo, '--import')
    }
    if ($Test) {
        Invoke-Godot @('--headless', '--path', $repo, '--import')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/smoke.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/save_delete.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/provider_contract.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/dialogue/grounding.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/dialogue/followup_questions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/oracle_rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/acceptance.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/legacy_guests.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/generated_cases.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/ui_capture.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/restart.gd', '--', 'write')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/restart.gd', '--', 'read')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/integration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/people_bridge.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/people_restart.gd', '--', 'write')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/people_restart.gd', '--', 'read')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/scene_visuals.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/arrival_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/consultation_layout.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/arrival_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/save_delete_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/generated_people.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/generation_arrival_slots.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/generated_people_ui.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/followup_questions.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/followup_questions_ui.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/chat_keyboard_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/opening_guests.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/project_cleanup.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/api_settings_ui.gd')
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-http.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'HTTP integration tests failed.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-person-http.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Background person HTTP tests failed.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-people.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'People regression tests failed.' }
    } elseif ($Export) {
        $outDir = Join-Path $repo 'build/windows'
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Invoke-Godot @('--headless', '--path', $repo, '--export-release', 'Windows Desktop', (Join-Path $outDir 'ZeroHourStore.exe'))
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'play-export.ps1') -Destination (Join-Path $outDir 'play-export.ps1') -Force
        $licenseDir = Join-Path $outDir 'licenses'
        New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
        foreach ($licenseFile in @('docs/GODOT-LICENSE.txt', 'docs/GODOT-COPYRIGHT.txt', 'docs/third-party.md', 'assets/fonts/OFL.txt')) {
            Copy-Item -LiteralPath (Join-Path $repo $licenseFile) -Destination $licenseDir -Force
        }
        @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0play-export.ps1"
if errorlevel 1 pause
'@ | Set-Content -LiteralPath (Join-Path $outDir 'StartGame.cmd') -Encoding ASCII
        Write-Host "Portable game entry: $(Join-Path $outDir 'StartGame.cmd')"
    } elseif ($Editor) {
        & $engine --path $repo --editor @GameArgs
        if ($LASTEXITCODE -ne 0) { throw "Godot editor failed (exit $LASTEXITCODE)." }
    } else {
        & $engine --path $repo @GameArgs
        if ($LASTEXITCODE -ne 0) { throw "Godot game failed (exit $LASTEXITCODE)." }
    }
} finally {
    [Environment]::SetEnvironmentVariable('CONDA_DLL_SEARCH_MODIFICATION_ENABLE', $savedCondaDllSearch, 'Process')
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
