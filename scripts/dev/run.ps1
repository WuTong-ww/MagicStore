param([switch]$Editor, [switch]$Test, [switch]$Export, [switch]$WithMusic, [string[]]$GameArgs = @())
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$exportStageBase = [IO.Path]::GetTempPath()
if ($WithMusic -and !$Export) { throw '-WithMusic requires -Export.' }
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'toolchain.json') -Raw | ConvertFrom-Json
$engine = Join-Path $repo ".tools/godot/Godot_v$($lock.version)-stable_win64_console.exe"
if (!(Test-Path -LiteralPath $engine)) { throw 'Run scripts/dev/bootstrap.ps1 first.' }
function Invoke-Godot([string[]]$GodotArgs) {
    $output = & $engine @GodotArgs 2>&1
    $code = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($code -ne 0 -or ($output -match 'SCRIPT ERROR:|ERROR:').Count -gt 0) { throw "Godot validation failed (exit $code)." }
}
function Test-OptionalLocalArt([string]$RelativeConfig) {
    $metadata = Get-Content -LiteralPath (Join-Path $repo $RelativeConfig) -Raw -Encoding UTF8 | ConvertFrom-Json
    if (!($metadata.PSObject.Properties.Name -contains 'local_audit_descriptor')) { return $true }
    if (!($metadata.local_audit_descriptor -is [string])) { throw 'Local art audit descriptor must be a relative path.' }
    $auditOutput = & python -B (Join-Path $repo 'tools/art/local_audit.py') --workspace $repo --descriptor $metadata.local_audit_descriptor
    if ($LASTEXITCODE -ne 0) { throw 'Optional art audit metadata is corrupt; it cannot be treated as a skip.' }
    $audit = ($auditOutput -join "`n") | ConvertFrom-Json
    if ($audit.status -in @('retired', 'skipped')) {
        Write-Host "SKIP LOCAL ART: $RelativeConfig / $($audit.code); no archived image acceptance claimed."
        return $false
    }
    return $true
}
# Redirect only this process and its children; never change machine/user settings.
# Godot still uses user://. Its Windows APPDATA parent is now on the project drive.
$savedEnvironment = @{}
$savedCondaDllSearch = [Environment]::GetEnvironmentVariable('CONDA_DLL_SEARCH_MODIFICATION_ENABLE', 'Process')
$runtimePaths = @{
    APPDATA = Join-Path $repo '.runtime/appdata'
    LOCALAPPDATA = Join-Path $repo '.runtime/localappdata'
    TEMP = Join-Path $repo '.runtime/temp'
    TMP = Join-Path $repo '.runtime/temp'
}
if ($Test) {
    $runtimePaths.APPDATA = Join-Path $repo '.tools/test-appdata'
    $runtimePaths.LOCALAPPDATA = Join-Path $repo '.tools/test-localappdata'
    $runtimePaths.TEMP = Join-Path $repo '.tools/test-temp'
    $runtimePaths.TMP = $runtimePaths.TEMP
}
foreach ($name in $runtimePaths.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
try {
    if ($Test) {
        # Conda Python on Windows needs its bundled OpenSSL DLL search enabled.
        # This affects this test process and its children only.
        [Environment]::SetEnvironmentVariable('CONDA_DLL_SEARCH_MODIFICATION_ENABLE', '1', 'Process')
    }
    foreach ($name in $runtimePaths.Keys) {
        New-Item -ItemType Directory -Force -Path $runtimePaths[$name] | Out-Null
        [Environment]::SetEnvironmentVariable($name, $runtimePaths[$name], 'Process')
    }
    if ((& $engine --version) -ne $lock.version_output) { throw 'Engine version differs from toolchain.json.' }
    # Fresh source ZIPs do not include Godot's generated .godot/imported cache.
    # Import once before launching the runtime/editor so FontFile and PNG resources exist.
    $fontImportDir = Join-Path $repo '.godot/imported'
    $fontImportExists = $false
    if (Test-Path -LiteralPath $fontImportDir) {
        $fontImportExists = [bool](Get-ChildItem -LiteralPath $fontImportDir -Filter 'NotoSansSC*.fontdata' -ErrorAction SilentlyContinue | Select-Object -First 1)
    }
    if (!$fontImportExists -and !$Test) {
        Invoke-Godot @('--headless', '--path', $repo, '--import')
    }
    if ($Test) {
        Invoke-Godot @('--headless', '--path', $repo, '--import')
        & python (Join-Path $repo 'tests/web/build_policy.py')
        if ($LASTEXITCODE -ne 0) { throw 'Pages channel-preservation checks failed.' }
        & node (Join-Path $repo 'tests/web/wheel_focus.cjs')
        if ($LASTEXITCODE -ne 0) { throw 'Web wheel focus checks failed.' }
        foreach ($learningTarget in @('tests/learning/content.gd','tests/learning/transactions.gd','tests/learning/migration.gd')) {
            Invoke-Godot @('--headless', '--path', $repo, '--script', "res://$learningTarget")
        }
        foreach ($craftTarget in @('tests/shop/crafting.gd','tests/integration/craft_migration.gd')) {
            Invoke-Godot @('--headless', '--path', $repo, '--script', "res://$craftTarget")
        }
        # The shared schema16 boundary is verified once with the full suite.
        foreach ($personTarget in @('tests/people/nationality.gd','tests/people/face_details.gd','tests/integration/person_details_migration.gd')) {
            Invoke-Godot @('--headless', '--path', $repo, '--script', "res://$personTarget")
        }
        # MUSIC uses synthetic voices; licensed local Ogg checks require explicit opt-in.
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/audio/music_catalog.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/music_runtime.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/music_host.gd')
        # POLISH presentation contracts share the normal save/action boundaries.
        foreach ($polishTarget in @(
            'tests/audio/music_sheep.gd',
            'tests/people/portrait_clipping.gd',
            'tests/integration/polish_style_config.gd',
            'tests/integration/polish_style.gd',
            'tests/integration/polish_font_arrays.gd',
            'tests/integration/polish_icon_contract.gd',
            'tests/integration/polish_button_materials.gd',
            'tests/integration/polish_card_choice.gd',
            'tests/integration/polish_layout.gd',
            'tests/integration/polish_windows.gd',
            'tests/integration/polish_wheel.gd',
            'tests/integration/web_drawer_input.gd',
            'tests/integration/polish_header.gd',
            'tests/integration/polish_panel_materials.gd',
            'tests/integration/polish_motion_lifecycle.gd',
            'tests/integration/polish_notebook_pages.gd',
            'tests/integration/polish_surface_consumers.gd',
            'tests/integration/polish_case_materials.gd'
        )) {
            Invoke-Godot @('--headless', '--path', $repo, '--script', ('res://' + $polishTarget))
        }
        & python -B (Join-Path $repo 'tools/check_font_coverage.py') --check --report (Join-Path $repo '.tools/font-coverage.json')
        if ($LASTEXITCODE -ne 0) { throw 'Bundled font coverage validation failed.' }
        & python -B (Join-Path $repo 'tools/check_portrait_clipping.py') --report (Join-Path $repo '.tools/portrait-clipping.json')
        if ($LASTEXITCODE -ne 0) { throw 'Portrait clipping validation failed.' }
        # TITLE runs first; each invocation gets new local evidence and restart identity.
        $titleRunId = 'title_full_' + [Guid]::NewGuid().ToString('N')
        $titleLogDir = Join-Path $repo (".tools/r3-title/full-runs/" + $titleRunId)
        $titleSaveRoot = "res://.tools/r3-title/full-saves/" + $titleRunId
        New-Item -ItemType Directory -Path $titleLogDir -ErrorAction Stop | Out-Null
        Write-Host "TITLE_FULL_RUN_ID $titleRunId"
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'creation.native.log'), '--script', 'res://tests/integration/title_creation.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'migration.native.log'), '--script', 'res://tests/integration/title_creation_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'ownership.native.log'), '--script', 'res://tests/integration/title_creation_ownership.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'restart-seed.native.log'), '--script', 'res://tests/integration/title_creation_restart.gd', '--', '--seed', $titleRunId)
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'restart-replay.native.log'), '--script', 'res://tests/integration/title_creation_restart.gd', '--', '--replay', $titleRunId)
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'geometry.native.log'), '--script', 'res://tests/integration/title_geometry.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'entry-audio.native.log'), '--script', 'res://tests/integration/title_entry_audio.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'presence.native.log'), '--script', 'res://tests/integration/title_presence.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'ui.native.log'), '--script', 'res://tests/integration/title_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-empty-missing.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--case=missing', "--save-dir=$titleSaveRoot/invalid-empty-missing")
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-empty-syntax.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--case=syntax', "--save-dir=$titleSaveRoot/invalid-empty-syntax")
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-empty-field.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--case=field', "--save-dir=$titleSaveRoot/invalid-empty-field")
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-prepare-existing.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--prepare-existing', "--save-dir=$titleSaveRoot/invalid-existing")
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-existing-missing.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--case=missing', "--existing-receipt=$titleSaveRoot/invalid-existing.receipt.json")
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-existing-syntax.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--case=syntax', "--existing-receipt=$titleSaveRoot/invalid-existing.receipt.json")
        Invoke-Godot @('--headless', '--path', $repo, '--log-file', (Join-Path $titleLogDir 'invalid-existing-field.native.log'), '--script', 'res://tests/integration/title_invalid_config.gd', '--', '--case=field', "--existing-receipt=$titleSaveRoot/invalid-existing.receipt.json")
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/emergent_case_kernel_v1.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/full_definition_codec_v1.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_case_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_model_admission.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_saved_shapes.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_schema13_target.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_catalog_target.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_template_history_target.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/providers/emergent_request_privacy.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_mode_recovery.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/providers/emergent_transport.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/emergent_case_routes.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/case_schema.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/deduction_board.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/case_host.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/case_deadline.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/case_save_bad_rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/case_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/case_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/case_board_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/story/content.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/story/progress.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_playthrough.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_return_backlog.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_followup_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/story_board_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/lin_appearance.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/lin_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/lin_legacy.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/lin_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/birth_identity.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/names_ordinary.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/names_protocol.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/names_provider.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/names_copy.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/names_catalog.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/names_dialogue.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/names_birth_failures.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/names_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/names_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/names_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/smoke.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/daily_loop.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/daily_loop_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/daily_loop_guards.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/save_delete.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/provider_contract.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/dialogue/grounding.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/dialogue/followup_questions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/oracle_rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/acceptance.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/legacy_guests.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/generated_cases.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/event_golden.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/invitation_feedback_golden.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/event_data_rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/event_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/event_workflows.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/divination/g4_components.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/generic_effects.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/event_effects.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/invitation_referral.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/event_notebook_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/ui_capture.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/restart.gd', '--', 'write')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/restart.gd', '--', 'read')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/integration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/content_rules.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/economic_validation.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/ordinary_content.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/ordinary_population.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_content_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_content_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/traffic_activation.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_component_feedback.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_content_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_content_capture.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/people_bridge.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/people_restart.gd', '--', 'write')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/people_restart.gd', '--', 'read')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shop_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/daily_loop_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/item_visuals.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/shop/shelf_layout.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/shelf_render.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/presentation/wind_and_spring.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/presentation/committed_events.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/scene_motion.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/motion_settings.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/motion_performance.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/motion_preview.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/appearance.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/appearance_birth.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/appearance_description.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/appearance_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/appearance_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/portrait_preview.gd', '--', '--schema-only')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/dialogue/mood.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/family_library.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/family_arrival_budget.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/family_library_flow.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/family_library_distribution.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/family_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/family_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/family_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/past_lives/library.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/past_lives_migration.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/past_lives_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/past_lives_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/past_lives_capture.gd', '--', '--schema-only')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/people/style_report.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/style_report_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/style_report_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/style_report_capture.gd', '--', '--schema-only')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/dialogue/family_policy.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/scene_visuals.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/aligned_scene_layers.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/scene_asset_acceptance.gd')
        foreach ($localPreview in @('data/art/scene_preview.json', 'data/art/scene_review.json')) {
            if (Test-OptionalLocalArt $localPreview) {
                Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/scene_asset_acceptance.gd', '--', '--config', "res://$localPreview")
            }
        }
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/arrival_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/consultation_layout.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/round2_shell.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/round2_shell_edges.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/round2_consultation.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/round2_audio_theme.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/audio_lifecycle.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/arrival_transactions.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/save_delete_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/generated_people.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/generation_arrival_slots.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/generated_people_ui.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/followup_questions.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/followup_questions_ui.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/chat_keyboard_ui.gd')
        Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/opening_guests.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/project_cleanup.gd')
		Invoke-Godot @('--headless', '--path', $repo, '--script', 'res://tests/integration/api_settings_ui.gd')
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-http.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'HTTP integration tests failed.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-person-http.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'Background person HTTP tests failed.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'test-people.ps1')
        if ($LASTEXITCODE -ne 0) { throw 'People regression tests failed.' }
        $artErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $artTestOutput = & python -m unittest discover -s (Join-Path $repo 'tests/art') -p 'test_*.py' -v 2>&1
        $artTestCode = $LASTEXITCODE
        $ErrorActionPreference = $artErrorPreference
        $artTestOutput | ForEach-Object {
            $line = [string]$_
            if (![string]::IsNullOrWhiteSpace($line) -and $line -ne 'System.Management.Automation.RemoteException') { Write-Host $line }
        }
        if ($artTestCode -ne 0) { throw 'Art pipeline regression tests failed.' }
        & python -B (Join-Path $repo 'tools/art/validate_formal_manifest.py') --workspace $repo
        if ($LASTEXITCODE -ne 0) { throw 'Formal art manifest validation failed.' }
        & python -B (Join-Path $repo 'tools/check_alpha.py') --workspace $repo --visuals 'data/shop/visuals.json'
        if ($LASTEXITCODE -ne 0) { throw 'Production item alpha validation failed.' }
        if (Test-OptionalLocalArt 'data/art/real_scene_registry.json') {
            & python -B (Join-Path $repo 'tools/art/register_real_scenes.py') --validate-only
            if ($LASTEXITCODE -ne 0) { throw 'Retained real scene data validation failed.' }
        }
    } elseif ($Export) {
        # Build from a fresh input tree. Default packages never contain local music.
        $stageDir = Join-Path $exportStageBase ('MagicStore-export-' + [Guid]::NewGuid().ToString('N'))
        $stageArgs = @('-B', (Join-Path $repo 'tools/music_build.py'), '--stage-from', $repo, '--stage-to', $stageDir)
        if ($WithMusic) { $stageArgs += '--with-music' }
        $stageJson = & python @stageArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host ($stageJson -join "`n")
            throw 'Isolated export staging failed.'
        }
        $stageReport = ($stageJson -join "`n") | ConvertFrom-Json
        if ($stageReport.status -ne 'complete') { throw 'Isolated export staging did not complete.' }
        $stagePreset = Join-Path $stageDir 'export_presets.cfg'
        $presetText = [IO.File]::ReadAllText($stagePreset)
        foreach ($template in @('windows_debug_x86_64.exe', 'windows_release_x86_64.exe')) {
            $templatePath = Join-Path $repo ('.tools/templates/' + $template)
            if (!(Test-Path -LiteralPath $templatePath)) { throw 'Run scripts/dev/bootstrap.ps1 -WithExportTemplates first.' }
            $presetText = $presetText.Replace('res://.tools/templates/' + $template, $templatePath.Replace('\', '/'))
        }
        [IO.File]::WriteAllText($stagePreset, $presetText, (New-Object Text.UTF8Encoding($false)))
        Invoke-Godot @('--headless', '--path', $stageDir, '--import')
        $outDir = Join-Path $repo 'build/windows'
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Invoke-Godot @('--headless', '--path', $stageDir, '--export-release', 'Windows Desktop', (Join-Path $outDir 'ZeroHourStore.exe'))
        [IO.File]::WriteAllText((Join-Path $outDir 'music-stage-receipt.json'), ($stageJson -join "`n"), (New-Object Text.UTF8Encoding($false)))
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'play-export.ps1') -Destination (Join-Path $outDir 'play-export.ps1') -Force
        $licenseDir = Join-Path $outDir 'licenses'
        New-Item -ItemType Directory -Force -Path $licenseDir | Out-Null
        foreach ($licenseFile in @('docs/GODOT-LICENSE.txt', 'docs/GODOT-COPYRIGHT.txt', 'docs/third-party.md', 'assets/fonts/OFL.txt')) {
            Copy-Item -LiteralPath (Join-Path $repo $licenseFile) -Destination $licenseDir -Force
        }
        @'
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0play-export.ps1"
if errorlevel 1 pause
'@ | Set-Content -LiteralPath (Join-Path $outDir 'StartGame.cmd') -Encoding ASCII
        Write-Host "Portable game entry: $(Join-Path $outDir 'StartGame.cmd')"
    } elseif ($Editor) {
        & $engine --path $repo --editor @GameArgs
        if ($LASTEXITCODE -ne 0) { throw "Godot editor failed (exit $LASTEXITCODE)." }
    } else {
        & $engine --path $repo @GameArgs
        if ($LASTEXITCODE -ne 0) { throw "Godot game failed (exit $LASTEXITCODE)." }
    }
} finally {
    [Environment]::SetEnvironmentVariable('CONDA_DLL_SEARCH_MODIFICATION_ENABLE', $savedCondaDllSearch, 'Process')
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
}
