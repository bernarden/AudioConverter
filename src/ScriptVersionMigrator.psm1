using module ".\ConfigRepository.psm1"
using module ".\FFToolsRepository.psm1"

function Move-ScriptToNewVersion {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion
    )

    $ExistingConfig = Get-ExistingConfig
    if ($CurrentVersion -eq $ExistingConfig.Version) {
        Write-Host "No migration is required. Existing version: '$($CurrentVersion)'."
        return
    }

    Write-Host "Migrating from '$($ExistingConfig.Version)'."
    Save-ConfigToFileAndResetRepository

    Write-Host "All migrations are applied. Current version: '$($CurrentVersion)'."
}

Export-ModuleMember -Function Move-ScriptToNewVersion