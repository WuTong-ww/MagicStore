param([string]$GamePath = '', [string[]]$GameArgs = @())
$ErrorActionPreference = 'Stop'

# This file is copied beside the exported game. It also works from scripts/dev.
# Directly opening the unwrapped .exe uses Windows AppData instead: use this
# launcher (or StartGame.cmd) when saves/cache/logs must stay beside the game.
if ([string]::IsNullOrWhiteSpace($GamePath)) {
    $GamePath = Join-Path $PSScriptRoot 'ZeroHourStore.exe'
    if (!(Test-Path -LiteralPath $GamePath -PathType Leaf)) {
        $GamePath = Join-Path $PSScriptRoot '../../build/windows/ZeroHourStore.exe'
    }
}
if (!(Test-Path -LiteralPath $GamePath -PathType Leaf)) { throw 'Exported game missing. Run scripts/dev/run.ps1 -Export first.' }
$game = (Resolve-Path -LiteralPath $GamePath).Path
$runtimeRoot = Join-Path (Split-Path -Parent $game) '.runtime'
$runtimePaths = @{
    APPDATA = Join-Path $runtimeRoot 'appdata'
    LOCALAPPDATA = Join-Path $runtimeRoot 'localappdata'
    TEMP = Join-Path $runtimeRoot 'temp'
    TMP = Join-Path $runtimeRoot 'temp'
}
$savedEnvironment = @{}
foreach ($name in $runtimePaths.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    foreach ($name in $runtimePaths.Keys) {
        New-Item -ItemType Directory -Force -Path $runtimePaths[$name] | Out-Null
        [Environment]::SetEnvironmentVariable($name, $runtimePaths[$name], 'Process')
    }
    # A pipeline makes PowerShell wait for a GUI subsystem executable too.
    & $game @GameArgs | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Game exited with code $LASTEXITCODE." }
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
