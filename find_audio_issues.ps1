$locationToSearch = "/media";
$problematicAudioFormats = @("truehd", "eac3")

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $file
    )
    Write-Host "Checking file: $file"
    $mediaFileInfo = ffprobe -v quiet -print_format json -show_format -show_streams "$file" | ConvertFrom-Json
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
    $audioStreamIssues = @();
    foreach ($audioSteam in $audioStreams) {
        foreach ($problematicAudioFormat in $problematicAudioFormats) {
            if ($audioSteam.codec_name -like "*$problematicAudioFormat*") {
                $audioStreamIssues += [PSCustomObject]@{
                    index      = $audioSteam.index
                    codec_name = $audioSteam.codec_name
                };
            }
        }
    }
    if ($audioStreamIssues.Length -eq 0) {
        Write-Host "No audio issues found. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }

    # Note: Everything going forward has some audio issues.
    if ($audioStreams.Length -eq 1) {
        Write-Host "Trying to automatically fix: '$file'"
        $originalFileSize = $file.Length;
        $originalFileLastWriteTimeUtc = $file.LastWriteTimeUtc;
        $newFileName = Join-Path $file.DirectoryName "$($file.BaseName)-1$($file.Extension)"
        $transcodeAudioOutput = ffmpeg -y -i "$file" -map 0 -c:v copy -c:a ac3 -c:s copy "$newFileName"
        if ($LastExitCode) {
            Write-Host "Failed to automatically resolve the issue with file: '$file'" 
            Remove-Item -Path $newFileName -Force
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
    }
    else {
        Write-Host "User intervention is required. File: '$file'"
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
