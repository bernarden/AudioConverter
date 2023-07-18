using module ".\classes\ConversionSettingsClass.psm1"
using module ".\EmailRepository.psm1"
using module ".\FFToolsRepository.psm1"
using module ".\MediaTrackingRepository.psm1"
using module ".\SettingsRepository.psm1"
using module ".\OutputHelper.psm1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,
        
        [Parameter(Mandatory = $true)]
        [DirectoryConversionSetting] $DirectoryConversionSetting
    )

    Write-Host ("-------------------------" | Add-Timestamp);
    Write-Host ("Checking file: $File" | Add-Timestamp);
    $AnalyzedAudioStreams = Get-AnalyzedAudioStreams -File $File -AudioCodecsToConvert $DirectoryConversionSetting.From
    if ($null -eq $AnalyzedAudioStreams) {
        Set-FileAsScannedOrConverted $File "N/A" @() $DirectoryConversionSetting
        Write-Host ("Not a media file. Skipping file: '$File'" | Add-Timestamp);
        Write-Host ("-------------------------" | Add-Timestamp);
        continue;
    }
    
    if ($AnalyzedAudioStreams.Length -eq 0) {
        $Duration = Get-MediaDuration $File
        Set-FileAsScannedOrConverted $File $Duration @() $DirectoryConversionSetting
        Write-Host ("No audio found. Skipping file: '$File'" | Add-Timestamp);
        Write-Host ("-------------------------" | Add-Timestamp);
        continue;
    }

    $OriginalAudioCodecs = @($AnalyzedAudioStreams | Select-Object -ExpandProperty CodecName);
    Write-Host ("Found audio codecs: '$($OriginalAudioCodecs -join ", ")'" | Add-Timestamp);
    if (($AnalyzedAudioStreams | Where-Object { $_.ShouldBeConverted } | Measure-Object).Count -eq 0) {
        $Duration = Get-MediaDuration $File
        Set-FileAsScannedOrConverted $File $Duration $OriginalAudioCodecs $DirectoryConversionSetting
        Write-Host ("No conversion needed. Skipping file: '$File'" | Add-Timestamp);
        Write-Host ( "-------------------------" | Add-Timestamp);
        continue;
    }

    Write-Host ("Trying to automatically convert: '$File'" | Add-Timestamp);
    $OriginalFileLength = $File.Length;
    $OriginalFileLastWriteTimeUtc = $File.LastWriteTimeUtc;
    $NewFileName = Join-Path $File.DirectoryName "$($File.BaseName)-1$($File.Extension)"
    $ConversionResult = Convert-AudioStreams -OriginalFile $File -NewFileName $NewFileName -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $DirectoryConversionSetting.To
    if ($ConversionResult.ExitCode) {
        Write-Host ("Failed to automatically convert the file: '$File'" | Add-Timestamp);
        Write-Host ($ConversionResult.Output | Add-Timestamp);
        Remove-Item -Path $NewFileName -Force -ErrorAction Ignore
        Send-TranscodingFailureEmail -File $File -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $DirectoryConversionSetting.To -Logs $ConversionResult.Output
        Write-Host ("-------------------------" | Add-Timestamp);
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
        Write-Host ("File has been converted." | Add-Timestamp);
        Write-Host ("-------------------------" | Add-Timestamp);
    }
    else { 
        Remove-Item -Path $NewFileName -Force
        Write-Host ("File has been changed during transcoding. Try again next time." | Add-Timestamp);
        Write-Host( "-------------------------" | Add-Timestamp);
    }
}

function Get-FilesToCheck {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $DirectoryPath
    )

    Write-Host ("Scanning '$DirectoryPath' for media files." | Add-Timestamp);
    $AllFiles = @(Get-ChildItem $DirectoryPath -Recurse -File);
    $AllUncheckedFiles = Get-UncheckedFilesAndRemoveDeletedFilesFromMediaTrackingFile $AllFiles $DirectoryPath
    Write-Host ("Found $($AllUncheckedFiles.length) files to process." | Add-Timestamp);
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
    Write-Host ("Starting up." | Add-Timestamp);

    # Install required modules.
    $ModuleToInstall = "powershell-yaml"
    if (Get-Module -ListAvailable -Name $ModuleToInstall) {
        Write-Host ("Module $ModuleToInstall already installed." | Add-Timestamp);
    } 
    else {
        Write-Host ("Installing module $ModuleToInstall." | Add-Timestamp);
        Install-Module -Name $ModuleToInstall -Force -Scope CurrentUser
        Write-Host ("Importing module $ModuleToInstall." | Add-Timestamp);
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
    Write-Host ("-------------------------" | Add-Timestamp);

    while ($true) {
        ForEach ($DirectoryConversionSetting in $ConversionSettings.Directories) {
            $FilesToCheck = Get-FilesToCheck -DirectoryPath $DirectoryConversionSetting.Path
            ForEach ($File in $FilesToCheck) {
                try {
                    Convert-File -File $File -DirectoryConversionSetting $DirectoryConversionSetting
                }
                catch { 
                    Write-Host ($_.Exception | Add-Timestamp);
                }
            }
        }
       
        Save-MediaTrackingFileAndResetRepository
        Write-Host ("Scanning is complete." | Add-Timestamp);
        $NextRunDateTime = (Get-Date).AddSeconds($ConversionSettings.WaitBetweenScansInSeconds).ToString("s")
        Write-Host ("Sleeping for $($ConversionSettings.WaitBetweenScansInSeconds) seconds. Next run scheduled for $NextRunDateTime" | Add-Timestamp);
        Write-Host ("-------------------------" | Add-Timestamp);
        Start-Sleep -s $ConversionSettings.WaitBetweenScansInSeconds
    }
}

Main
