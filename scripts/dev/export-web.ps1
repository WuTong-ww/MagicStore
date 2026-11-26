param([ValidateSet('preview','main')][string]$Variant='preview',[switch]$Baseline,[switch]$WithMusic,[ValidatePattern('^[a-z0-9-]*$')][string]$Attempt='')
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$arguments=@((Join-Path $repo 'tools/web_build.py'),'--variant',$Variant)
if ($Baseline) { $arguments+='--baseline' }
if ($WithMusic) { $arguments+='--with-music' }
if ($Attempt) { $arguments+=@('--attempt',$Attempt) }
Push-Location $repo
try { & python @arguments; if ($LASTEXITCODE -ne 0) { throw 'Web build failed; see isolated build logs.' } }
finally { Pop-Location }
