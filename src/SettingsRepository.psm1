using module ".\classes\ConversionSettingsClass.psm1"
using module ".\classes\EmailSettingsClass.psm1"
using module ".\EnvVariableHelper.psm1"
using module ".\FFToolsRepository.psm1"
using module ".\OutputHelper.psm1"

function Initialize-SettingsRepository {
    Param(
        [Parameter(Mandatory = $true)]
        [String] $ConfigDirectory
    )
    
    $SettingsFileName = "settings.yaml"
    $SettingsFilePath = Join-Path $ConfigDirectory $SettingsFileName
    If (!(Test-Path $SettingsFilePath)) {
        $SettingsExampleFileName = "settings-example.yaml"
        $SettingsExampleFilePath = Join-Path $ConfigDirectory $SettingsExampleFileName
        If (!(Test-Path $SettingsExampleFilePath)) {
            Copy-Item $SettingsExampleFileName -Destination $ConfigDirectory
        }
        Write-Host ("Please create a settings file at the following path: '$SettingsFilePath'." | Add-Timestamp);
        Write-Host ("Exiting." | Add-Timestamp);
        exit;
    }

    $script:Settings = Get-Content -Path $SettingsFilePath | ConvertFrom-Yaml

    # Email Settings
    $EmailSettingsTemp = $script:Settings.Settings.Email
    $script:EmailSettings = [EmailSettings]@{
        Host                 = $EmailSettingsTemp.Host
        Port                 = $EmailSettingsTemp.Port
        To                   = $EmailSettingsTemp.To
        Sender               = $EmailSettingsTemp.Sender
        Username             = $EmailSettingsTemp.Username
        Password             = Get-StringEnvVariable -Name "EMAIL_PASSWORD" -DefaultValue $EmailSettingsTemp.Password
        SendTestEmailOnStart = $EmailSettingsTemp.Send_test_email_on_start
    };

    # Conversion Settings
    $ConversionSettingsTemp = $script:Settings.Settings.Conversion
    $Directories = @()
    ForEach ($Directory in $ConversionSettingsTemp.Directories) {
        $DirectoryConversionSetting = [DirectoryConversionSetting]@{
            Path     = $Directory.Path
            From     = $Directory.From
            To       = $Directory.To
            Excluded = $Directory.Excluded
        };

        if ($Directory.From -contains $Directory.To) {
            Write-Host ("'From' setting value ('$($Directory.From -join ", ")') contains 'To' setting value ('$($Directory.To)') and therefore will cause infinite loop." | Add-Timestamp);
            Write-Host ("Exiting." | Add-Timestamp);
            exit;
        }

        $Directories += $DirectoryConversionSetting
    }
    $script:ConversionSettings = [ConversionSettings]@{
        WaitBetweenScansInSeconds = $ConversionSettingsTemp.Wait_between_scans_in_seconds
        Directories               = $Directories
    };
}

function Get-EmailSettings {
    [OutputType([EmailSettings])]
    param ()

    return $script:EmailSettings
}

function Get-ConversionSettings {
    [OutputType([ConversionSettings])]
    param ()
    
    return $script:ConversionSettings
}

Export-ModuleMember -Function Initialize-SettingsRepository, Get-EmailSettings, Get-ConversionSettings
