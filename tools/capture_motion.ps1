param([string]$Mode = '', [switch]$All, [switch]$Reduced, [switch]$SkipRecording)
$ErrorActionPreference = 'Stop'
$movieRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$movieValidationPath = Join-Path $movieRepo 'data/art/motion_validation.json'
$movieValidation = Get-Content -LiteralPath $movieValidationPath -Raw -Encoding UTF8 | ConvertFrom-Json
$movieSettings = $movieValidation.movie
$movieEffectiveReduced = [bool]$Reduced -or [bool]$movieSettings.reduced_motion
if ($movieValidation.version -ne 1 -or $null -eq $movieSettings -or $movieSettings.fps -le 0 -or $movieSettings.frame_count -ne $movieSettings.fps * $movieSettings.duration_seconds) {
    throw 'Invalid movie validation data; frame count must equal FPS times duration.'
}
if ($movieSettings.action_frame -le 0 -or $movieSettings.action_frame -ge $movieSettings.frame_count) { throw 'Movie action frame must be inside the recording.' }
$movieWriterOffset = $movieSettings.writer_frame_offset
if ($null -eq $movieWriterOffset -or $movieWriterOffset -is [bool] -or $movieWriterOffset -is [string] -or [double]::IsNaN([double]$movieWriterOffset) -or [double]::IsInfinity([double]$movieWriterOffset) -or $movieWriterOffset -lt 0 -or [Math]::Floor([double]$movieWriterOffset) -ne $movieWriterOffset -or $movieWriterOffset -ge $movieSettings.frame_count) {
    throw 'Movie Writer/post-draw offset must be a finite nonnegative integer below the Writer frame count.'
}
$movieExpectedCallbacks = [int]$movieSettings.frame_count - [int]$movieWriterOffset
if ($movieSettings.action_frame -ge $movieExpectedCallbacks) { throw 'Movie action must occur before the final observed post-draw callback.' }
if ($movieValidation.window.width -le 0 -or $movieValidation.window.height -le 0) { throw 'Movie window dimensions must be positive.' }

function Assert-MovieProjectProfile([string]$ProjectPath, [int]$Width, [int]$Height) {
    # MovieWriter selects the initial viewport before the script can resize it.
    # A command-line resolution alone can still produce the normal game profile.
    $movieExpectedProfile = @{
        'window/size/viewport_width.movie' = $Width
        'window/size/viewport_height.movie' = $Height
        'window/size/window_width_override.movie' = $Width
        'window/size/window_height_override.movie' = $Height
    }
    $movieActualProfile = @{}
    $movieProjectSection = ''
    foreach ($movieProjectLine in (Get-Content -LiteralPath $ProjectPath -Encoding UTF8)) {
        if ($movieProjectLine -match '^\[([^\]]+)\]\s*$') {
            $movieProjectSection = $Matches[1]
        } elseif ($movieProjectSection -eq 'display' -and $movieProjectLine -match '^([^=]+)=(.+)$') {
            $movieProfileKey = $Matches[1].Trim()
            if ($movieExpectedProfile.ContainsKey($movieProfileKey)) { $movieActualProfile[$movieProfileKey] = $Matches[2].Trim() }
        }
    }
    foreach ($movieProfileKey in $movieExpectedProfile.Keys) {
        if (!$movieActualProfile.ContainsKey($movieProfileKey) -or $movieActualProfile[$movieProfileKey] -notmatch '^\d+$' -or [int]$movieActualProfile[$movieProfileKey] -ne $movieExpectedProfile[$movieProfileKey]) {
            throw "Movie project profile $movieProfileKey must match validation JSON value $($movieExpectedProfile[$movieProfileKey]); command-line resolution is insufficient."
        }
    }
}

if (!$SkipRecording) { Assert-MovieProjectProfile (Join-Path $movieRepo 'project.godot') ([int]$movieValidation.window.width) ([int]$movieValidation.window.height) }
if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = [string]$movieSettings.default_mode }
if ($All -and $PSBoundParameters.ContainsKey('Mode')) { throw 'Choose -All or -Mode, not both.' }
$movieModes = @($movieSettings.modes.PSObject.Properties.Name)
$movieSelectedModes = $movieModes | Where-Object { $All -or $_ -eq $Mode }
if (@($movieSelectedModes).Count -eq 0) { throw 'Requested movie mode is absent from the validated data.' }

function Get-MovieChildPath([string]$RelativePath) {
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains(':') -or $RelativePath.Contains('\') -or @($RelativePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count -gt 0) {
        throw 'Movie paths must be clean repository-relative paths.'
    }
    $resolvedMoviePath = [IO.Path]::GetFullPath((Join-Path $movieRepo $RelativePath))
    $movieRepoPrefix = $movieRepo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (!$resolvedMoviePath.StartsWith($movieRepoPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Movie path escaped the repository.' }
    return $resolvedMoviePath
}

$movieRawDirectory = Get-MovieChildPath ([string]$movieSettings.capture_directory)
$moviePublicDirectory = Get-MovieChildPath ([string]$movieSettings.compressed_directory)
if (!([string]$movieSettings.capture_directory).StartsWith('.tools/art/a6/') -or !([string]$movieSettings.compressed_directory).StartsWith('docs/screenshots/')) {
    throw 'Raw/intermediate movies stay under .tools/art/a6; only compressed copies may enter docs/screenshots.'
}
New-Item -ItemType Directory -Force -Path $movieRawDirectory | Out-Null

function Find-MovieEncoder {
    $movieCommand = Get-Command ffmpeg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $movieCommand) { return $movieCommand.Source }
    foreach ($movieSearchRoot in @((Join-Path $movieRepo '.tools'),'D:/tools')) {
        if (Test-Path -LiteralPath $movieSearchRoot) {
            $movieFound = Get-ChildItem -LiteralPath $movieSearchRoot -Recurse -File -Filter '*ffmpeg*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $movieFound) { return $movieFound.FullName }
        }
    }
    $movieRg = Get-Command rg -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $movieRg -and (Test-Path -LiteralPath 'D:/Downlode')) {
        # Explicitly authorized existing tool root; do not scan the whole C drive.
        $movieScanPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $movieKnownPaths = @(& $movieRg.Source --files --hidden -g '*ffmpeg*.exe' 'D:/Downlode' 2>$null)
        } finally { $ErrorActionPreference = $movieScanPreference }
        $movieKnown = $movieKnownPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if ($null -ne $movieKnown) { return [string]$movieKnown }
    }
    $movieWingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages'
    if (Test-Path -LiteralPath $movieWingetRoot) {
        foreach ($moviePackage in @(Get-ChildItem -LiteralPath $movieWingetRoot -Directory -Filter '*FFmpeg*' -ErrorAction SilentlyContinue)) {
            $movieFound = Get-ChildItem -LiteralPath $moviePackage.FullName -Recurse -File -Filter '*ffmpeg*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $movieFound) { return $movieFound.FullName }
        }
    }
    # Reuse a bundled binary from an already-installed package only. This does
    # not import the package, call a downloader, install a module or use a fee.
    $moviePython = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $moviePython) {
        $moviePythonBinaries = Join-Path (Split-Path $moviePython.Source -Parent) 'Lib/site-packages/imageio_ffmpeg/binaries'
        if (Test-Path -LiteralPath $moviePythonBinaries) {
            $movieFound = Get-ChildItem -LiteralPath $moviePythonBinaries -File -Filter '*ffmpeg*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $movieFound) { return $movieFound.FullName }
        }
    }
    return $null
}

function Read-MovieAviHeader([string]$Path) {
    $movieStream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $movieReadLength = [int][Math]::Min($movieStream.Length,[int]$movieSettings.avi_header_probe_bytes)
        $movieHeader = New-Object byte[] $movieReadLength
        if ($movieStream.Read($movieHeader,0,$movieReadLength) -ne $movieReadLength) { throw 'Cannot read the complete AVI header.' }
    } finally { $movieStream.Dispose() }
    $movieHeaderText = [Text.Encoding]::ASCII.GetString($movieHeader)
    if (!$movieHeaderText.StartsWith('RIFF') -or $movieHeaderText.Substring(8,4) -ne 'AVI ') { throw 'Movie Writer output is not a RIFF AVI.' }
    $movieMainOffset = $movieHeaderText.IndexOf('avih',[StringComparison]::Ordinal)
    if ($movieMainOffset -lt 0 -or $movieMainOffset + 48 -gt $movieHeader.Length) { throw 'AVI main header is absent.' }
    $movieFrames = [BitConverter]::ToUInt32($movieHeader,$movieMainOffset+24)
    $movieWidth = [BitConverter]::ToUInt32($movieHeader,$movieMainOffset+40)
    $movieHeight = [BitConverter]::ToUInt32($movieHeader,$movieMainOffset+44)
    $movieVideoOffset = -1
    $movieSearchOffset = 0
    while ($movieSearchOffset -lt $movieHeaderText.Length) {
        $movieStreamOffset = $movieHeaderText.IndexOf('strh',$movieSearchOffset,[StringComparison]::Ordinal)
        if ($movieStreamOffset -lt 0) { break }
        if ($movieStreamOffset+44 -le $movieHeader.Length -and $movieHeaderText.Substring($movieStreamOffset+8,4) -eq 'vids') { $movieVideoOffset = $movieStreamOffset; break }
        $movieSearchOffset = $movieStreamOffset+4
    }
    if ($movieVideoOffset -lt 0) { throw 'AVI video stream header is absent.' }
    $movieScale = [BitConverter]::ToUInt32($movieHeader,$movieVideoOffset+28)
    $movieRate = [BitConverter]::ToUInt32($movieHeader,$movieVideoOffset+32)
    if ($movieScale -eq 0 -or $movieRate -eq 0) { throw 'AVI video frame rate is invalid.' }
    $movieActualFps = [double]$movieRate / $movieScale
    return [ordered]@{ frames=$movieFrames; width=$movieWidth; height=$movieHeight; fps=$movieActualFps; duration_seconds=$movieFrames/$movieActualFps; rate=$movieRate; scale=$movieScale }
}

$movieEncoder = Find-MovieEncoder
$movieProbeCommand = Get-Command ffprobe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$movieProbe = if ($null -ne $movieProbeCommand) { $movieProbeCommand.Source } elseif ($null -ne $movieEncoder -and (Test-Path -LiteralPath (Join-Path (Split-Path $movieEncoder -Parent) 'ffprobe.exe'))) { Join-Path (Split-Path $movieEncoder -Parent) 'ffprobe.exe' } else { $null }
$movieLock = Get-Content -LiteralPath (Join-Path $movieRepo 'scripts/dev/toolchain.json') -Raw | ConvertFrom-Json
$movieEngine = Join-Path $movieRepo ".tools/godot/Godot_v$($movieLock.version)-stable_win64_console.exe"
if (!$SkipRecording -and !(Test-Path -LiteralPath $movieEngine -PathType Leaf)) { throw 'The pinned local Godot engine is missing; no dependency will be installed.' }
$movieEnvironment = @{}
$movieEnvironmentPaths = @{ APPDATA='.tools/art/a6/movie-env/appdata'; LOCALAPPDATA='.tools/art/a6/movie-env/localappdata'; TEMP='.tools/art/a6/movie-env/temp'; TMP='.tools/art/a6/movie-env/temp' }
foreach ($movieVariable in $movieEnvironmentPaths.Keys) { $movieEnvironment[$movieVariable] = [Environment]::GetEnvironmentVariable($movieVariable,'Process') }
$movieResults = @()
try {
    foreach ($movieVariable in $movieEnvironmentPaths.Keys) {
        $movieEnvironmentPath = Get-MovieChildPath $movieEnvironmentPaths[$movieVariable]
        New-Item -ItemType Directory -Force -Path $movieEnvironmentPath | Out-Null
        [Environment]::SetEnvironmentVariable($movieVariable,$movieEnvironmentPath,'Process')
    }
    if (!$SkipRecording -and (& $movieEngine --version) -ne $movieLock.version_output) { throw 'Godot version differs from the repository toolchain lock.' }
    foreach ($movieMode in $movieSelectedModes) {
        $movieDefinition = $movieSettings.modes.$movieMode
        $movieBasename = [string]$movieDefinition.basename + $(if ($movieEffectiveReduced) { '-reduced' } else { '' })
        if ($movieBasename -notmatch '^[a-zA-Z0-9_-]+$') { throw 'Movie basename must be one safe filename component.' }
        $movieAvi = Join-Path $movieRawDirectory ($movieBasename+'.avi')
        $movieHarness = Join-Path $movieRawDirectory ($movieBasename+'-harness.json')
        $movieLog = Join-Path $movieRawDirectory ($movieBasename+'-godot.log')
        if (!$SkipRecording) {
            $movieArguments = @('--path',$movieRepo,'--resolution',"$($movieValidation.window.width)x$($movieValidation.window.height)",'--write-movie',$movieAvi,'--fixed-fps',[string]$movieSettings.fps,'--script','res://tests/integration/scene_motion_movie.gd','--',"--mode=$movieMode")
            if ($movieEffectiveReduced) { $movieArguments += '--reduced' }
            # The harness counts callbacks separately from the measured Writer
            # offset; AVI headers below independently require frame_count frames.
            $movieEnginePreference = $ErrorActionPreference
            try {
                # Windows PowerShell 5.1 surfaces native stderr as error records.
                # Keep the full engine log, then judge the completed process.
                $ErrorActionPreference = 'Continue'
                & $movieEngine @movieArguments *> $movieLog
                $movieExitCode = $LASTEXITCODE
            } finally { $ErrorActionPreference = $movieEnginePreference }
            if ($movieExitCode -ne 0 -or (Get-Content -LiteralPath $movieLog -Raw) -match 'SCRIPT ERROR:|ERROR:|MOTION MOVIE FAIL:') { throw "Movie harness failed (exit $movieExitCode). Inspect $movieLog" }
        }
        if (!(Test-Path -LiteralPath $movieAvi -PathType Leaf) -or !(Test-Path -LiteralPath $movieHarness -PathType Leaf)) { throw 'Expected raw AVI and successful harness receipt are required.' }
        $movieReceipt = Get-Content -LiteralPath $movieHarness -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($movieReceipt.failures -ne 0 -or $movieReceipt.observed_post_draw_callbacks -ne $movieExpectedCallbacks -or $movieReceipt.writer_expected_frames -ne $movieSettings.frame_count -or $movieReceipt.writer_frame_offset -ne $movieWriterOffset -or $movieReceipt.observed_post_draw_callbacks + $movieReceipt.writer_frame_offset -ne $movieReceipt.writer_expected_frames) { throw 'Harness receipt must independently identify the configured callbacks, measured Writer offset and expected Writer frames.' }
        if ($movieReceipt.mode -ne $movieMode -or [bool]$movieReceipt.reduced_motion -ne $movieEffectiveReduced -or $movieReceipt.configuration_unchanged -ne $true) {
            throw 'Movie receipt is stale or belongs to a different mode, configuration or art manifest; record it again before publication.'
        }
        $movieResourceBindings = @(@('configuration_sha256',$movieValidationPath), @('motion_settings_sha256',(Join-Path $movieRepo 'data/ui/motion.json')), @('scene_config_sha256',(Join-Path $movieRepo 'data/shop/visuals.json')), @('art_manifest_sha256',(Join-Path $movieRepo 'assets/ART_ASSET_MANIFEST.json')))
        foreach ($movieResourceBinding in $movieResourceBindings) {
            $movieResourceKey = $movieResourceBinding[0]
            $movieCurrentHash = (Get-FileHash -LiteralPath $movieResourceBinding[1] -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($movieReceipt.$movieResourceKey -ne $movieCurrentHash -or $movieReceipt.finished_resource_sha256.$movieResourceKey -ne $movieCurrentHash) { throw "Movie resource $movieResourceKey changed during or after recording; preserve the raw evidence and record again before publication." }
        }
        $movieHeader = Read-MovieAviHeader $movieAvi
        if ($movieHeader.frames -ne $movieSettings.frame_count -or $movieHeader.width -ne $movieValidation.window.width -or $movieHeader.height -ne $movieValidation.window.height -or [Math]::Abs($movieHeader.fps-$movieSettings.fps) -gt 0.001 -or [Math]::Abs($movieHeader.duration_seconds-$movieSettings.duration_seconds) -gt 0.001) {
            throw 'Actual AVI dimensions, frame count or rate differ from the validated recording contract.'
        }
        $movieRow = [ordered]@{ mode=$movieMode; reduced=$movieEffectiveReduced; observed_post_draw_callbacks=$movieReceipt.observed_post_draw_callbacks; writer_frame_offset=$movieWriterOffset; raw_avi=$movieAvi; raw_bytes=(Get-Item -LiteralPath $movieAvi).Length; raw_sha256=(Get-FileHash -LiteralPath $movieAvi -Algorithm SHA256).Hash.ToLowerInvariant(); avi_header=$movieHeader; harness_receipt=$movieHarness; godot_log=$movieLog; compressed_path=$null; encoder=$movieEncoder; not_realtime_performance=$true; status='needs_manual_compression'; needs_manual='No existing FFmpeg found. Compress the retained local AVI to the documented screenshots directory without installing a dependency.' }
        if ($null -ne $movieEncoder) {
            try {
            $movieCandidate = Join-Path $movieRawDirectory ($movieBasename+'-encoded.mp4')
            $movieEncoderLog = Join-Path $movieRawDirectory ($movieBasename+'-ffmpeg.log')
            $movieCompression = $movieSettings.compression
            $movieEncoderArguments = @('-y','-i',$movieAvi,'-map','0:v:0','-map','0:a?','-c:v',[string]$movieCompression.video_codec,'-preset',[string]$movieCompression.preset,'-crf',[string]$movieCompression.crf,'-pix_fmt',[string]$movieCompression.pixel_format,'-c:a',[string]$movieCompression.audio_codec,'-b:a',[string]$movieCompression.audio_bitrate,'-movflags','+faststart',$movieCandidate)
            $movieEncodingPreference = $ErrorActionPreference
            try {
                $ErrorActionPreference = 'Continue'
                & $movieEncoder @movieEncoderArguments *> $movieEncoderLog
                $movieEncodingCode = $LASTEXITCODE
            } finally { $ErrorActionPreference = $movieEncodingPreference }
            if ($movieEncodingCode -ne 0) { throw "Existing encoder failed. Inspect $movieEncoderLog" }
            if ((Get-Item -LiteralPath $movieCandidate).Length -gt [long]$movieCompression.max_public_bytes) {
                $movieRow['ffmpeg_candidate_bytes'] = (Get-Item -LiteralPath $movieCandidate).Length
                $movieRow['ffmpeg_candidate_over_budget'] = $true
                $movieRow.needs_manual = 'Encoded candidate exceeds the JSON publication budget; raw and candidate remain local and are not copied into the repository review directory.'
            } else {
                if ($null -ne $movieProbe) {
                    $movieProbeText = & $movieProbe -v error -select_streams v:0 -count_frames -show_entries stream=width,height,nb_read_frames,duration -of json $movieCandidate
                    if ($LASTEXITCODE -ne 0) { throw 'Existing ffprobe failed to inspect the encoded candidate.' }
                    $movieProbeResult = ($movieProbeText -join "`n") | ConvertFrom-Json
                    $movieVideo = $movieProbeResult.streams[0]
                    if ($movieVideo.width -ne $movieValidation.window.width -or $movieVideo.height -ne $movieValidation.window.height -or [int]$movieVideo.nb_read_frames -ne [int]$movieSettings.frame_count) { throw 'Encoded candidate frame count or dimensions do not match the source.' }
                    $movieRow['encoded_probe'] = $movieProbeResult
                }
                New-Item -ItemType Directory -Force -Path $moviePublicDirectory | Out-Null
                $moviePublicPath = Join-Path $moviePublicDirectory ($movieBasename+'.mp4')
                Copy-Item -LiteralPath $movieCandidate -Destination $moviePublicPath -Force
                $movieRow.compressed_path = $moviePublicPath
                $movieRow['compressed_bytes'] = (Get-Item -LiteralPath $moviePublicPath).Length
                $movieRow['compressed_sha256'] = (Get-FileHash -LiteralPath $moviePublicPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $movieRow.status = if ($null -ne $movieProbe) { 'compressed_and_ffprobe_verified' } else { 'compressed_from_header_verified_avi_no_ffprobe' }
                $movieRow.needs_manual = $null
            }
            } catch {
                $movieRow['ffmpeg_error'] = $_.Exception.GetBaseException().Message
                $movieRow.needs_manual = "Existing FFmpeg did not publish a valid candidate: $($movieRow.ffmpeg_error). The verified raw AVI remains local."
            }
        }
        if ([string]::IsNullOrEmpty([string]$movieRow.compressed_path) -and $null -ne $movieSettings.compression.windows_transcoder -and $movieSettings.compression.windows_transcoder.enabled) {
            try {
            $movieWindowsHelper = Join-Path $movieRepo 'tools/transcode_motion.ps1'
            $movieWindowsCandidate = Join-Path $movieRawDirectory ($movieBasename+'-winrt.mp4')
            $movieWindowsReport = Join-Path $movieRawDirectory ($movieBasename+'-winrt.json')
            $movieWindowsLog = Join-Path $movieRawDirectory ($movieBasename+'-winrt.log')
            if (!(Test-Path -LiteralPath $movieWindowsHelper -PathType Leaf)) {
                $movieRow.needs_manual = 'FFmpeg is unavailable and the optional Windows transcoder helper is missing; the validated raw AVI remains local.'
            } else {
                $movieWindowsPreference = $ErrorActionPreference
                try {
                    $ErrorActionPreference = 'Continue'
                    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $movieWindowsHelper -Source $movieAvi -Destination $movieWindowsCandidate -ReportPath $movieWindowsReport *> $movieWindowsLog
                    $movieWindowsCode = $LASTEXITCODE
                } finally { $ErrorActionPreference = $movieWindowsPreference }
                $movieRow['windows_transcoder_log'] = $movieWindowsLog
                $movieRow['windows_transcoder_exit_code'] = $movieWindowsCode
                if (Test-Path -LiteralPath $movieWindowsReport -PathType Leaf) {
                    $movieWindowsResult = Get-Content -LiteralPath $movieWindowsReport -Raw -Encoding UTF8 | ConvertFrom-Json
                    $movieRow['windows_transcoder'] = $movieWindowsResult
                    if ($movieWindowsCode -eq 0 -and $movieWindowsResult.success -and $movieWindowsResult.encoding_performed -and (Test-Path -LiteralPath $movieWindowsCandidate -PathType Leaf) -and (Get-Item -LiteralPath $movieWindowsCandidate).Length -le [long]$movieSettings.compression.max_public_bytes) {
                        New-Item -ItemType Directory -Force -Path $moviePublicDirectory | Out-Null
                        $moviePublicPath = Join-Path $moviePublicDirectory ($movieBasename+'.mp4')
                        Copy-Item -LiteralPath $movieWindowsCandidate -Destination $moviePublicPath -Force
                        $movieRow.compressed_path = $moviePublicPath
                        $movieRow.encoder = 'Windows.Media.Transcoding.MediaTranscoder'
                        $movieRow['compressed_bytes'] = (Get-Item -LiteralPath $moviePublicPath).Length
                        $movieRow['compressed_sha256'] = (Get-FileHash -LiteralPath $moviePublicPath -Algorithm SHA256).Hash.ToLowerInvariant()
                        $movieRow.status = 'compressed_winrt_metadata_verified_frame_count_not_directly_measured'
                        $movieRow.needs_manual = $null
                    } else {
                        $movieRow.needs_manual = "Existing Windows transcoder could not publish this AVI. Reason=$($movieWindowsResult.failure_reason); error=$($movieWindowsResult.error); HRESULT=$($movieWindowsResult.hresult). Original AVI remains local; no dependency was installed."
                    }
                } else {
                    $movieRow.needs_manual = "Existing Windows transcoder did not produce a report (exit $movieWindowsCode). Inspect $movieWindowsLog; the verified raw AVI remains local."
                }
            }
            } catch {
                $movieRow['windows_transcoder_error'] = $_.Exception.GetBaseException().Message
                $movieRow.needs_manual = "Existing Windows fallback failed: $($movieRow.windows_transcoder_error). The verified raw AVI remains local; no dependency was installed."
            }
        }
        $movieResults += $movieRow
        Write-Output "Movie $movieMode`: $($movieReceipt.observed_post_draw_callbacks) observed post-draw callbacks + measured Writer offset $movieWriterOffset; actual AVI $($movieHeader.frames) frames / $($movieHeader.fps) FPS / $($movieHeader.duration_seconds) seconds; $($movieRow.status). Fixed-step Movie Maker is not a real-time performance measurement."
    }
} finally {
    foreach ($movieVariable in $movieEnvironment.Keys) { [Environment]::SetEnvironmentVariable($movieVariable,$movieEnvironment[$movieVariable],'Process') }
}
$movieStatusPath = Get-MovieChildPath '.tools/art/a6/movie-capture-status.json'
$movieStatusJson = [ordered]@{ kind='existing_tools_only_motion_capture'; validation_sha256=(Get-FileHash -LiteralPath $movieValidationPath -Algorithm SHA256).Hash.ToLowerInvariant(); results=$movieResults; raw_movies_are_local_only=$true; no_new_dependency_installed=$true; no_git_operation_performed=$true; not_realtime_performance=$true } | ConvertTo-Json -Depth 20
[IO.File]::WriteAllText($movieStatusPath,($movieStatusJson+"`n").Replace("`r`n","`n"),(New-Object Text.UTF8Encoding $false))
Write-Output "Movie report: $movieStatusPath"
exit 0
