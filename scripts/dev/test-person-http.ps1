param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
$paths = @{
    APPDATA = Join-Path $repo '.tools/test-person-http-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/test-person-http-localappdata'
    TEMP = Join-Path $repo '.tools/test-person-http-temp'
    TMP = Join-Path $repo '.tools/test-person-http-temp'
}
$previous = @{}
foreach ($key in $paths.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
try {
    foreach ($key in $paths.Keys) {
        New-Item -ItemType Directory -Force -Path $paths[$key] | Out-Null
        [Environment]::SetEnvironmentVariable($key,$paths[$key],'Process')
    }
    $ErrorActionPreference = 'Continue'
    & python (Join-Path $repo 'tests/http/person_jobs.py') --engine $engine
    $testExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($testExit -ne 0) { throw "Person HTTP tests failed (exit $testExit)." }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key,$previous[$key],'Process') }
}
