using module ".\ConfigClass.psm1"

$ConfigFileName = "config.json"

function Initialize-ConfigRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $ConfigDirectory,

        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion
    )

    $script:DefaultConfig = [Config]@{
        CheckedFiles = @()
        Version      = $CurrentVersion
    }

    $script:NewConfig = $script:DefaultConfig;

    $script:ConfigFileFullName = "$ConfigDirectory$ConfigFileName"
    if (!(Test-Path $script:ConfigFileFullName)) {
        $script:ExistingConfig = $script:DefaultConfig 
        $ConfigJson = $script:DefaultConfig | ConvertTo-Json
        New-Item -path $ConfigDirectory -name $ConfigFileName -type "file" -value $ConfigJson > $null
    }
    else {
        $script:ExistingConfig = Get-Content -Path $script:ConfigFileFullName | ConvertFrom-Json
    }
}

function Get-UncheckedFilesAndRefreshConfig {
    Param(
        [Parameter(Mandatory = $true)]
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

function Save-ConfigToFile {
    $NewConfigJson = $script:NewConfig | ConvertTo-Json
    Set-Content -Path $script:ConfigFileFullName -Value $NewConfigJson
}

Export-ModuleMember -Function Initialize-ConfigRepository, Set-FileAsScannedOrFixed, Get-UncheckedFilesAndRefreshConfig, Save-ConfigToFile