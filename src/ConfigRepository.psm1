using module ".\FileConfigClass.psm1"
using module ".\FFToolsRepository.psm1"

$ConfigFileName = "config.json"

function Initialize-ConfigRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $ConfigDirectory,

        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion,

        [Parameter(Mandatory = $true)]
        [string[]] $AudioCodecsToConvert
    )

    $script:Version = $CurrentVersion
    $script:AudioCodecsToConvert = $AudioCodecsToConvert
    $script:NewConfig = Get-DefaultConfig
    $script:ConfigFileFullName = Join-Path $ConfigDirectory $ConfigFileName
    if (!(Test-Path $script:ConfigFileFullName)) {
        $script:ExistingConfig = Get-DefaultConfig
        $script:ExistingConfigJson = $script:ExistingConfig | ConvertTo-Json -Depth 5 -Compress
        New-Item -path $ConfigDirectory -name $ConfigFileName -type "file" -value $script:ExistingConfigJson > $null
    }
    else {
        $script:ExistingConfigJson = Get-Content -Path $script:ConfigFileFullName
        $script:ExistingConfig = $script:ExistingConfigJson | ConvertFrom-Json
    }
}

function Get-DefaultConfig {
    return [FileConfig]@{
        CheckedFiles = @()
        Version      = $script:Version
    }
}

function Get-UncheckedFilesAndRemoveDeletedFilesFromConfig {
    Param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.IO.FileInfo[]] $AllFiles
    )

    $PreviouslyCheckedFilesDictionary = @{ }
    ForEach ($CheckedFile in $script:ExistingConfig.CheckedFiles) {
        $PreviouslyCheckedFilesDictionary[$CheckedFile.FullName] = $CheckedFile
    }

    $FilesToCheck = @();
    ForEach ($File in $AllFiles) {
        $PreviouslyCheckedFile = $PreviouslyCheckedFilesDictionary[$File.FullName];
        if ($PreviouslyCheckedFile -and
            $PreviouslyCheckedFile.LastWriteTimeUtc -eq $File.LastWriteTimeUtc -and
            $PreviouslyCheckedFile.Length -eq $File.Length) {
            $script:NewConfig.CheckedFiles += $PreviouslyCheckedFile
        }
        else {
            $FilesToCheck += $File
        }
    }

    return , $FilesToCheck;
}

function Remove-PreviouslyCheckedFilesFromConfigIfConversionIsRequired {
    ForEach ($CheckedFile in $script:ExistingConfig.CheckedFiles) {
        $IsConversionRequired = Get-IsConversionRequired $CheckedFile.AudioCodecs $script:AudioCodecsToConvert
        if (!$IsConversionRequired) {
            $script:NewConfig.CheckedFiles += $CheckedFile
        }
    }
    
    Save-ConfigToFileAndResetRepository
}

function Set-FileAsScannedOrConverted {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File,

        [Parameter(Mandatory = $true)]
        [string] $Duration,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $AudioCodecs
    )

    $script:NewConfig.CheckedFiles += [CheckedFile]@{
        FullName         = $File.FullName
        LastWriteTimeUtc = $File.LastWriteTimeUtc
        Length           = $File.Length
        Duration         = $Duration
        AudioCodecs      = $AudioCodecs
    };
}

function Save-ConfigToFileAndResetRepository {
    $NewConfigJson = $script:NewConfig | ConvertTo-Json -Depth 5 -Compress
    if (!$script:ExistingConfigJson.Equals($NewConfigJson)) {
        Set-Content -Path $script:ConfigFileFullName -Value $NewConfigJson
        $script:ExistingConfig = $script:NewConfig 
        $script:ExistingConfigJson = $NewConfigJson
    }
    
    $script:NewConfig = Get-DefaultConfig
}

function Get-ExistingConfig {
    return $script:ExistingConfig
}

Export-ModuleMember -Function Initialize-ConfigRepository, Set-FileAsScannedOrConverted, Remove-PreviouslyCheckedFilesFromConfigIfConversionIsRequired, Get-UncheckedFilesAndRemoveDeletedFilesFromConfig, Save-ConfigToFileAndResetRepository, Get-ExistingConfig
