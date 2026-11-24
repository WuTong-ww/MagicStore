param()
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 -WithWebExportTemplates first.' }
if (!(Test-Path -LiteralPath (Join-Path $repo '.tools/templates/web_nothreads_release.zip'))) { throw 'Run scripts/dev/bootstrap.ps1 -WithWebExportTemplates first.' }
if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
$outputDirectory = Join-Path $repo 'build/web'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
# Editor/export logs and caches stay in ignored workspace storage, not player saves.
$previous = @{}
$previousWebWorkspace = [Environment]::GetEnvironmentVariable('MAGIC_WEB_WORKSPACE', 'Process')
$presetPath = Join-Path $repo 'export_presets.cfg'
$presetOriginal = [IO.File]::ReadAllText($presetPath)
try {
    $extraFilters = & python (Join-Path $repo 'tools/web_export_resources.py') --workspace $repo
    if ($LASTEXITCODE -ne 0) { throw 'Could not derive the Web resource exclusion list.' }
    $webSection = $presetOriginal.IndexOf('[preset.1]')
    if ($webSection -lt 0) { throw 'Missing Web preset.' }
    $webPreset = $presetOriginal.Substring($webSection)
    $filterMatch = [regex]::Match($webPreset, 'exclude_filter="([^"]*)"')
    if (!$filterMatch.Success) { throw 'Missing Web exclusion filter.' }
    $updated = $webPreset.Remove($filterMatch.Index, $filterMatch.Length).Insert($filterMatch.Index, ('exclude_filter="' + $filterMatch.Groups[1].Value + ',' + $extraFilters + '"'))
    # Derived only for this export. Always restore tracked configuration below.
    [IO.File]::WriteAllText($presetPath, $presetOriginal.Substring(0, $webSection) + $updated, [Text.UTF8Encoding]::new($false))
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        $directory = Join-Path $repo ".tools/web-export-env/$name"
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
        [Environment]::SetEnvironmentVariable($name, $directory, 'Process')
    }
    foreach ($arguments in @(@('--headless', '--path', $repo, '--import'), @('--headless', '--path', $repo, '--export-release', 'Web Playtest', (Join-Path $outputDirectory 'index.html')))) {
        $output = & $engine @arguments 2>&1
        $code = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|ERROR:').Count -gt 0) { throw "Web export failed (exit $code)." }
    }
    foreach ($name in @('index.html','index.js','index.wasm','index.pck')) {
        if (!(Test-Path -LiteralPath (Join-Path $outputDirectory $name) -PathType Leaf)) { throw "Missing Web output: $name" }
    }
    # GitHub Pages must serve the Wasm/assets verbatim.
    [IO.File]::WriteAllText((Join-Path $outputDirectory '.nojekyll'), '')
    $licenseDirectory = Join-Path $outputDirectory 'licenses'
    New-Item -ItemType Directory -Force -Path $licenseDirectory | Out-Null
    foreach ($path in @('docs/GODOT-LICENSE.txt','docs/GODOT-COPYRIGHT.txt','docs/third-party.md','assets/fonts/OFL.txt','assets/fonts/LXGWWenKai-OFL.txt','assets/audio/KENNEY-LICENSE.txt')) {
        Copy-Item -LiteralPath (Join-Path $repo $path) -Destination $licenseDirectory -Force
    }
    $commit = (& git -C $repo rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $commit -notmatch '^[0-9a-f]{40}$') { throw 'Could not identify build source commit.' }
    $files = @('index.html','index.js','index.wasm','index.pck') | ForEach-Object {
        $path = Join-Path $outputDirectory $_
        [ordered]@{ path = $_; bytes = (Get-Item -LiteralPath $path).Length; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    }
    $buildInfo = [ordered]@{ version = 1; commit = $commit; engine = $lock.version_output; threads = $false; files = @($files) }
    $buildInfoJson = $buildInfo | ConvertTo-Json -Depth 5
    $check = $buildInfoJson | ConvertFrom-Json
    if ($check.version -ne 1 -or $check.files.Count -ne 4 -or $check.threads -ne $false) { throw 'Invalid build metadata.' }
    [IO.File]::WriteAllText((Join-Path $outputDirectory 'build-info.json'), $buildInfoJson, [Text.UTF8Encoding]::new($false))
    # Exercise the actual exported package with an isolated native engine before
    # publication. This is not a WebGL or browser-persistence test.
    $packSmokeRoot = Join-Path $repo '.tools/web-export-pack-root'
    New-Item -ItemType Directory -Force -Path $packSmokeRoot | Out-Null
    [Environment]::SetEnvironmentVariable('MAGIC_WEB_WORKSPACE', $repo, 'Process')
    $smokeOutput = & $engine --headless --path $packSmokeRoot --main-pack (Join-Path $outputDirectory 'index.pck') --script (Join-Path $repo 'tests/export/web_pack.gd') 2>&1
    $smokeExit = $LASTEXITCODE
    $smokeOutput | ForEach-Object { Write-Host $_ }
    if ($smokeExit -ne 0 -or ($smokeOutput -match 'SCRIPT ERROR:|ERROR:|WARNING:').Count -gt 0) { throw "Exported package smoke failed (exit $smokeExit)." }
    Write-Host "Web export ready: $outputDirectory"
} finally {
    [Environment]::SetEnvironmentVariable('MAGIC_WEB_WORKSPACE', $previousWebWorkspace, 'Process')
    [IO.File]::WriteAllText($presetPath, $presetOriginal, [Text.UTF8Encoding]::new($false))
    foreach ($name in $previous.Keys) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
}
