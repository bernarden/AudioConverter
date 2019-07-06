using module ".\FFToolsRepository.psm1"

# Arguments
$WaitBetweenScansInSecondsArg = [int](Get-ChildItem -Path Env:WAIT_BETWEEN_SCANS_IN_SECONDS -ErrorAction SilentlyContinue).Value
$ProblematicAudioFormatsArg = (Get-ChildItem -Path Env:PROBLEMATIC_AUDIO_FORMATS -ErrorAction SilentlyContinue).Value
$ProblematicAudioFormatsArg = if ($null -ne $ProblematicAudioFormatsArg) { [regex]::split($ProblematicAudioFormatsArg, '[,\s]+') } else { 0 }
$AmendedAudioFormatArg = [string](Get-ChildItem -Path Env:AMENDED_AUDIO_FORMAT -ErrorAction SilentlyContinue).Value

# Variables
$LocationToSearch = "/media";
$ProblematicAudioFormats = ($ProblematicAudioFormatsArg, @("truehd", "eac3") -ne 0)[0];
$WaitBetweenScansInSeconds = ($WaitBetweenScansInSecondsArg, 43200 -ne 0)[0];
$AmendedAudioFormat = ($AmendedAudioFormatArg, "ac3" -ne '')[0];

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    Write-Host "Checking file: $File"
    $AnalyzedAudioStreams = Get-AnalyzedAudioStreams -File $File -ProblematicAudioFormats $ProblematicAudioFormats
    if ($null -eq $AnalyzedAudioStreams) {
        Write-Host "Not a media file. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }
    
    if ($AnalyzedAudioStreams.Length -eq 0) {
        Write-Host "No audio found. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Found audio formats: '$(($AnalyzedAudioStreams | Select-Object -ExpandProperty codecName) -join ", ")'"
    if (($AnalyzedAudioStreams | Where-Object { $_.IsProblematic }).Length -eq 0) {
        Write-Host "No issues found. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Trying to automatically fix: '$File'"
    $OriginalFileSize = $File.Length;
    $OriginalFileLastWriteTimeUtc = $File.LastWriteTimeUtc;
    $NewFileName = Join-Path $File.DirectoryName "$($File.BaseName)-1$($File.Extension)"
    $ExitCode = Convert-ProblematicAudioStreams -OriginalFile $File -NewFileName $NewFileName -AnalyzedAudioStreams $AnalyzedAudioStreams -AmendedAudioFormat $AmendedAudioFormat
    if ($ExitCode) {
        Write-Host "Failed to automatically resolve the issue with file: '$File'" 
        Remove-Item -Path $NewFileName -Force -ErrorAction Ignore
        Write-Host "-------------------------"
        continue;
    }
 
    $File.Refresh();
    if ($OriginalFileSize -eq $File.Length -and $OriginalFileLastWriteTimeUtc -eq $File.LastWriteTimeUtc) {
        Remove-Item -Path $File -Force
        Rename-Item -Path $NewFileName -NewName $File.Name
        Write-Host "File has been fixed."
        Write-Host "-------------------------"
    }
    else { 
        Remove-Item -Path $NewFileName -Force
        Write-Host "File has been changed during transcoding. Try again next time."
        Write-Host "-------------------------"
    }
}

function Get-FilesToCheck {
    # TODO: Include a file with previously scanned and converted files to make this script faster.
    $AllFiles = Get-ChildItem $LocationToSearch -Include "*.*" -Recurse -File;
    return $AllFiles;
}

function Main {
    while ($true) {
        $FilesToCheck = Get-FilesToCheck
        ForEach ($File in $FilesToCheck) {
            try {
                Convert-File -File $File
            }
            catch { 
                Write-Host $_.Exception
            }
        }
        Start-Sleep -s $WaitBetweenScansInSeconds
    }
}

Main
