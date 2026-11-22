<#
.SYNOPSIS
Optional existing Windows MediaTranscoder fallback for a local motion AVI.
.DESCRIPTION
Pure Windows PowerShell 5.1 and the Windows Runtime projection. Add-Type below
loads a system assembly; it does not compile C# source or install a dependency.
Only generated files inside the validated local movie directory may be used.
Exit 2 means that manual compression is required; the original AVI is retained.
.LINK
https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/transcode-media-files
.LINK
https://learn.microsoft.com/en-us/uwp/api/windows.media.transcoding.mediatranscoder.preparefiletranscodeasync
#>
[CmdletBinding(DefaultParameterSetName='Transcode')]
param(
    [Parameter(Mandatory=$true,ParameterSetName='Transcode')][string]$Source,
    [Parameter(Mandatory=$true,ParameterSetName='Transcode')][string]$Destination,
    [Parameter(Mandatory=$true,ParameterSetName='Probe')][switch]$ProbeOnly,
    [string]$ReportPath = ''
)
$ErrorActionPreference = 'Stop'
$winrtRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$winrtValidationPath = Join-Path $winrtRepo 'data/art/motion_validation.json'
$winrtExit = 2
$winrtReport = [ordered]@{
    provider='Windows.Media.Transcoding.MediaTranscoder'
    powershell=$PSVersionTable.PSVersion.ToString()
    probe_only=[bool]$ProbeOnly
    success=$false
    status='needs_manual_compression'
    encoding_attempted=$false
    encoding_performed=$false
    failure_reason=$null
    error=$null
    hresult=$null
    source=$Source
    destination=$Destination
    no_new_dependency_installed=$true
    no_csharp_source_compiled=$true
    module_metadata=[ordered]@{
        assembly='System.Runtime.WindowsRuntime'
        os_version=[Environment]::OSVersion.VersionString
        api_documentation=@(
            'https://learn.microsoft.com/en-us/windows/apps/develop/media-authoring-processing/transcode-media-files',
            'https://learn.microsoft.com/en-us/uwp/api/windows.media.transcoding.mediatranscoder.preparefiletranscodeasync'
        )
    }
}

function Get-WinrtRepoPath([string]$Path) {
    $winrtResolved = if ([IO.Path]::IsPathRooted($Path)) { [IO.Path]::GetFullPath($Path) } else { [IO.Path]::GetFullPath((Join-Path $winrtRepo $Path)) }
    $winrtPrefix = $winrtRepo.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if (!$winrtResolved.StartsWith($winrtPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Transcoder path escaped the repository.' }
    return $winrtResolved
}

function Wait-WinrtOperation($Operation, [Type]$ResultType, [double]$TimeoutSeconds) {
    $winrtMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    if ($null -eq $winrtMethod) { throw 'The existing Windows Runtime IAsyncOperation task bridge is unavailable.' }
    $winrtTask = $winrtMethod.MakeGenericMethod($ResultType).Invoke($null,@($Operation))
    if (!$winrtTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
        try { $Operation.Cancel() } catch { }
        throw 'Windows Runtime media operation exceeded its validated timeout.'
    }
    return $winrtTask.GetAwaiter().GetResult()
}

function Wait-WinrtTranscode($Operation, [double]$TimeoutSeconds) {
    $winrtMethod = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetGenericArguments().Count -eq 1 -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncActionWithProgress`1'
    } | Select-Object -First 1
    if ($null -eq $winrtMethod) { throw 'The existing Windows Runtime progress-action task bridge is unavailable.' }
    $winrtTask = $winrtMethod.MakeGenericMethod([double]).Invoke($null,@($Operation))
    if (!$winrtTask.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
        try { $Operation.Cancel() } catch { }
        throw 'Windows Runtime transcoding exceeded its validated timeout.'
    }
    $winrtTask.GetAwaiter().GetResult()
}

try {
    if ($PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5) { throw 'Use existing Windows PowerShell 5.1 for the system WinRT projection.' }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    $winrtStorageFile = [Type]::GetType('Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime',$true)
    $winrtStorageFolder = [Type]::GetType('Windows.Storage.StorageFolder, Windows.Storage, ContentType=WindowsRuntime',$true)
    $winrtCollision = [Type]::GetType('Windows.Storage.CreationCollisionOption, Windows.Storage, ContentType=WindowsRuntime',$true)
    $winrtTranscoderType = [Type]::GetType('Windows.Media.Transcoding.MediaTranscoder, Windows.Media.Transcoding, ContentType=WindowsRuntime',$true)
    $winrtPreparedType = [Type]::GetType('Windows.Media.Transcoding.PrepareTranscodeResult, Windows.Media.Transcoding, ContentType=WindowsRuntime',$true)
    $winrtProfileType = [Type]::GetType('Windows.Media.MediaProperties.MediaEncodingProfile, Windows.Media.MediaProperties, ContentType=WindowsRuntime',$true)
    $winrtQualityType = [Type]::GetType('Windows.Media.MediaProperties.VideoEncodingQuality, Windows.Media.MediaProperties, ContentType=WindowsRuntime',$true)
    $winrtVideoPropertiesType = [Type]::GetType('Windows.Storage.FileProperties.VideoProperties, Windows.Storage, ContentType=WindowsRuntime',$true)
    $winrtReport['available_types'] = @($winrtStorageFile.FullName,$winrtStorageFolder.FullName,$winrtTranscoderType.FullName,$winrtPreparedType.FullName,$winrtProfileType.FullName,$winrtQualityType.FullName)
    $winrtValidation = Get-Content -LiteralPath $winrtValidationPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $winrtMovie = $winrtValidation.movie
    $winrtSettings = $winrtMovie.compression.windows_transcoder
    $winrtQualityName = if ($null -ne $winrtSettings) { [string]$winrtSettings.quality } else { 'HD1080p' }
    $winrtQuality = [Enum]::Parse($winrtQualityType,$winrtQualityName)
    $winrtProfile = $winrtProfileType::CreateMp4($winrtQuality)
    $winrtTranscoder = [Activator]::CreateInstance($winrtTranscoderType)
    $winrtReport['profile_probe'] = [ordered]@{ container=$winrtProfile.Container.Subtype; video_subtype=$winrtProfile.Video.Subtype; width=$winrtProfile.Video.Width; height=$winrtProfile.Video.Height; bitrate=$winrtProfile.Video.Bitrate; frame_rate_numerator=$winrtProfile.Video.FrameRate.Numerator; frame_rate_denominator=$winrtProfile.Video.FrameRate.Denominator }
    if ($ProbeOnly) {
        $winrtReport.success = $true
        $winrtReport.status = 'api_profile_probe_passed_no_media_opened'
        $winrtExit = 0
    } else {
        if ($null -eq $winrtSettings -or !$winrtSettings.enabled -or $winrtSettings.quality -ne 'HD1080p' -or $winrtSettings.timeout_seconds -le 0 -or $winrtSettings.bitrate_budget_fraction -le 0 -or $winrtSettings.bitrate_budget_fraction -ge 1) { throw 'Windows transcoder fallback is absent, disabled or invalid in movie validation data.' }
        if ($winrtMovie.duration_seconds -le 0 -or $winrtMovie.fps -le 0 -or $winrtMovie.frame_count -ne $winrtMovie.duration_seconds*$winrtMovie.fps) { throw 'Invalid movie frame contract.' }
        $winrtRawDirectory = Get-WinrtRepoPath ([string]$winrtMovie.capture_directory)
        $winrtRawPrefix = $winrtRawDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
        $winrtSourcePath = Get-WinrtRepoPath $Source
        $winrtDestinationPath = Get-WinrtRepoPath $Destination
        if (!$winrtSourcePath.StartsWith($winrtRawPrefix,[StringComparison]::OrdinalIgnoreCase) -or !$winrtDestinationPath.StartsWith($winrtRawPrefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetExtension($winrtSourcePath) -ne '.avi' -or [IO.Path]::GetExtension($winrtDestinationPath) -ne '.mp4') { throw 'Only a retained local movie AVI and a local generated MP4 candidate are accepted.' }
        if (!(Test-Path -LiteralPath $winrtSourcePath -PathType Leaf)) { throw 'The retained AVI does not exist; no media encoding was attempted.' }
        $winrtReport.source = $winrtSourcePath
        $winrtReport.destination = $winrtDestinationPath
        $winrtReport['source_sha256'] = (Get-FileHash -LiteralPath $winrtSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
        $winrtProfile.Video.Width = [uint32]$winrtValidation.window.width
        $winrtProfile.Video.Height = [uint32]$winrtValidation.window.height
        $winrtProfile.Video.FrameRate.Numerator = [uint32]$winrtMovie.fps
        $winrtProfile.Video.FrameRate.Denominator = 1
        $winrtAudioBitrate = if ($null -ne $winrtProfile.Audio) { [double]$winrtProfile.Audio.Bitrate } else { 0.0 }
        $winrtAvailableBitrate = [Math]::Floor([double]$winrtMovie.compression.max_public_bytes*8.0*[double]$winrtSettings.bitrate_budget_fraction/[double]$winrtMovie.duration_seconds-$winrtAudioBitrate)
        if ($winrtAvailableBitrate -le 0) { throw 'Validated publication budget leaves no room for the H264 video stream.' }
        $winrtProfile.Video.Bitrate = [uint32][Math]::Min([double]$winrtProfile.Video.Bitrate,$winrtAvailableBitrate)
        $winrtReport['requested_profile'] = [ordered]@{ quality=$winrtQualityName; video_subtype=$winrtProfile.Video.Subtype; width=$winrtProfile.Video.Width; height=$winrtProfile.Video.Height; video_bitrate=$winrtProfile.Video.Bitrate; audio_bitrate=$winrtAudioBitrate; frame_rate_numerator=$winrtProfile.Video.FrameRate.Numerator; frame_rate_denominator=$winrtProfile.Video.FrameRate.Denominator; budget_fraction=$winrtSettings.bitrate_budget_fraction; max_public_bytes=$winrtMovie.compression.max_public_bytes }
        $winrtTimeout = [double]$winrtSettings.timeout_seconds
        $winrtSourceFile = Wait-WinrtOperation ($winrtStorageFile::GetFileFromPathAsync($winrtSourcePath)) $winrtStorageFile $winrtTimeout
        $winrtOutputDirectory = Split-Path $winrtDestinationPath -Parent
        New-Item -ItemType Directory -Force -Path $winrtOutputDirectory | Out-Null
        $winrtOutputFolder = Wait-WinrtOperation ($winrtStorageFolder::GetFolderFromPathAsync($winrtOutputDirectory)) $winrtStorageFolder $winrtTimeout
        $winrtReplace = [Enum]::Parse($winrtCollision,'ReplaceExisting')
        $winrtOutputFile = Wait-WinrtOperation ($winrtOutputFolder.CreateFileAsync([IO.Path]::GetFileName($winrtDestinationPath),$winrtReplace)) $winrtStorageFile $winrtTimeout
        $winrtPrepared = Wait-WinrtOperation ($winrtTranscoder.PrepareFileTranscodeAsync($winrtSourceFile,$winrtOutputFile,$winrtProfile)) $winrtPreparedType $winrtTimeout
        $winrtReport['can_transcode'] = [bool]$winrtPrepared.CanTranscode
        $winrtReport['prepare_failure_reason'] = $winrtPrepared.FailureReason.ToString()
        if (!$winrtPrepared.CanTranscode) { $winrtReport.failure_reason = $winrtPrepared.FailureReason.ToString(); throw "Windows could not prepare this AVI: $($winrtPrepared.FailureReason)." }
        $winrtReport.encoding_attempted = $true
        Wait-WinrtTranscode ($winrtPrepared.TranscodeAsync()) $winrtTimeout
        $winrtReport.encoding_performed = $true
        $winrtOutputBytes = (Get-Item -LiteralPath $winrtDestinationPath).Length
        if ($winrtOutputBytes -le 0 -or $winrtOutputBytes -gt [long]$winrtMovie.compression.max_public_bytes) { throw 'Windows encoded candidate is empty or exceeds the validated publication budget; it remains local.' }
        $winrtOutputProfile = Wait-WinrtOperation ($winrtProfileType::CreateFromFileAsync($winrtOutputFile)) $winrtProfileType $winrtTimeout
        $winrtVideoProperties = Wait-WinrtOperation ($winrtOutputFile.Properties.GetVideoPropertiesAsync()) $winrtVideoPropertiesType $winrtTimeout
        $winrtActualFps = [double]$winrtOutputProfile.Video.FrameRate.Numerator/[double]$winrtOutputProfile.Video.FrameRate.Denominator
        $winrtActualDuration = [double]$winrtVideoProperties.Duration.TotalSeconds
        $winrtReport['encoded_metadata'] = [ordered]@{ container=$winrtOutputProfile.Container.Subtype; video_subtype=$winrtOutputProfile.Video.Subtype; width=$winrtOutputProfile.Video.Width; height=$winrtOutputProfile.Video.Height; fps=$winrtActualFps; duration_seconds=$winrtActualDuration; bytes=$winrtOutputBytes; sha256=(Get-FileHash -LiteralPath $winrtDestinationPath -Algorithm SHA256).Hash.ToLowerInvariant(); direct_frame_count_available=$false }
        if ($winrtOutputProfile.Video.Width -ne $winrtValidation.window.width -or $winrtOutputProfile.Video.Height -ne $winrtValidation.window.height -or [Math]::Abs($winrtActualFps-[double]$winrtMovie.fps) -gt 0.001 -or [Math]::Abs($winrtActualDuration-[double]$winrtMovie.duration_seconds) -gt 1.0/[double]$winrtMovie.fps) { throw 'Windows encoded metadata does not match the validated dimensions, FPS or duration.' }
        $winrtReport.success = $true
        $winrtReport.status = 'encoded_winrt_metadata_verified_frame_count_not_directly_measured'
        $winrtReport.failure_reason = $null
        $winrtExit = 0
    }
} catch {
    $winrtBaseException = $_.Exception.GetBaseException()
    $winrtReport.error = $winrtBaseException.Message
    $winrtReport.hresult = $winrtBaseException.HResult
    if ([string]::IsNullOrEmpty([string]$winrtReport.failure_reason)) { $winrtReport.failure_reason = $winrtBaseException.GetType().FullName }
} finally {
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = if ($ProbeOnly) { '.tools/art/a6/movie-winrt-capability.json' } else { $Destination+'.winrt.json' }
    }
    $winrtReportFile = Get-WinrtRepoPath $ReportPath
    $winrtReportDirectory = Split-Path $winrtReportFile -Parent
    $winrtAllowedReportPrefix = (Get-WinrtRepoPath '.tools/art/a6').TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if (!$winrtReportFile.StartsWith($winrtAllowedReportPrefix,[StringComparison]::OrdinalIgnoreCase)) { throw 'Windows transcoder evidence must remain inside the local A6 tool directory.' }
    New-Item -ItemType Directory -Force -Path $winrtReportDirectory | Out-Null
    $winrtJson = $winrtReport | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($winrtReportFile,($winrtJson+"`n").Replace("`r`n","`n"),(New-Object Text.UTF8Encoding $false))
    Write-Output "WINDOWS MOTION TRANSCODER: $($winrtReport.status); report=$winrtReportFile"
    if (!$winrtReport.success) { Write-Output "WINDOWS MOTION TRANSCODER REASON: $($winrtReport.failure_reason); $($winrtReport.error); HRESULT=$($winrtReport.hresult)" }
}
exit $winrtExit
