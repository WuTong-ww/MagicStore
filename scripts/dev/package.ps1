param([switch]$WithEnvironment)
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 / .NET Framework 4.5+; no external zip utility needed.
# The source archive is an explicit allowlist, never a zip of the entire repo.
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$buildDir = Join-Path $repo 'build'
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Get-SafeSourceFiles([string]$Directory) {
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        # Never follow a junction/symlink into personal data outside the repo.
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if ($item.PSIsContainer) {
            if ($item.Name.StartsWith('.') -or $item.Name -in @('build', 'saves', 'test-runs', 'test-appdata', 'test-localappdata', 'editor_data', 'node_modules')) { continue }
            Get-SafeSourceFiles $item.FullName
        } else {
            $item
        }
    }
}

function Add-RequiredFile($Files, [string]$RelativePath) {
    $path = Join-Path $repo $RelativePath
    if (!(Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required package file missing: $RelativePath" }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Package file must not be a symlink: $RelativePath" }
    $Files.Add($item.FullName) | Out-Null
}

function Write-VerifiedZip([string]$Name, $Files) {
    # Both final and staging paths are explicitly inside this repo's build dir.
    $target = [IO.Path]::GetFullPath((Join-Path $buildDir $Name))
    $buildPrefix = [IO.Path]::GetFullPath($buildDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (!$target.StartsWith($buildPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Archive target escaped build directory.' }
    $temporary = "$target.partial"
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::Create, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $archive = $null
    $uniqueFiles = @($Files | Sort-Object -Unique)
    $prefix = $repo.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    try {
        $archive = New-Object System.IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create, $false, $utf8)
        foreach ($path in $uniqueFiles) {
            if (!$path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw "File outside repository: $path" }
            $entryName = $path.Substring($prefix.Length).Replace('\', '/')
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $path, $entryName, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
    } finally {
        if ($null -ne $archive) { $archive.Dispose() } else { $stream.Dispose() }
    }
    # Inspect the completed central directory before replacing any existing zip.
    $verify = [IO.Compression.ZipFile]::OpenRead($temporary)
    try {
        if ($verify.Entries.Count -ne $uniqueFiles.Count) { throw 'Archive entry count mismatch.' }
        foreach ($entry in $verify.Entries) {
            if ($entry.FullName.StartsWith('/') -or $entry.FullName.Contains('../') -or $entry.FullName.Contains('\')) { throw "Unsafe zip entry: $($entry.FullName)" }
        }
    } finally { $verify.Dispose() }
    Move-Item -LiteralPath $temporary -Destination $target -Force
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    Write-Host ("Created {0} ({1} files, {2:N1} MiB)" -f $target, $uniqueFiles.Count, ((Get-Item -LiteralPath $target).Length / 1MB))
    Write-Host "SHA256 $hash"
}

$sourceFiles = New-Object 'System.Collections.Generic.List[string]'
foreach ($required in @('project.godot', 'export_presets.cfg', '.gitignore', '.gitattributes', 'README.md', 'start-game.cmd', 'start-editor.cmd', 'scripts/dev/toolchain.json', 'scripts/dev/package.ps1')) {
    Add-RequiredFile $sourceFiles $required
}
$sourceRules = [ordered]@{
    'scenes' = @('.tscn', '.uid')
    'scripts' = @('.gd', '.uid', '.ps1', '.json')
    'data' = @('.json')
    'assets' = @('.svg', '.png', '.jpg', '.jpeg', '.webp', '.ttf', '.otf', '.txt', '.md', '.import', '.uid')
    'themes' = @('.tres', '.uid')
    'tests' = @('.gd', '.uid', '.tscn')
    'docs' = @('.md', '.txt')
}
foreach ($directory in $sourceRules.Keys) {
    $folder = Join-Path $repo $directory
    if (!(Test-Path -LiteralPath $folder -PathType Container)) { throw "Source directory missing: $directory" }
    foreach ($file in Get-SafeSourceFiles $folder) {
        if ($file.Extension.ToLowerInvariant() -in $sourceRules[$directory] -or $file.Name -eq '.gdignore') {
            if ($file.Name -match '(?i)(^\.env|credentials|secrets|\.tmp$|\.bak$)') { continue }
            $sourceFiles.Add($file.FullName) | Out-Null
        }
    }
}
Write-VerifiedZip 'MagicStore-source.zip' $sourceFiles

if ($WithEnvironment) {
    $lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
    $environmentFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($relative in @(
        ".tools/godot/Godot_v$($lock.version)-stable_win64.exe",
        ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe",
        '.tools/godot/_sc_',
        '.tools/templates/windows_release_x86_64.exe',
        '.tools/templates/windows_debug_x86_64.exe',
        'scripts/dev/toolchain.json',
        'scripts/dev/bootstrap.ps1',
        'scripts/dev/run.ps1',
        'scripts/dev/play-export.ps1',
        'scripts/dev/package.ps1',
        'start-game.cmd',
        'start-editor.cmd',
        'docs/third-party.md',
        'docs/GODOT-LICENSE.txt',
        'docs/GODOT-COPYRIGHT.txt',
        'assets/fonts/OFL.txt'
    )) {
        Add-RequiredFile $environmentFiles $relative
    }
    Write-VerifiedZip 'MagicStore-environment-win64.zip' $environmentFiles
    Write-Host 'Extract the source and environment zips into the same folder. Personal editor data and saves are excluded.'
}
