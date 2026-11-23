param(
    [Parameter(Mandatory = $true)][string]$Style,
    [Parameter(Mandatory = $true)][string]$Only,
    [string]$Manifest = 'assets/ART_ASSET_MANIFEST.json',
    [string]$Output,
    [string]$ImportMap,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pipeline = Join-Path $PSScriptRoot 'art_pipeline.py'
$pipelineArguments = @($pipeline, '--workspace', $workspace, '--manifest', $Manifest,
    '--style', $Style, '--only', $Only)
if ($Output) { $pipelineArguments += @('--output', $Output) }
if ($ImportMap) { $pipelineArguments += @('--import-map', $ImportMap) }
& $Python @pipelineArguments
if ($LASTEXITCODE -ne 0) { throw "Art pipeline failed (exit $LASTEXITCODE)." }
# No API key, service, or CLI generator is called here. The receipt's queue
# must be executed using Codex's built-in imagegen in the active conversation.
# A compact schema-3 manifest resolves -Style v3 through style_profiles.v3.
# Missing reference/templates produces an explicit pending queue. With no
# -Output the Python adapter chooses a versioned local queue receipt; legacy
# manifests retain their original default receipt path.
# -Only past_fragments creates three fresh style-only native tasks and their
# runtime cover dependencies; it never edits the modern scene reference.
