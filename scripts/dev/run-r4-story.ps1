$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$engine = Join-Path $repo '.tools/godot/Godot_v4.6.3-stable_win64_console.exe'
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
$targets = @('tests/story/round4_text.gd','tests/story/content.gd','tests/story/progress.gd','tests/integration/story_playthrough.gd')
$failed = @()
foreach ($target in $targets) {
  $ErrorActionPreference = 'Continue'
  try {
    $output = & $engine --headless --path $repo --script "res://$target" 2>&1
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = 'Stop' }
  $output | ForEach-Object { Write-Host $_ }
  if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|ERROR:').Count -gt 0) { $failed += $target }
}
if ($failed.Count -gt 0) { throw "Failed: $($failed -join ', ')" }
