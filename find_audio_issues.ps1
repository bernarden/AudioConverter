$locationToSearch = "/media";
$problematicAudioFormats = @("truehd", "eac3")

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $file
    )
    Write-Host "Checking file: $file"
    $mediaFileInfo = ffprobe -v quiet -print_format json -show_streams "$file" | ConvertFrom-Json
    if ($mediaFileInfo.PSObject.Properties.Name -notcontains "streams") {
        Write-Host "Not a media file. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }
    
    $audioStreams = $mediaFileInfo.streams | Where-Object { $_.codec_type -eq "audio" };
    if ($audioStreams.Length -eq 0) {
        Write-Host "No audio found. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Found audio formats: '$(($audioStreams | Select-Object -ExpandProperty codec_name) -join ", ")'"
    $checkedAudioStreams = @();
    $audioStreamIndex = 0;
    foreach ($audioSteam in $audioStreams) {
        $isAdded = false;
        foreach ($problematicAudioFormat in $problematicAudioFormats) {
            if ($audioSteam.codec_name -like "*$problematicAudioFormat*" -and !$isAdded) {
                $checkedAudioStreams += [PSCustomObject]@{
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
            $checkedAudioStreams += [PSCustomObject]@{
                fileStreamIndex  = $audioSteam.index
                audioStreamIndex = $audioStreamIndex++ 
                codecName        = $audioSteam.codec_name
                isProblematic    = $false;
            };
        }
    }

    $problematicAudioStreams = $checkedAudioStreams | Where-Object { $_.isProblematic };
    if ($problematicAudioStreams.Length -eq 0) {
        Write-Host "No audio issues found. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Trying to automatically fix: '$file'"
    $originalFileSize = $file.Length;
    $originalFileLastWriteTimeUtc = $file.LastWriteTimeUtc;
    $newFileName = Join-Path $file.DirectoryName "$($file.BaseName)-1$($file.Extension)"

    $audioArguments = "";
    Write-Host "checkedAudioStreams: $($checkedAudioStreams.Length)"
    Write-Host "problematicAudioStreams: $($problematicAudioStreams.Length)"
    if ($checkedAudioStreams.Length -gt 0 -and $checkedAudioStreams.Length -ne $problematicAudioStreams.Length) {
        $audioArguments = "-c:a copy";
    }
    foreach ($problematicAudioStream in $problematicAudioStreams) {
        $audioArguments += " -c:a:$($problematicAudioStream.audioStreamIndex) ac3";
    }

    $transcodeCommand = "ffmpeg -y -i ""$file"" -map 0 -c:v copy $audioArguments -c:s copy ""$newFileName"""
    Invoke-Expression $transcodeCommand        
    if ($LastExitCode) {
        Write-Host "Failed to automatically resolve the issue with file: '$file'" 
        Remove-Item -Path $newFileName -Force -ErrorAction Ignore
    }
    else {
        $file.Refresh();
        if ($originalFileSize -eq $file.Length -and $originalFileLastWriteTimeUtc -eq $file.LastWriteTimeUtc) {
            Remove-Item -Path $file -Force
            Rename-Item -Path $newFileName -NewName $file.Name
            Write-Host "File has been fixed."
        }
        else { 
            Remove-Item -Path $newFileName -Force
            Write-Host "File has been changed during transcoding. Try again next time."
        }
    }

    Write-Host "-------------------------"
}

function Main {
    while ($true) {
        # TODO: Include a file with previously scanned and converted files to make this script faster.
        $allFiles = Get-ChildItem $locationToSearch -Include "*.*" -Recurse -File;
        ForEach ($file in $allFiles) {
            try {
                Convert-File $file
            }
            catch { 
                Write-Host $_.Exception | Format-List -force
            }
        }
        Start-Sleep -s 43200
    }
}

Main
