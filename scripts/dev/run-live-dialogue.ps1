param([string]$PlanPath = 'tests/live/plan.example.json')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$planFile = if ([IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $repo $PlanPath }
if (!(Test-Path -LiteralPath $planFile -PathType Leaf)) { throw 'Live dialogue plan JSON not found.' }
foreach ($requiredName in @('MAGIC_LIVE_API_URL','MAGIC_LIVE_MODEL','MAGIC_LIVE_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($requiredName,'Process'))) {
        throw "$requiredName must be supplied in this process environment."
    }
}
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
$paths = @{
    APPDATA = Join-Path $repo '.tools/live-dialogue-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/live-dialogue-localappdata'
    TEMP = Join-Path $repo '.tools/live-dialogue-temp'
    TMP = Join-Path $repo '.tools/live-dialogue-temp'
    MAGIC_LIVE_PLAN_PATH = [IO.Path]::GetFullPath($planFile)
}
$previous = @{}
foreach ($name in @($paths.Keys) + @('MAGIC_GATEWAY_URL','MAGIC_GATEWAY_TOKEN','MAGIC_AI_KEY')) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
try {
    foreach ($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) { New-Item -ItemType Directory -Force -Path $paths[$name] | Out-Null }
    foreach ($name in $paths.Keys) { [Environment]::SetEnvironmentVariable($name,$paths[$name],'Process') }
    foreach ($name in @('MAGIC_GATEWAY_URL','MAGIC_GATEWAY_TOKEN','MAGIC_AI_KEY')) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $ErrorActionPreference = 'Continue'
    & $engine --headless --path $repo --script res://tests/live/dialogue_live.gd
    $liveExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($liveExit -ne 0) { throw "Live dialogue evaluation exited $liveExit; inspect the per-turn JSON report." }
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
}
