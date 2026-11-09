param([switch]$WithExportTemplates)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$toolsDir = Join-Path $repo '.tools'
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null
function Get-VerifiedFile($Url, $Target, $Hash) {
    if (!(Test-Path -LiteralPath $Target) -or (Get-FileHash -LiteralPath $Target -Algorithm SHA256).Hash -ne $Hash) {
        Invoke-WebRequest -Uri $Url -OutFile "$Target.download"
        if ((Get-FileHash -LiteralPath "$Target.download" -Algorithm SHA256).Hash -ne $Hash) { throw "SHA256 mismatch: $Url" }
        Move-Item -LiteralPath "$Target.download" -Destination $Target -Force
    }
}
Get-VerifiedFile $lock.engine_url (Join-Path $toolsDir 'godot.zip') $lock.engine_sha256
$engineDir = Join-Path $toolsDir 'godot'
$engine = Join-Path $engineDir "Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) {
    Expand-Archive -LiteralPath (Join-Path $toolsDir 'godot.zip') -DestinationPath $engineDir -Force
}
# Portable editor settings/cache remain inside the ignored tool directory.
New-Item -ItemType File -Force -Path (Join-Path $engineDir '_sc_') | Out-Null
if ($WithExportTemplates) {
    Get-VerifiedFile $lock.templates_url (Join-Path $toolsDir 'export_templates.tpz') $lock.templates_sha256
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $toolsDir 'export_templates.tpz'))
    try {
        $templateDir = Join-Path $toolsDir 'templates'
        New-Item -ItemType Directory -Force -Path $templateDir | Out-Null
        foreach ($name in @('windows_release_x86_64.exe', 'windows_debug_x86_64.exe')) {
            $entry = $archive.GetEntry("templates/$name")
            if (!$entry) { throw "Missing template: $name" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $templateDir $name), $true)
        }
    } finally { $archive.Dispose() }
}
$actual = & $engine --version
if ($actual -ne $lock.version_output) { throw "Unexpected engine: $actual" }
Write-Host "Ready: $engine ($actual)"
