using module ".\AnalyzedAudioStreamClass.psm1"

function Get-AnalyzedAudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string[]] $ProblematicAudioFormats
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
            fileStreamIndex  = $audioSteam.index
            audioStreamIndex = $audioStreamIndex++ 
            codecName        = $audioSteam.codec_name
            isProblematic    = $false;
        };
        $checkedAudioStreams += $checkedAudioStream;
        foreach ($problematicAudioFormat in $ProblematicAudioFormats) {
            if ($audioSteam.codec_name -like "*$problematicAudioFormat*") {
                $checkedAudioStream.isProblematic = $true;
                break;
            }
        }
    }
    return $checkedAudioStreams;
}

function Convert-ProblematicAudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $OriginalFile,

        [Parameter(Mandatory = $true)]
        [string] $NewFileName,

        [Parameter(Mandatory = $true)]
        [AnalyzedAudioStream[]] $AnalyzedAudioStreams,
        
        [Parameter(Mandatory = $true)]
        [string] $AmendedAudioFormat
    )

    $AudioArguments = "";
    $ProblematicAudioStreams = $AnalyzedAudioStreams | Where-Object { $_.isProblematic };
    if ($AnalyzedAudioStreams.Length -gt 0 -and $AnalyzedAudioStreams.Length -ne $ProblematicAudioStreams.Length) {
        $AudioArguments = "-c:a copy";
    }
    foreach ($ProblematicAudioStream in $ProblematicAudioStreams) {
        $AudioArguments += " -c:a:$($ProblematicAudioStream.audioStreamIndex) $($AmendedAudioFormat)";
    }

    $TranscodeCommand = "ffmpeg -y -i ""$OriginalFile"" -map 0 -c:v copy $AudioArguments -c:s copy ""$NewFileName"""
    Invoke-Expression $TranscodeCommand *> $null
    return $LastExitCode
}

Export-ModuleMember -Function Get-AnalyzedAudioStreams, Convert-ProblematicAudioStreams