using module ".\AnalyzedAudioStream.psm1"

$ConfigFileName = "config.json"

function Initialize-ConfigRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $ConfigDirectory,

        [Parameter(Mandatory = $true)]
        [string] $CurrentVersion
    )

    $script:ConfigFileFullPath = "$ConfigDirectory$ConfigFileName"
    if (!(Test-Path $script:ConfigFileFullPath)) {
        $DefaultValue = "{""CheckedLocations"": [],""Version"": ""$CurrentVersion""}";
        $script:Config = $DefaultValue | ConvertFrom-Json
        New-Item -path $ConfigDirectory -name $ConfigFileName -type "file" -value $DefaultValue > $null
    }
    else {
        $script:Config = Get-Content -Path $script:ConfigFileFullPath | ConvertFrom-Json
    }
}

Export-ModuleMember -Function Initialize-ConfigRepository