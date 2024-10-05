using module ".\classes\ConversionSettingsClass.psm1"
using module ".\classes\AnalyzedMediaFileClass.psm1"
using module ".\EmailRepository.psm1"
using module ".\FFToolsRepository.psm1"
using module ".\MediaTrackingRepository.psm1"
using module ".\SettingsRepository.psm1"
using module ".\OutputHelper.psm1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-FilesToConvert {
    Param(
        [Parameter()]
        [System.IO.FileInfo[]] $FilesToCheck,

        [Parameter(Mandatory = $true)]
        [DirectoryConversionSetting] $DirectoryConversionSetting
    )   
    Write-Host ("Filtering out files that do not require conversion or excluded." | Add-Timestamp);
    $FilesToConvert = [System.Collections.Concurrent.ConcurrentDictionary[System.IO.FileInfo, AnalyzedMediaFile]]::new()
    $FilesToMarkAsChecked = [System.Collections.Concurrent.ConcurrentDictionary[System.IO.FileInfo, AnalyzedMediaFile]]::new()
    $FilesToCheck | ForEach-Object -ThrottleLimit 2048 -Parallel {
        $FilesToConvert = $using:FilesToConvert
        $FilesToMarkAsChecked = $using:FilesToMarkAsChecked
        $DirectoryConversionSetting = $using:DirectoryConversionSetting

        # Hack to load all modules into new PS run-space state. https://github.com/PowerShell/PowerShell/issues/12240
        $ScriptRoot = $using:PSScriptRoot
        $scriptBody = @"
using module "$ScriptRoot\classes\AnalyzedMediaFileClass.psm1"
using module "$ScriptRoot\FFToolsRepository.psm1"
using module "$ScriptRoot\OutputHelper.psm1"
"@;
        $script = [ScriptBlock]::Create($scriptBody)
        . $script
    
        try {
            $File = $_;
            $AnalyzedMediaFile = Get-AnalyzedMediaFile -File $File -DirectoryConversionSetting $DirectoryConversionSetting

            $NumberOfAudioStreamsToConvert = ($AnalyzedMediaFile.AudioStreams | Where-Object { $_.ShouldBeConverted } | Measure-Object).Count
            if (($NumberOfAudioStreamsToConvert -eq 0) -or $AnalyzedMediaFile.IsFilePathExcluded) {
                if ($FilesToMarkAsChecked.TryAdd($File, $AnalyzedMediaFile) -eq $false) {
                    throw [System.Exception] "Failed to mark file '$($File.Name)' as checked."
                }
            }
            else {
                if ($FilesToConvert.TryAdd($File, $AnalyzedMediaFile) -eq $false) {
                    throw [System.Exception] "Failed to schedule file '$($File.Name)' for conversion."
                }
            }
        }
        catch { 
            Write-Host ("Failed to check if the file requires a conversion: '$File'.`n" + $_.Exception.ToString() | Add-Timestamp);
        }
    }
    
    ForEach ($FileToMarkAsChecked in $FilesToMarkAsChecked.Keys) {
        $AnalyzedMediaFile = $FilesToMarkAsChecked[$FileToMarkAsChecked]
        $OriginalAudioCodecs = @($AnalyzedMediaFile.AudioStreams | Select-Object -ExpandProperty CodecName);
        Set-FileAsScannedOrConverted $FileToMarkAsChecked $AnalyzedMediaFile.Duration $OriginalAudioCodecs $DirectoryConversionSetting
    }

    Write-Host ("Found $($FilesToConvert.Keys.Count) files to convert." | Add-Timestamp);
    return $FilesToConvert
}

function Convert-File {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [AnalyzedMediaFile] $AnalyzedMediaFile,
                
        [Parameter(Mandatory = $true)]
        [DirectoryConversionSetting] $DirectoryConversionSetting
    )

    Write-Host ("-------------------------" | Add-Timestamp);
    Write-Host ("Converting file: $File" | Add-Timestamp);
    $AnalyzedAudioStreams = $AnalyzedMediaFile.AudioStreams
    
    $OriginalFileLength = $File.Length;
    $OriginalFileLastWriteTimeUtc = $File.LastWriteTimeUtc;
    $NewFileName = Join-Path $File.DirectoryName "$($File.BaseName)-1$($File.Extension)"
    $ConversionResult = Convert-AudioStreams -OriginalFile $File -NewFileName $NewFileName -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $DirectoryConversionSetting.To
    if ($ConversionResult.ExitCode) {
        Write-Host ("Failed to convert file: '$File'" | Add-Timestamp);
        Write-Host ($ConversionResult.Output | Add-Timestamp);
        Remove-Item -LiteralPath $NewFileName -Force -ErrorAction Ignore
        Send-TranscodingFailureEmail -File $File -AnalyzedAudioStreams $AnalyzedAudioStreams -AudioCodecDestination $DirectoryConversionSetting.To -Logs $ConversionResult.Output
        Write-Host ("-------------------------" | Add-Timestamp);
        return;
    }
 
    $File.Refresh();
    if ($OriginalFileLength -eq $File.Length -and $OriginalFileLastWriteTimeUtc -eq $File.LastWriteTimeUtc) {
        Remove-Item -LiteralPath $File -Force
        Rename-Item -LiteralPath $NewFileName -NewName $File.Name
        $File.Refresh();
        $AnalyzedMediaFile = Get-AnalyzedMediaFile -File $File -DirectoryConversionSetting $DirectoryConversionSetting
        $NewAudioCodecs = @($AnalyzedMediaFile.AudioStreams | Select-Object -ExpandProperty CodecName);
        Set-FileAsScannedOrConverted $File $AnalyzedMediaFile.Duration $NewAudioCodecs $DirectoryConversionSetting
        Write-Host ("File has been converted." | Add-Timestamp);
        Write-Host ("-------------------------" | Add-Timestamp);
    }
    else { 
        Remove-Item -LiteralPath $NewFileName -Force
        Write-Host ("File has been changed during conversion. Try again next time." | Add-Timestamp);
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
    Write-Host ("Found $($AllUncheckedFiles.Length) files to check." | Add-Timestamp);
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
    $CurrentScriptVersion = "2.2.0"
    New-DirectoryIfDoesNotExist -DirectoryPath $ConfigDirectory
    
    Initialize-SettingsRepository -ConfigDirectory $ConfigDirectory 
    
    $ConversionSettings = Get-ConversionSettings
    Initialize-MediaTrackingRepository -ConfigDirectory $ConfigDirectory -CurrentVersion $CurrentScriptVersion -ConversionSettings $ConversionSettings

    $EmailSettings = Get-EmailSettings
    Initialize-EmailRepository -EmailSettings $EmailSettings

    while ($true) {
        Write-Host ("-------------------------" | Add-Timestamp);
        ForEach ($DirectoryConversionSetting in $ConversionSettings.Directories) {
            $FilesToCheck = Get-FilesToCheck -DirectoryPath $DirectoryConversionSetting.Path
            if ($FilesToCheck.Length -eq 0) {
                Write-Host ("-------------------------" | Add-Timestamp);
                continue;
            }
        
            $FilesToConvertDict = Get-FilesToConvert -FilesToCheck $FilesToCheck -DirectoryConversionSetting $DirectoryConversionSetting
            if ($FilesToConvertDict.Count -eq 0) {
                Write-Host ("-------------------------" | Add-Timestamp);
                continue;
            }

            ForEach ($FileToConvert in $FilesToConvertDict.Keys) {
                try {
                    $AnalyzedMediaFile = $FilesToConvertDict[$FileToConvert]
                    Convert-File -File $FileToConvert -AnalyzedMediaFile $AnalyzedMediaFile -DirectoryConversionSetting $DirectoryConversionSetting
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
        Start-Sleep -s $ConversionSettings.WaitBetweenScansInSeconds
    }
}

Main
