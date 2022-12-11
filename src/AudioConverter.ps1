using module ".\FFToolsRepository.psm1"
using module ".\ConfigRepository.psm1"
using module ".\EmailRepository.psm1"
using module ".\EnvVariableHelper.psm1"
using module ".\ScriptVersionMigrator.psm1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Variables
$LocationToSearch = "/media";
$ConfigDirectory = "/config"
$AudioCodecsToConvert = Get-StringArrayEnvVariable -Name "AUDIO_CODECS_TO_CONVERT" -DefaultValue @("truehd", "eac3")
$AudioCodecDestination = Get-StringEnvVariable -Name "AUDIO_CODEC_DESTINATION" -DefaultValue "ac3"
$WaitBetweenScansInSeconds = Get-IntEnvVariable -Name "WAIT_BETWEEN_SCANS_IN_SECONDS" -DefaultValue 43200
$CurrentScriptVersion = "1.2.0"
$global:IsFirstRun = $true;

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    Write-Host "-------------------------"
    Write-Host "Checking file: $File"
    $AnalyzedAudioStreams = Get-AnalyzedAudioStreams -File $File -AudioCodecsToConvert $AudioCodecsToConvert
    if ($null -eq $AnalyzedAudioStreams) {
        Set-FileAsScannedOrConverted $File "N/A" @()
        Write-Host "Not a media file. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }
    
    if ($AnalyzedAudioStreams.Length -eq 0) {
        $Duration = Get-MediaDuration $File
        Set-FileAsScannedOrConverted $File $Duration @()
        Write-Host "No audio found. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }

    $OriginalAudioCodecs = @($AnalyzedAudioStreams | Select-Object -ExpandProperty CodecName);
    Write-Host "Found audio codecs: '$($OriginalAudioCodecs -join ", ")'"
    if (($AnalyzedAudioStreams | Where-Object { $_.ShouldBeConverted } | Measure-Object).Count -eq 0) {
        $Duration = Get-MediaDuration $File
        Set-FileAsScannedOrConverted $File $Duration $OriginalAudioCodecs
        Write-Host "No conversion needed. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Trying to automatically convert: '$File'"
    $OriginalFileLength = $File.Length;
    $OriginalFileLastWriteTimeUtc = $File.LastWriteTimeUtc;
    $NewFileName = Join-Path $File.DirectoryName "$($File.BaseName)-1$($File.Extension)"
    $ConversionResult = Convert-AudioStreams -OriginalFile $File -NewFileName $NewFileName -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $AudioCodecDestination
    if ($ConversionResult.ExitCode) {
        Write-Host "Failed to automatically convert the file: '$File'" 
        Write-Host $ConversionResult.Output
        Remove-Item -Path $NewFileName -Force -ErrorAction Ignore
        Send-TranscodingFailureEmail -File $File -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $AudioCodecDestination -Logs $ConversionResult.Output
        Write-Host "-------------------------"
        continue;
    }
 
    $File.Refresh();
    if ($OriginalFileLength -eq $File.Length -and $OriginalFileLastWriteTimeUtc -eq $File.LastWriteTimeUtc) {
        Remove-Item -Path $File -Force
        Rename-Item -Path $NewFileName -NewName $File.Name
        $File.Refresh();
        $Duration = Get-MediaDuration $File
        $NewAnalyzedAudioStreams = Get-AnalyzedAudioStreams -File $File -AudioCodecsToConvert $AudioCodecsToConvert
        $NewAudioCodecs = @($NewAnalyzedAudioStreams | Select-Object -ExpandProperty CodecName);
        Set-FileAsScannedOrConverted $File $Duration $NewAudioCodecs
        Write-Host "File has been converted."
        Write-Host "-------------------------"
    }
    else { 
        Remove-Item -Path $NewFileName -Force
        Write-Host "File has been changed during transcoding. Try again next time."
        Write-Host "-------------------------"
    }
}

function Get-FilesToCheck {
    Write-Host "Scanning for media files.";
    $AllFiles = @(Get-ChildItem $LocationToSearch -Include "*.*" -Recurse -File);
    
    if ($global:IsFirstRun) {
        Write-Host "Checking if any previously tracked files require a conversion." ;
        Remove-PreviouslyCheckedFilesFromConfigIfConversionIsRequired 
        $global:IsFirstRun = $false;
    }
    $AllUncheckedFiles = Get-UncheckedFilesAndRemoveDeletedFilesFromConfig $AllFiles
    return , $AllUncheckedFiles;
}

function New-DirectoryIfDoesNotExist {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $DirectoryPath
    )

    If (!(Test-Path $DirectoryPath)) {
        New-Item -ItemType Directory -Force -Path $DirectoryPath | Out-Null
    }
}

function Main {
    Write-Host "Starting up."
    New-DirectoryIfDoesNotExist -DirectoryPath $LocationToSearch
    New-DirectoryIfDoesNotExist -DirectoryPath $ConfigDirectory
    
    if ( $AudioCodecsToConvert -contains $AudioCodecDestination) {
        Write-Host "AudioCodecsToConvert ('$($AudioCodecsToConvert -join ", ")') contains AudioCodecDestination ($AudioCodecDestination) and therefore will cause infinite loop."
        Write-Host "Exiting."
        exit;
    }

    Initialize-EmailRepository
    Initialize-ConfigRepository -ConfigDirectory $ConfigDirectory -CurrentVersion $CurrentScriptVersion -AudioCodecsToConvert $AudioCodecsToConvert
    
    Move-ScriptToNewVersion -CurrentVersion $CurrentScriptVersion
    Write-Host "-------------------------"

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
        Save-ConfigToFileAndResetRepository
        Write-Host "Scanning is complete."
        $NextRunDateTime = (Get-Date).AddSeconds($WaitBetweenScansInSeconds).ToString("o")
        Write-Host "Sleeping for $WaitBetweenScansInSeconds seconds. Next run scheduled for $NextRunDateTime" 
        Write-Host "-------------------------"
        Start-Sleep -s $WaitBetweenScansInSeconds
    }
}

Main
