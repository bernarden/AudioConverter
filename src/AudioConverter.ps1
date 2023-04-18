using module ".\classes\ConversionSettingsClass.psm1"
using module ".\EmailRepository.psm1"
using module ".\FFToolsRepository.psm1"
using module ".\MediaTrackingRepository.psm1"
using module ".\SettingsRepository.psm1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,
        
        [Parameter(Mandatory = $true)]
        [DirectoryConversionSetting] $DirectoryConversionSetting
    )

    Write-Host "-------------------------"
    Write-Host "Checking file: $File"
    $AnalyzedAudioStreams = Get-AnalyzedAudioStreams -File $File -AudioCodecsToConvert $DirectoryConversionSetting.From
    if ($null -eq $AnalyzedAudioStreams) {
        Set-FileAsScannedOrConverted $File "N/A" @() $DirectoryConversionSetting
        Write-Host "Not a media file. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }
    
    if ($AnalyzedAudioStreams.Length -eq 0) {
        $Duration = Get-MediaDuration $File
        Set-FileAsScannedOrConverted $File $Duration @() $DirectoryConversionSetting
        Write-Host "No audio found. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }

    $OriginalAudioCodecs = @($AnalyzedAudioStreams | Select-Object -ExpandProperty CodecName);
    Write-Host "Found audio codecs: '$($OriginalAudioCodecs -join ", ")'"
    if (($AnalyzedAudioStreams | Where-Object { $_.ShouldBeConverted } | Measure-Object).Count -eq 0) {
        $Duration = Get-MediaDuration $File
        Set-FileAsScannedOrConverted $File $Duration $OriginalAudioCodecs $DirectoryConversionSetting
        Write-Host "No conversion needed. Skipping file: '$File'"
        Write-Host "-------------------------"
        continue;
    }

    Write-Host "Trying to automatically convert: '$File'"
    $OriginalFileLength = $File.Length;
    $OriginalFileLastWriteTimeUtc = $File.LastWriteTimeUtc;
    $NewFileName = Join-Path $File.DirectoryName "$($File.BaseName)-1$($File.Extension)"
    $ConversionResult = Convert-AudioStreams -OriginalFile $File -NewFileName $NewFileName -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $DirectoryConversionSetting.To
    if ($ConversionResult.ExitCode) {
        Write-Host "Failed to automatically convert the file: '$File'" 
        Write-Host $ConversionResult.Output
        Remove-Item -Path $NewFileName -Force -ErrorAction Ignore
        Send-TranscodingFailureEmail -File $File -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $DirectoryConversionSetting.To -Logs $ConversionResult.Output
        Write-Host "-------------------------"
        continue;
    }
 
    $File.Refresh();
    if ($OriginalFileLength -eq $File.Length -and $OriginalFileLastWriteTimeUtc -eq $File.LastWriteTimeUtc) {
        Remove-Item -Path $File -Force
        Rename-Item -Path $NewFileName -NewName $File.Name
        $File.Refresh();
        $Duration = Get-MediaDuration $File
        $NewAnalyzedAudioStreams = Get-AnalyzedAudioStreams -File $File -AudioCodecsToConvert $DirectoryConversionSetting.From
        $NewAudioCodecs = @($NewAnalyzedAudioStreams | Select-Object -ExpandProperty CodecName);
        Set-FileAsScannedOrConverted $File $Duration $NewAudioCodecs $DirectoryConversionSetting
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
    Param(
        [Parameter(Mandatory = $true)]
        [string] $DirectoryPath
    )

    Write-Host "Scanning '$DirectoryPath' for media files.";
    $AllFiles = @(Get-ChildItem $DirectoryPath -Include "*.*" -Recurse -File);
    $AllUncheckedFiles = Get-UncheckedFilesAndRemoveDeletedFilesFromMediaTrackingFile $AllFiles $DirectoryPath
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

    # Install required modules.
    $ModuleToInstall = "powershell-yaml"
    if (Get-Module -ListAvailable -Name $ModuleToInstall) {
        Write-Host "Module $ModuleToInstall already installed."
    } 
    else {
        Write-Host "Installing module $ModuleToInstall."
        Install-Module -Name $ModuleToInstall -Force
        Write-Host "Importing module $ModuleToInstall."
        Import-Module -Name $ModuleToInstall
    }

    $ConfigDirectory = "config"
    $CurrentScriptVersion = "2.0.0"
    New-DirectoryIfDoesNotExist -DirectoryPath $ConfigDirectory
    
    Initialize-SettingsRepository -ConfigDirectory $ConfigDirectory 
    
    $ConversionSettings = Get-ConversionSettings
    Initialize-MediaTrackingRepository -ConfigDirectory $ConfigDirectory -CurrentVersion $CurrentScriptVersion -ConversionSettings $ConversionSettings

    $EmailSettings = Get-EmailSettings
    Initialize-EmailRepository -EmailSettings $EmailSettings
    Write-Host "-------------------------"

    while ($true) {
        ForEach ($DirectoryConversionSetting in $ConversionSettings.Directories) {
            $FilesToCheck = Get-FilesToCheck -DirectoryPath $DirectoryConversionSetting.Path
            ForEach ($File in $FilesToCheck) {
                try {
                    Convert-File -File $File -DirectoryConversionSetting $DirectoryConversionSetting
                }
                catch { 
                    Write-Host $_.Exception
                }
            }
        }
       
        Save-MediaTrackingFileAndResetRepository
        Write-Host "Scanning is complete."
        $NextRunDateTime = (Get-Date).AddSeconds($ConversionSettings.WaitBetweenScansInSeconds).ToString("o")
        Write-Host "Sleeping for $($ConversionSettings.WaitBetweenScansInSeconds) seconds. Next run scheduled for $NextRunDateTime" 
        Write-Host "-------------------------"
        Start-Sleep -s $ConversionSettings.WaitBetweenScansInSeconds
    }
}

Main
