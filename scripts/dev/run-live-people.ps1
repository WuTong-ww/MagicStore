param([string]$ReportName = 'live-people-generation.json', [int]$GenerationWaitSeconds = 180, [ValidateRange(2,6)][int]$GenerationTarget = 2, [string]$ApprovedInputReport = '')
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if ($ReportName -notmatch '^[A-Za-z0-9_-]+\.json$') { throw 'ReportName must be a simple JSON filename.' }
$approvedReportPath = ''
if (![string]::IsNullOrWhiteSpace($ApprovedInputReport)) {
    $toolsRoot = (Resolve-Path -LiteralPath (Join-Path $repo '.tools')).Path
    $candidatePath = if ([IO.Path]::IsPathRooted($ApprovedInputReport)) { $ApprovedInputReport } else { Join-Path $repo $ApprovedInputReport }
    $approvedReportPath = (Resolve-Path -LiteralPath $candidatePath).Path
    if (!$approvedReportPath.StartsWith($toolsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($approvedReportPath) -ne '.json') { throw 'ApprovedInputReport must be a local JSON report below .tools.' }
    $cursor = Get-Item -LiteralPath $approvedReportPath
    if ($cursor.PSIsContainer) { throw 'ApprovedInputReport must be a file.' }
    while ($cursor.FullName -ne $toolsRoot) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ApprovedInputReport may not traverse a link.' }
        $parentPath = Split-Path -Parent $cursor.FullName
        if ([string]::IsNullOrWhiteSpace($parentPath)) { throw 'ApprovedInputReport escaped .tools.' }
        $cursor = Get-Item -LiteralPath $parentPath
    }
    if ($approvedReportPath -eq (Join-Path $toolsRoot $ReportName)) { throw 'The output report must differ from the approved input report.' }
}
foreach ($requiredName in @('MAGIC_LIVE_API_URL','MAGIC_LIVE_MODEL','MAGIC_LIVE_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($requiredName,'Process'))) { throw "$requiredName must be supplied in the process environment." }
}
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
$paths = @{
    APPDATA = Join-Path $repo '.tools/live-people-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/live-people-localappdata'
    TEMP = Join-Path $repo '.tools/live-people-temp'
    TMP = Join-Path $repo '.tools/live-people-temp'
    MAGIC_LIVE_PEOPLE_REPORT = Join-Path $repo ".tools/$ReportName"
    MAGIC_LIVE_PEOPLE_WAIT = [string][Math]::Max(1,[Math]::Min(180,$GenerationWaitSeconds))
    MAGIC_LIVE_PEOPLE_TARGET = [string]$GenerationTarget
    MAGIC_LIVE_PEOPLE_APPROVED_INPUT = $approvedReportPath
}
$previous = @{}
foreach ($name in @($paths.Keys)+@('MAGIC_GATEWAY_URL','MAGIC_GATEWAY_TOKEN','MAGIC_AI_KEY')) { $previous[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
try {
    foreach ($name in @('APPDATA','LOCALAPPDATA','TEMP','TMP')) { New-Item -ItemType Directory -Force -Path $paths[$name] | Out-Null }
    foreach ($name in $paths.Keys) { [Environment]::SetEnvironmentVariable($name,$paths[$name],'Process') }
    foreach ($name in @('MAGIC_GATEWAY_URL','MAGIC_GATEWAY_TOKEN','MAGIC_AI_KEY')) { [Environment]::SetEnvironmentVariable($name,$null,'Process') }
    $ErrorActionPreference = 'Continue'
    & $engine --headless --path $repo --script res://tests/live/generated_people_live.gd
    $liveExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($liveExit -ne 0) { throw "Live generated-people evaluation exited $liveExit; inspect the incremental JSON report." }
} finally {
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name,$previous[$name],'Process') }
}
