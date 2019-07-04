using module ".\AnalyzedAudioStream.psm1"

function Get-AnalyzedAudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $file,

        [Parameter(Mandatory = $true)]
        [string[]] $problematicAudioFormats
    )

    $mediaFileInfo = ffprobe -v quiet -print_format json -show_streams "$file" | ConvertFrom-Json
    if (!$mediaFileInfo -or !$mediaFileInfo.streams) {
        return $null;
    }
    $audioStreams = $mediaFileInfo.streams | Where-Object { $_.codec_type -eq "audio" };

    $checkedAudioStreams = @();
    $audioStreamIndex = 0;
    foreach ($audioSteam in $audioStreams) {
        $isAdded = false;
        foreach ($problematicAudioFormat in $problematicAudioFormats) {
            if ($audioSteam.codec_name -like "*$problematicAudioFormat*" -and !$isAdded) {
                $checkedAudioStreams += [AnalyzedAudioStream]@{
                    fileStreamIndex  = $audioSteam.index
                    audioStreamIndex = $audioStreamIndex++ 
                    codecName        = $audioSteam.codec_name
                    isProblematic    = $true;
                };
                $isAdded = $true;
                break;
            }
        }
        if (!$isAdded) {
            $checkedAudioStreams += [AnalyzedAudioStream]@{
                fileStreamIndex  = $audioSteam.index
                audioStreamIndex = $audioStreamIndex++ 
                codecName        = $audioSteam.codec_name
                isProblematic    = $false;
            };
        }
    }
    return $checkedAudioStreams;
}

function Convert-ProblematicAudioStreams {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $originalFile,

        [Parameter(Mandatory = $true)]
        [string] $newFileName,

        [Parameter(Mandatory = $true)]
        [AnalyzedAudioStream[]] $analyzedAudioStreams,
        
        [string] $newCodecNew = "ac3"
    )

    $audioArguments = "";
    $problematicAudioStreams = $analyzedAudioStreams | Where-Object { $_.isProblematic };
    if ($analyzedAudioStreams.Length -gt 0 -and $analyzedAudioStreams.Length -ne $problematicAudioStreams.Length) {
        $audioArguments = "-c:a copy";
    }
    foreach ($problematicAudioStream in $problematicAudioStreams) {
        $audioArguments += " -c:a:$($problematicAudioStream.audioStreamIndex) $($newCodecNew)";
    }

    $transcodeCommand = "ffmpeg -y -i ""$originalFile"" -map 0 -c:v copy $audioArguments -c:s copy ""$newFileName"""
    Invoke-Expression $transcodeCommand *> $null
    return $LastExitCode
}

Export-ModuleMember -Function Get-AnalyzedAudioStreams, Convert-ProblematicAudioStreams