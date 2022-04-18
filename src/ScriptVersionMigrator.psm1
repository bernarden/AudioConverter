using module ".\ConfigRepository.psm1"
using module ".\FFToolsRepository.psm1"

function Move-ScriptToNewVersion {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $CurrentVersion
    )

    $ExistingConfig = Get-ExistingConfig
    if ($CurrentVersion -eq $ExistingConfig.Version) {
        Write-Host "No migration is required. Existing version: $($CurrentVersion)"
        return
    }

    if ($ExistingConfig.Version -eq "1.0.0") {
        Write-Host "Migrating from version: $($ExistingConfig.Version)"
        
        foreach ($CheckedFile in $ExistingConfig.CheckedFiles) {
            if ((Test-Path $CheckedFile.FullName)) {
                $Duration = Get-MediaDuration $CheckedFile.FullName
                $File = $(Get-Item $CheckedFile.FullName)
                Set-FileAsScannedOrConverted $File $Duration
            }
            
        }
        Save-ConfigToFileAndResetRepository
    }

    Write-Host "All migrations are applied. Current version: $($CurrentVersion)"
}

Export-ModuleMember -Function Move-ScriptToNewVersion