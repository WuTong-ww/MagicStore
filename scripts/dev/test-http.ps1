param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
$paths = @{
    APPDATA = Join-Path $repo '.tools/test-http-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/test-http-localappdata'
    TEMP = Join-Path $repo '.tools/test-http-temp'
    TMP = Join-Path $repo '.tools/test-http-temp'
}
$previous = @{}
foreach ($key in $paths.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    foreach ($key in $paths.Keys) {
        New-Item -ItemType Directory -Force -Path $paths[$key] | Out-Null
        [Environment]::SetEnvironmentVariable($key, $paths[$key], 'Process')
    }
    $ErrorActionPreference = 'Continue'
    $testOutput = & python (Join-Path $repo 'tests/http/fake_gateway.py') --engine $engine 2>&1
    $testExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $testOutput | ForEach-Object { Write-Host $_ }
    if ($testExit -ne 0) { throw "HTTP tests failed (exit $testExit)." }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
