param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
$paths = @{
    APPDATA = Join-Path $repo '.tools/test-people-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/test-people-localappdata'
    TEMP = Join-Path $repo '.tools/test-people-temp'
    TMP = Join-Path $repo '.tools/test-people-temp'
}
$previous = @{}
foreach ($key in $paths.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    foreach ($key in $paths.Keys) {
        New-Item -ItemType Directory -Force -Path $paths[$key] | Out-Null
        [Environment]::SetEnvironmentVariable($key, $paths[$key], 'Process')
    }
    function Test-Godot([string[]]$GodotArgs) {
        $output = & $engine @GodotArgs 2>&1
        $code = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|ERROR:').Count -gt 0) { throw "People test failed (exit $code)." }
    }
    if (!(Test-Path -LiteralPath (Join-Path $repo '.godot/imported'))) {
        Test-Godot @('--headless', '--path', $repo, '--import')
    }
    foreach ($name in @('rules', 'memory', 'family_flow', 'arrival_edges', 'feedback', 'distribution', 'director', 'panel', 'demo', 'b_handoff')) {
        Test-Godot @('--headless', '--path', $repo, '--script', "res://tests/people/$name.gd")
    }
    foreach ($mode in @('write', 'read')) {
        Test-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/restart.gd', '--', $mode)
    }
    $ErrorActionPreference = 'Continue'
    $pythonOutput = & python -m unittest discover -s (Join-Path $repo 'tests/people') -p test_gateway.py -v 2>&1
    $pythonCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $pythonOutput | ForEach-Object {
        $line = [string]$_
        if (![string]::IsNullOrWhiteSpace($line) -and $line -ne 'System.Management.Automation.RemoteException') { Write-Host $line }
    }
    if ($pythonCode -ne 0) { throw "Gateway tests failed (exit $pythonCode)." }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
