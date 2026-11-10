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
    foreach ($name in $runtimePaths.Keys) {
        New-Item -ItemType Directory -Force -Path $runtimePaths[$name] | Out-Null
        [Environment]::SetEnvironmentVariable($name, $runtimePaths[$name], 'Process')
    }
    if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
    if ($Test) {
        Invoke-Godot @('--headless', '--path', $repo, '--import')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/smoke.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/provider_contract.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/oracle_rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/acceptance.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/ui_capture.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/restart.gd', '--', 'write')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/restart.gd', '--', 'read')
    } elseif ($Export) {
        $outDir = Join-Path $repo 'build/windows'
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Invoke-Godot @('--headless', '--path', $repo, '--export-release', 'Windows Desktop', (Join-Path $outDir 'ZeroHourStore.exe'))
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'play-export.ps1') -Destination (Join-Path $outDir 'play-export.ps1') -Force
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
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
