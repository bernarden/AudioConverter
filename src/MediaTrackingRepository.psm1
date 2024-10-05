using module ".\classes\ConversionSettingsClass.psm1"
using module ".\classes\MediaTrackingClass.psm1"
using module ".\FFToolsRepository.psm1"
using module ".\OutputHelper.psm1"

function Initialize-MediaTrackingRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $ConfigDirectory,

        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion,

        [Parameter(Mandatory = $true)]
        [ConversionSettings] $ConversionSettings
    )

    $MediaTrackingFileName = "media_tracking.json"
    $script:ConversionSettings = $ConversionSettings

    $MediaTrackingFileFullName = Join-Path $ConfigDirectory $MediaTrackingFileName
    if (!(Test-Path $MediaTrackingFileFullName)) {
        $NewMediaTracking = Get-DefaultMediaTracking -CurrentVersion $CurrentVersion -ConversionSettings $ConversionSettings
        $ExistingMediaTracking = Get-DefaultMediaTracking -CurrentVersion $CurrentVersion -ConversionSettings $ConversionSettings
        $script:State = [PSCustomObject]@{
            FilePath       = $MediaTrackingFileFullName
            CurrentVersion = $CurrentVersion
            New            = $NewMediaTracking
            Existing       = $ExistingMediaTracking
            ExistingJson   = $ExistingMediaTracking | ConvertTo-Json -Depth 10 -Compress
        }
        New-Item -Path $ConfigDirectory -name $MediaTrackingFileName -type "file" -value $script:State.ExistingJson > $null
    }
    else {
        $script:State = Get-MigratedMediaTrackingState -MediaTrackingFileFullName $MediaTrackingFileFullName -CurrentVersion $CurrentVersion -ConversionSettings $ConversionSettings
        Remove-TrackedMediaFilesThatRequireConversion -ConversionSettings $ConversionSettings
    }
}

function Get-DefaultMediaTracking {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion,

        [Parameter(Mandatory = $true)]
        [ConversionSettings] $ConversionSettings
    )

    $CheckedFiles = @{}
    ForEach ($Directory in $ConversionSettings.Directories) {
        $CheckedFiles[$Directory.Path] = @()
    }

    $MediaTracking = [MediaTracking]@{
        CheckedFiles = $CheckedFiles
        Version      = $CurrentVersion
    }
    return $MediaTracking
}

function Get-MigratedMediaTrackingState {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $MediaTrackingFileFullName,

        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion,

        [Parameter(Mandatory = $true)]
        [ConversionSettings] $ConversionSettings
    )

    $ExistingMediaTrackingJson = Get-Content -Path $MediaTrackingFileFullName
    $ExistingMediaTracking = $ExistingMediaTrackingJson | ConvertFrom-Json
    $NewMediaTracking = Get-DefaultMediaTracking -CurrentVersion $CurrentVersion -ConversionSettings $ConversionSettings

    if ($CurrentVersion -eq $ExistingMediaTracking.Version) {
        Write-Host ("No migration is required. Existing version: '$($CurrentVersion)'." | Add-Timestamp);

        # Map json from PSCustomObject to MediaTracking class for consistency.
        $CheckedFiles = @{}
        $ExistingMediaTracking.CheckedFiles.PSObject.Properties | ForEach-Object {
            $CheckedFiles[$_.Name] = $_.Value
        }
        ForEach ($Directory in $ConversionSettings.Directories) {
            if (!$CheckedFiles.ContainsKey($Directory.Path)) {
                $CheckedFiles[$Directory.Path] = @()
            }
        }

        $ExistingMediaTracking = [MediaTracking]@{
            CheckedFiles = $CheckedFiles
            Version      = $CurrentVersion
        }
        return [PSCustomObject]@{
            FilePath       = $MediaTrackingFileFullName
            CurrentVersion = $CurrentVersion
            New            = $NewMediaTracking
            Existing       = $ExistingMediaTracking
            ExistingJson   = $ExistingMediaTrackingJson
        }
    }

    Write-Host ("Migrating from '$($ExistingMediaTracking.Version)'." | Add-Timestamp);
    # Complete reset of the media tracking file.
    $ExistingMediaTracking = Get-DefaultMediaTracking -CurrentVersion $CurrentVersion -ConversionSettings $ConversionSettings
    Set-Content -Path $MediaTrackingFileFullName -Value $ExistingMediaTrackingJson
    Write-Host ("All migrations are applied. Current version: '$($CurrentVersion)'." | Add-Timestamp);
    return [PSCustomObject]@{
        FilePath       = $MediaTrackingFileFullName
        CurrentVersion = $CurrentVersion
        New            = $NewMediaTracking
        Existing       = $ExistingMediaTracking
        ExistingJson   = $ExistingMediaTracking | ConvertTo-Json -Depth 10 -Compress
    }
}

function Get-UncheckedFilesAndRemoveDeletedFilesFromMediaTrackingFile {
    Param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]] $AllFiles,

        [Parameter(Mandatory = $true)]
        [string] $DirectoryPath
    )

    if (!$script:State.Existing.CheckedFiles.ContainsKey($DirectoryPath)) {
        return , $AllFiles;
    }

    $PreviouslyCheckedFilesDictionary = @{ }
    ForEach ($CheckedFile in $script:State.Existing.CheckedFiles[$DirectoryPath]) {
        $PreviouslyCheckedFilesDictionary[$CheckedFile.FullName] = $CheckedFile
    }

    $FilesToCheck = @();
    ForEach ($File in $AllFiles) {
        $PreviouslyCheckedFile = $PreviouslyCheckedFilesDictionary[$File.FullName];
        if ($PreviouslyCheckedFile -and
            $PreviouslyCheckedFile.LastWriteTimeUtc -eq $File.LastWriteTimeUtc -and
            $PreviouslyCheckedFile.Length -eq $File.Length) {
            # Start setting up New media tracking state for the final save after all checks/conversions are done.
            $script:State.New.CheckedFiles[$DirectoryPath] += $PreviouslyCheckedFile
        }
        else {
            $FilesToCheck += $File
        }
    }
    
    return , $FilesToCheck;
}

function Remove-TrackedMediaFilesThatRequireConversion {
    Param(
        [Parameter(Mandatory = $true)]
        [ConversionSettings] $ConversionSettings
    )

    Write-Host ("Checking if any previously tracked files require a conversion." | Add-Timestamp);
    ForEach ($DirectoryCheckedFiles in $script:State.Existing.CheckedFiles.GetEnumerator()) {
        $MatchingSetting = $ConversionSettings.Directories | Where-Object { $_.Path -eq $DirectoryCheckedFiles.Name }
        if (!$MatchingSetting) { continue; }
        
        ForEach ($CheckedFile in $DirectoryCheckedFiles.Value) {
            $IsFilePathExcluded = Get-IsFilePathExcluded -FileFullName $CheckedFile.FullName -DirectoryConversionSetting $MatchingSetting
            $IsConversionRequired = Get-IsConversionRequired $CheckedFile.AudioCodecs $MatchingSetting.From
            if ($IsFilePathExcluded -or !$IsConversionRequired) {
                $script:State.New.CheckedFiles[$DirectoryCheckedFiles.Name] += $CheckedFile
            }
        }      
    }
    
    Save-MediaTrackingFileAndResetRepository
}

function Set-FileAsScannedOrConverted {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string] $Duration,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $AudioCodecs,

        [Parameter(Mandatory = $true)]
        [DirectoryConversionSetting] $DirectoryConversionSetting
    )

    $script:State.New.CheckedFiles[$DirectoryConversionSetting.Path] += [CheckedFile]@{
        FullName         = $File.FullName
        LastWriteTimeUtc = $File.LastWriteTimeUtc
        Length           = $File.Length
        Duration         = $Duration
        AudioCodecs      = $AudioCodecs
    };
}

function Save-MediaTrackingFileAndResetRepository {
    $NewJson = $script:State.New | ConvertTo-Json -Depth 10 -Compress
    if (!$script:State.ExistingJson.Equals($NewJson)) {
        Set-Content -Path $script:State.FilePath -Value $NewJson
        $script:State.Existing = $script:State.New
        $script:State.ExistingJson = $NewJson
    }
    
    $script:State.New = Get-DefaultMediaTracking -CurrentVersion $script:State.CurrentVersion -ConversionSettings $script:ConversionSettings
}

Export-ModuleMember -Function `
    Initialize-MediaTrackingRepository, `
    Set-FileAsScannedOrConverted, `
    Get-UncheckedFilesAndRemoveDeletedFilesFromMediaTrackingFile, `
    Save-MediaTrackingFileAndResetRepository
