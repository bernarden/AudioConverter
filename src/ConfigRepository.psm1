using module ".\ConfigClass.psm1"

$ConfigFileName = "config.json"

function Initialize-ConfigRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $ConfigDirectory,

        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion
    )

    $script:Version = $CurrentVersion
    $script:NewConfig = Get-DefaultConfig
    $script:ConfigFileFullName = Join-Path $ConfigDirectory $ConfigFileName
    if (!(Test-Path $script:ConfigFileFullName)) {
        $script:ExistingConfig = Get-DefaultConfig
        $script:ExistingConfigJson = $script:ExistingConfig | ConvertTo-Json -Compress
        New-Item -path $ConfigDirectory -name $ConfigFileName -type "file" -value $script:ExistingConfigJson > $null
    }
    else {
        $script:ExistingConfigJson = Get-Content -Path $script:ConfigFileFullName
        $script:ExistingConfig = $script:ExistingConfigJson | ConvertFrom-Json
    }
}

function Get-DefaultConfig {
    return [Config]@{
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
    foreach ($CheckedFile in $script:ExistingConfig.CheckedFiles) {
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

    return $FilesToCheck;
}

function Set-FileAsScannedOrFixed {
    Param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    $script:NewConfig.CheckedFiles += [CheckedFile]@{
        FullName         = $File.FullName
        LastWriteTimeUtc = $File.LastWriteTimeUtc
        Length           = $File.Length
    };
}

function Save-ConfigToFileAndResetRepository {
    $NewConfigJson = $script:NewConfig | ConvertTo-Json -Compress
    if (!$script:ExistingConfigJson.Equals($NewConfigJson)) {
        Set-Content -Path $script:ConfigFileFullName -Value $NewConfigJson
        $script:ExistingConfig = $script:NewConfig 
        $script:ExistingConfigJson = $NewConfigJson
    }
    
    $script:NewConfig = Get-DefaultConfig
}

Export-ModuleMember -Function Initialize-ConfigRepository, Set-FileAsScannedOrFixed, Get-UncheckedFilesAndRemoveDeletedFilesFromConfig, Save-ConfigToFileAndResetRepository
