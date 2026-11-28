param(
    [ValidateSet('B2','B1','B3','All')][string]$Stage = 'All',
    [switch]$SkipImport,
    [string[]]$Only = @(),
    [ValidateRange(10,1800)][int]$TargetTimeoutSeconds = 300
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
$runId = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + $PID
$evidence = Join-Path $repo ".tools/r4-b/runs/$runId"
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$environmentNames = @('APPDATA','LOCALAPPDATA','TEMP','TMP','PYTHONPATH','CONDA_DLL_SEARCH_MODIFICATION_ENABLE')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
$results = @()
function Invoke-BProcess([string]$Executable,[string[]]$TargetArguments,[string]$LogPath) {
    $stdoutPath = $LogPath + '.stdout'
    $stderrPath = $LogPath + '.stderr'
    # These arguments are fixed suite paths; quoting also supports a checkout
    # under a directory containing spaces. No shell or credential is passed.
    $quotedArguments = @($TargetArguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' })
    $process = Start-Process -FilePath $Executable -ArgumentList $quotedArguments -WorkingDirectory $repo -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    while (!$process.WaitForExit(1000)) {
        if ($watch.Elapsed.TotalSeconds -ge $TargetTimeoutSeconds) {
            $timedOut = $true
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
            break
        }
    }
    $process.Refresh()
    $code = if ($timedOut) { 124 } else { $process.ExitCode }
    if ($null -eq $code) { throw 'Native process exit status is unavailable.' }
    $stdout = [IO.File]::ReadAllText($stdoutPath)
    $stderr = [IO.File]::ReadAllText($stderrPath)
    [IO.File]::WriteAllText($LogPath,$stdout + "`n" + $stderr,[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{code=[int]$code;timed_out=$timedOut}
}
try {
    foreach ($entry in @{APPDATA='appdata';LOCALAPPDATA='localappdata';TEMP='temp';TMP='temp'}.GetEnumerator()) {
        $path = Join-Path $evidence $entry.Value
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        [Environment]::SetEnvironmentVariable($entry.Key,$path,'Process')
    }
    $dependencyPath = Join-Path $repo '.tools/r4-b/python'
    $pythonPaths = @($repo)
    if (Test-Path -LiteralPath $dependencyPath) { $pythonPaths += $dependencyPath }
    if ($savedEnvironment.PYTHONPATH) { $pythonPaths += $savedEnvironment.PYTHONPATH }
    $env:PYTHONPATH = $pythonPaths -join [IO.Path]::PathSeparator
    $env:CONDA_DLL_SEARCH_MODIFICATION_ENABLE = '1'
    if (!$SkipImport) {
        $importLog = Join-Path $evidence 'import.log'
        & $engine --headless --path $repo --import *> $importLog
        $importExit = $LASTEXITCODE
        $importText = Get-Content -LiteralPath $importLog -Raw
        if ($importExit -ne 0 -or $importText -match 'SCRIPT ERROR:|ERROR:') { throw "Godot import failed; see $importLog" }
    }
    foreach ($line in (Get-Content -LiteralPath (Join-Path $repo 'tests/suites/r4_art.txt'))) {
        $line = $line.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        $testStage, $relative, $testArgument = $line -split '\|',3
        if ($testStage -ne 'shared' -and $Stage -ne 'All' -and $testStage -ne $Stage) { continue }
        if ($Only.Count -gt 0 -and $relative -notin $Only) { continue }
        if (!$relative -or $relative.Contains('..') -or !(Test-Path -LiteralPath (Join-Path $repo $relative))) { throw "Invalid suite entry: $line" }
        if ($testArgument -and ($relative -ne 'tests/people/restart.gd' -or $testArgument -notin @('write','read'))) { throw "Unsupported test argument: $line" }
        $logName = $relative.Replace('/','-').Replace('\','-') + '.log'
        if ($testArgument) { $logName = $relative.Replace('/','-') + '-' + $testArgument + '.log' }
        $log = Join-Path $evidence $logName
        $started = [DateTime]::UtcNow
        if ($relative.EndsWith('.py')) {
            $outcome = Invoke-BProcess -Executable (Get-Command python).Source -TargetArguments @('-B',(Join-Path $repo $relative)) -LogPath $log
        } else {
            $arguments = @('--headless','--path',$repo,'--script',('res://' + $relative))
            if ($testArgument) { $arguments += @('--',$testArgument) }
            $outcome = Invoke-BProcess -Executable $engine -TargetArguments $arguments -LogPath $log
        }
        $code = $outcome.code
        $content = Get-Content -LiteralPath $log -Raw
        $passed = $code -eq 0 -and $content -notmatch 'SCRIPT ERROR:|ERROR:'
        $results += [pscustomobject]@{stage=$testStage;path=$relative;argument=$testArgument;exit_code=$code;passed=$passed;timed_out=$outcome.timed_out;seconds=([DateTime]::UtcNow-$started).TotalSeconds;log=$log}
        Write-Output ((@{path=$relative;passed=$passed;exit_code=$code} | ConvertTo-Json -Compress))
        # Continue through failures so known baseline failures cannot hide the
        # outcome of the B-specific targets. Exit remains nonzero if any fail.
    }
    $failed = @($results | Where-Object { !$_.passed }).Count
    if ($results.Count -eq 0) { throw 'No suite targets matched the requested stage and paths.' }
    [ordered]@{stage=$Stage;run_id=$runId;targets=$results.Count;failed_targets=$failed;results=$results} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $evidence 'summary.json') -Encoding UTF8
    Write-Output "R4-B targets=$($results.Count) failed=$failed evidence=$evidence"
    if ($failed -gt 0) { exit 1 }
} finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name,$savedEnvironment[$name],'Process') }
}
