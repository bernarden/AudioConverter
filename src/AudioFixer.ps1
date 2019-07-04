using module ".\FFToolsRepository.psm1"

$locationToSearch = "/media";
$problematicAudioFormats = @("truehd", "eac3")

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $file
    )

    Write-Host "Checking file: $file"
    $analyzedAudioStreams = Get-AnalyzedAudioStreams -file $file -problematicAudioFormats $problematicAudioFormats
    if ($null -eq $analyzedAudioStreams) {
        Write-Host "Not a media file. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }
    
    if ($analyzedAudioStreams.Length -eq 0) {
        Write-Host "No audio found. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Found audio formats: '$(($analyzedAudioStreams | Select-Object -ExpandProperty codecName) -join ", ")'"
    if (($analyzedAudioStreams | Where-Object { $_.isProblematic }).Length -eq 0) {
        Write-Host "No issues found. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Trying to automatically fix: '$file'"
    $originalFileSize = $file.Length;
    $originalFileLastWriteTimeUtc = $file.LastWriteTimeUtc;
    $newFileName = Join-Path $file.DirectoryName "$($file.BaseName)-1$($file.Extension)"
    $ExitCode = Convert-ProblematicAudioStreams -originalFile $file -newFileName $newFileName -analyzedAudioStreams $analyzedAudioStreams 
    if ($ExitCode) {
        Write-Host "Failed to automatically resolve the issue with file: '$file'" 
        Remove-Item -Path $newFileName -Force -ErrorAction Ignore
        Write-Host "-------------------------"
        continue;
    }
 
    $file.Refresh();
    if ($originalFileSize -eq $file.Length -and $originalFileLastWriteTimeUtc -eq $file.LastWriteTimeUtc) {
        Remove-Item -Path $file -Force
        Rename-Item -Path $newFileName -NewName $file.Name
        Write-Host "File has been fixed."
        Write-Host "-------------------------"
    }
    else { 
        Remove-Item -Path $newFileName -Force
        Write-Host "File has been changed during transcoding. Try again next time."
        Write-Host "-------------------------"
    }
}

function Get-FilesToCheck {
    # TODO: Include a file with previously scanned and converted files to make this script faster.
    $allFiles = Get-ChildItem $locationToSearch -Include "*.*" -Recurse -File;
    return $allFiles;
}

function Main {
    while ($true) {
        $filesToCheck = Get-FilesToCheck
        ForEach ($file in $filesToCheck) {
            try {
                Convert-File $file
            }
            catch { 
                Write-Host $_.Exception
            }
        }
        Start-Sleep -s 43200
    }
}

Main
