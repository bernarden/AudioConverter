# Variables
$locationToSearch = "./";
$problematicAudioFormats = @("TrueHD", "E-AC-3")

# Logic
# TODO: Include a file with previously scanned and converted files to make this script faster.
$allFiles = Get-ChildItem $locationToSearch -Include "*.*" -Recurse;
ForEach ($file in $allFiles) {
    Write-Host "Checking file: $file"
    $audioFormatsString = ((mediainfo $file --Output='Audio;%Format%\n') | Out-String).Trim();
    $audioFormats = $audioFormatsString.Split('\r?\n');
    Write-Host "Found audio formats: '$($audioFormats -join ",")'"
    $audioIssues = $audioFormats | Where-Object { $problematicAudioFormats -contains $_ };
    if ($audioIssues.Length -eq 0) {
        Write-Host "No audio or audio issues found. Skipping file: '$file'"
        Write-Host "-------------------------"
        continue;
    }

    # Note: Everything going forward has some audio issues.
    if ($audioFormats.Length -eq 1) {
        Write-Host "Trying to automatically fix: '$file'"
        $newFileName = Join-Path $file.DirectoryName "$($file.BaseName)-1$($file.Extension)"
        $transcodeAudioOutput = ffmpeg -y -i "$file" -map 0 -c:v copy -c:a aac -c:s copy "$newFileName"
        
        if ($LastExitCode) {
            Write-Host "Failed to automatically resolve the issue with file: '$file'" 
            Remove-Item -Path $newFileName -Force
        }
        else {
            Remove-Item -Path $file -Force
            Rename-Item -Path $newFileName -NewName $file.Name
            Write-Host "File has been fixed."
        }
    }
    else {
        Write-Host "User intervention is required. File: '$file'"
    }

    Write-Host "-------------------------"
}