using module ".\AnalyzedAudioStreamClass.psm1"

function Get-AnalyzedAudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string[]] $AudioFormatsToConvert
    )

    $mediaFileInfo = ffprobe -v quiet -print_format json -show_streams "$File" | ConvertFrom-Json
    if (!$mediaFileInfo -or !$mediaFileInfo.streams) {
        return $null;
    }
    $audioStreams = $mediaFileInfo.streams | Where-Object { $_.codec_type -eq "audio" };

    $checkedAudioStreams = @();
    $audioStreamIndex = 0;
    foreach ($audioSteam in $audioStreams) {
        $checkedAudioStream = [AnalyzedAudioStream]@{
            fileStreamIndex     = $audioSteam.index
            audioStreamIndex    = $audioStreamIndex++ 
            codecName           = $audioSteam.codec_name
            ShouldBeConverted   = $false;
        };
        $checkedAudioStreams += $checkedAudioStream;
        foreach ($AudioFormatToConvert in $AudioFormatsToConvert) {
            if ($audioSteam.codec_name -like "*$AudioFormatToConvert*") {
                $checkedAudioStream.ShouldBeConverted = $true;
                break;
            }
        }
    }
    return $checkedAudioStreams;
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
        [string] $AudioFormatDestination
    )

    $AudioArguments = @();
    $AudioStreamsToConvert = $AnalyzedAudioStreams | Where-Object { $_.ShouldBeConverted };
    if ($AnalyzedAudioStreams.Length -gt 0 -and $AnalyzedAudioStreams.Length -ne $AudioStreamsToConvert.Length) {
        $AudioArguments += "-c:a", "copy";
    }
    foreach ($AudioStreamToConvert in $AudioStreamsToConvert) {
        $AudioArguments += "-c:a:$($AudioStreamToConvert.audioStreamIndex)", $AudioFormatDestination;
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

    $Output = (ffprobe -i "$File" -show_format  -v quiet *>&1) | Out-String;
    if($Output -match "duration=(\d+.\d+)"){
        return $Matches[1]
    }
    return "N/A"
}

Export-ModuleMember -Function Get-AnalyzedAudioStreams, Convert-AudioStreams, Get-MediaDuration