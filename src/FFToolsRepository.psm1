using module ".\classes\AnalyzedAudioStreamClass.psm1"

function Get-AnalyzedAudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string[]] $AudioCodecsToConvert
    )

    $mediaFileInfo = ffprobe -v quiet -print_format json -show_streams "$File" | ConvertFrom-Json
    if (!$mediaFileInfo -or !$mediaFileInfo.streams) {
        return $null;
    }
    $audioStreams = $mediaFileInfo.streams | Where-Object { $_.codec_type -eq "audio" };

    $checkedAudioStreams = @();
    $audioStreamIndex = 0;
    ForEach ($audioSteam in $audioStreams) {
        $checkedAudioStream = [AnalyzedAudioStream]@{
            FileStreamIndex   = $audioSteam.index
            AudioStreamIndex  = $audioStreamIndex++ 
            CodecName         = $audioSteam.codec_name
            ShouldBeConverted = Get-IsConversionRequired $audioSteam.codec_name $AudioCodecsToConvert
        };
        $checkedAudioStreams += $checkedAudioStream;
    }

    return , $checkedAudioStreams;
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

function Get-MediaDuration {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    $Output = (ffprobe -i "$File" -show_format -v quiet *>&1) | Out-String;
    if ($Output -match "duration=(\d+.\d+)") {
        return $Matches[1]
    }
    return "N/A"
}

Export-ModuleMember -Function Get-AnalyzedAudioStreams, Get-IsConversionRequired, Convert-AudioStreams, Get-MediaDuration