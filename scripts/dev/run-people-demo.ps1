$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
$paths = @{
    APPDATA = Join-Path $repo '.tools/demo-people-appdata'
    LOCALAPPDATA = Join-Path $repo '.tools/demo-people-localappdata'
    TEMP = Join-Path $repo '.tools/demo-people-temp'
    TMP = Join-Path $repo '.tools/demo-people-temp'
}
$previous = @{}
foreach ($key in $paths.Keys) { $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
try {
    foreach ($key in $paths.Keys) {
        New-Item -ItemType Directory -Force -Path $paths[$key] | Out-Null
        [Environment]::SetEnvironmentVariable($key, $paths[$key], 'Process')
    }
    if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
    if (!(Test-Path -LiteralPath (Join-Path $repo '.godot/imported'))) {
        & $engine --headless --path $repo --import
        if ($LASTEXITCODE -ne 0) { throw "People demo import failed (exit $LASTEXITCODE)." }
    }
    & $engine --path $repo res://scenes/people/people_demo.tscn
    if ($LASTEXITCODE -ne 0) { throw "People demo failed (exit $LASTEXITCODE)." }
} finally {
    foreach ($key in $previous.Keys) { [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process') }
}
