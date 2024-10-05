class ConversionSettings {
    [int] $WaitBetweenScansInSeconds
    [DirectoryConversionSetting[]] $Directories 
}

class DirectoryConversionSetting {
    [string] $Path
    [string[]] $From
    [string] $To
    [string[]] $Excluded
}