param([string]$ReportName = 'live-model-switch.json', [ValidatePattern('^[A-Za-z0-9_.-]+(,[A-Za-z0-9_.-]+)*$')][string]$ModelList = 'deepseek-v4.1-flash,glm-5.3,glm-5.3-flash,qwen3.8-27b-fp8,deepseek-v4.1-flash', [switch]$FollowupQuestions)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if ($ReportName -notmatch '^[A-Za-z0-9_-]+\.json$') { throw 'ReportName must be a simple JSON filename.' }
foreach ($requiredName in @('MAGIC_LIVE_API_URL','MAGIC_LIVE_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($requiredName,'Process'))) { throw "$requiredName must be supplied in the process environment." }
}
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
$paths = @{
    APPDATA = Join-Path $repo '.tools/live-switch-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/live-switch-localappdata'
    TEMP = Join-Path $repo '.tools/live-switch-temp'
    TMP = Join-Path $repo '.tools/live-switch-temp'
    MAGIC_LIVE_SWITCH_REPORT = Join-Path $repo ".tools/$ReportName"
    MAGIC_LIVE_SWITCH_MODELS = $ModelList
}
$previous = @{}
foreach ($name in @($paths.Keys)+@('MAGIC_GATEWAY_URL','MAGIC_GATEWAY_TOKEN','MAGIC_AI_KEY')) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    foreach ($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) { New-Item -ItemType Directory -Force -Path $paths[$name] | Out-Null }
    foreach ($name in $paths.Keys) { [Environment]::SetEnvironmentVariable($name,$paths[$name],'Process') }
    foreach ($name in @('MAGIC_GATEWAY_URL','MAGIC_GATEWAY_TOKEN','MAGIC_AI_KEY')) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $ErrorActionPreference = 'Continue'
    $liveScript = if ($FollowupQuestions) { 'res://tests/live/followup_questions_live.gd' } else { 'res://tests/live/model_switch_live.gd' }
    & $engine --headless --path $repo --script $liveScript
    $runCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($runCode -ne 0) { throw "Live model switching exited $runCode; inspect .tools/$ReportName." }
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
}
