param(
    [Parameter(Mandatory = $true)][string]$Style,
    [Parameter(Mandatory = $true)][string]$Only,
    [string]$Manifest = 'assets/ART_ASSET_MANIFEST.json',
    [string]$Output = '.tools/art/regen_receipt.json',
    [string]$ImportMap,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipeline = Join-Path $PSScriptRoot 'art_pipeline.py'
$pipelineArguments = @($pipeline, '--workspace', $workspace, '--manifest', $Manifest,
    '--style', $Style, '--only', $Only, '--output', $Output)
if ($ImportMap) { $pipelineArguments += @('--import-map', $ImportMap) }
& $Python @pipelineArguments
if ($LASTEXITCODE -ne 0) { throw "Art pipeline failed (exit $LASTEXITCODE)." }
# No API key, service, or CLI generator is called here. The receipt's queue
# must be executed using Codex's built-in imagegen in the active conversation.
