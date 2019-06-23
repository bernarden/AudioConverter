# Variables
$locationToSearch = "./";
$problomaticAudioFormats = @("TrueHD", "E-AC-3")

# Logic
# TODO: Include a file with previously scaned and conveted files to make this script faster.
$allFiles = Get-ChildItem $locationToSearch -Include "*.*" -Recurse;
ForEach ($file in $allFiles) {
    Write-Host "Checking file: $file"
    $audioFormatsString = ((mediainfo $file --Output='Audio;%Format%\n') | Out-String).Trim();
    $audioFormats = $audioFormatsString.Split('\r?\n');
    Write-Host "Found audio formats: '$($audioFormats -join ",")'"
    $audioIssues = $audioFormats | Where-Object { $problomaticAudioFormats -contains $_ };
    if ($audioIssues.Length -eq 0) {
        Write-Host "No audio or audio issues found. Skipping file: '$file'"
        continue;
    }

    # Note: Everything going foward has some audio issues.
    if ($audioFormats.Length -eq 1) {
        Write-Host "Trying to automaticaaly fix: '$file'"
        $newFileName = Join-Path $file.DirectoryName "$($file.BaseName)-1$($file.Extension)"
        $transcodeAudioOutput = (ffmpeg -i "$file" -map 0 -c:v copy -c:a aac -c:s copy "$newFileName") | Out-String;

        #Remove-Item -Path $file -Force
        #Rename-Item -Path $file -NewName $file.Name
    }
    else {
        Write-Host "User intervention is required. File: '$file'"
    }
}