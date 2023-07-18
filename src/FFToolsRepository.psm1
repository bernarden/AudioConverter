using module ".\classes\AnalyzedMediaFileClass.psm1"

function Get-AnalyzedMediaFile {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string[]] $AudioCodecsToConvert
    )

    $MediaFileInfo = ffprobe -v quiet -print_format json -show_format -show_streams "$File" | ConvertFrom-Json
    if (!$MediaFileInfo -or !$MediaFileInfo.streams -or !$MediaFileInfo.format) {
        $AnalyzedMediaFile = [AnalyzedMediaFile]@{
            FileName     = $File.Name
            Duration     = "N/A"
            Bitrate      = "N/A"
            Size         = $File.Length
            VideoStreams = @()
            AudioStreams = @()
            SubtitleStreams = @()
            IsMediaFile  = $false
        }
        return $AnalyzedMediaFile;
    }

    $VideoStreams = $MediaFileInfo.streams | Where-Object { $_.codec_type -eq "video" };
    $AnalyzedVideoStreams = @();
    $StreamIndex = 0;
    ForEach ($VideoStream in $VideoStreams) {
        $AnalyzedVideoStream = [AnalyzedVideoStream]@{
            FileStreamIndex  = $VideoStream.index
            VideoStreamIndex = $StreamIndex++ 
            CodecName        = $VideoStream.codec_name
        };
        $AnalyzedVideoStreams += $AnalyzedVideoStream;
    }

    $AudioStreams = $MediaFileInfo.streams | Where-Object { $_.codec_type -eq "audio" };
    $AnalyzedAudioStreams = @();
    $StreamIndex = 0;
    ForEach ($AudioSteam in $AudioStreams) {
        $AnalyzedAudioStream = [AnalyzedAudioStream]@{
            FileStreamIndex   = $AudioSteam.index
            AudioStreamIndex  = $StreamIndex++ 
            CodecName         = $AudioSteam.codec_name
            ShouldBeConverted = Get-IsConversionRequired $AudioSteam.codec_name $AudioCodecsToConvert
        };
        $AnalyzedAudioStreams += $AnalyzedAudioStream;
    }

    $SubtitleStreams = $MediaFileInfo.streams | Where-Object { $_.codec_type -eq "subtitle" };
    $AnalyzedSubtitleStreams = @();
    $StreamIndex = 0;
    ForEach ($SubtitleSteam in $SubtitleStreams) {
        $AnalyzedSubtitleStream = [AnalyzedSubtitleStream]@{
            FileStreamIndex     = $SubtitleSteam.index
            SubtitleStreamIndex = $StreamIndex++
        };
        $AnalyzedSubtitleStreams += $AnalyzedSubtitleStream;
    }

    $AnalyzedMediaFile = [AnalyzedMediaFile]@{
        FileName        = $File.Name
        Duration        = $MediaFileInfo.format.duration ? $MediaFileInfo.format.duration : "N/A"
        Bitrate         = $MediaFileInfo.format.bit_rate ? $MediaFileInfo.format.bit_rate : "N/A"
        Size            = $File.Length
        VideoStreams    = $AnalyzedVideoStreams
        AudioStreams    = $AnalyzedAudioStreams
        SubtitleStreams = $AnalyzedSubtitleStreams
        IsMediaFile     = $true
    }
    return $AnalyzedMediaFile;
}

function Get-IsConversionRequired {
    Param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $AudioCodecsInUse,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $AudioCodecsToConvert
    )

    ForEach ($AudioCodecInUse in $AudioCodecsInUse) {
        ForEach ($AudioCodecToConvert in $AudioCodecsToConvert) {
            if ($AudioCodecInUse -like "*$AudioCodecToConvert*") {
                return $true;
            }
        }
    }

    return $false;
}

function Convert-AudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $OriginalFile,

        [Parameter(Mandatory = $true)]
        [string] $NewFileName,

        [Parameter(Mandatory = $true)]
        [AnalyzedAudioStream[]] $AnalyzedAudioStreams,
        
        [Parameter(Mandatory = $true)]
        [string] $AudioCodecDestination
    )

    $AudioArguments = @();
    $AudioStreamsToConvert = $AnalyzedAudioStreams | Where-Object { $_.ShouldBeConverted };
    if ($AnalyzedAudioStreams.Length -gt 0 -and $AnalyzedAudioStreams.Length -ne $AudioStreamsToConvert.Length) {
        $AudioArguments += "-c:a", "copy";
    }
    ForEach ($AudioStreamToConvert in $AudioStreamsToConvert) {
        $AudioArguments += "-c:a:$($AudioStreamToConvert.audioStreamIndex)", $AudioCodecDestination;
    }

    $Output = (ffmpeg -y -i "$OriginalFile" -map 0 -c:v copy $AudioArguments -c:s copy "$NewFileName" *>&1) | Out-String;
    return  @{
        ExitCode = $LastExitCode
        Output   = $Output
    }
}

Export-ModuleMember -Function Get-AnalyzedMediaFile, Get-IsConversionRequired, Convert-AudioStreams