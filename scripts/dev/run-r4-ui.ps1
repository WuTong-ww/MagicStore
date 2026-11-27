param([switch]$Graphical)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = Join-Path $repo '.tools/godot/Godot_v4.6.3-stable_win64_console.exe'
$env:APPDATA = Join-Path $repo '.tools/r4-test-appdata'
New-Item -ItemType Directory -Force -Path $env:APPDATA | Out-Null
$suite = Get-Content -LiteralPath (Join-Path $repo 'tests/suites/r4_ui.txt')
foreach ($test in $suite) {
    if ([string]::IsNullOrWhiteSpace($test) -or $test.StartsWith('#')) { continue }
    $arguments = @('--path', $repo, '--script', $test)
    if (!$Graphical) { $arguments = @('--headless') + $arguments }
    $ErrorActionPreference = 'Continue'
    $output = & $engine @arguments 2>&1
    $ErrorActionPreference = 'Stop'
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|ERROR:').Count -gt 0) { throw "R4 UI suite failed: $test ($code)" }
}
