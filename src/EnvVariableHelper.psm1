function Get-IntEnvVariable {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [int] $DefaultValue
    )

    $Argument = (Get-ChildItem -Path "Env:$Name" -ErrorAction SilentlyContinue).Value;
    if (!$Argument -and $PSBoundParameters.ContainsKey("DefaultValue")) {
        return $DefaultValue
    }
    return [int]$Argument;
}

function Get-StringEnvVariable {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [string] $DefaultValue
    )

    $Argument = (Get-ChildItem -Path "Env:$Name" -ErrorAction SilentlyContinue).Value;
    if (!$Argument -and $PSBoundParameters.ContainsKey("DefaultValue")) {
        return $DefaultValue
    }
    return [string]$Argument;
}

function Get-BooleanEnvVariable {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [boolean] $DefaultValue
    )

    $Argument = (Get-ChildItem -Path "Env:$Name" -ErrorAction SilentlyContinue).Value;
    if (!$Argument -and $PSBoundParameters.ContainsKey("DefaultValue")) {
        return $DefaultValue
    }
    return [System.Convert]::ToBoolean($Argument);
}

function Get-StringArrayEnvVariable {
    Param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [string[]] $DefaultValue
    )

    $Argument = (Get-ChildItem -Path "Env:$Name" -ErrorAction SilentlyContinue).Value;
    if (!$Argument) {
        if ($PSBoundParameters.ContainsKey("DefaultValue")) {
            return $DefaultValue
        }
        return @();
    }

    return [regex]::split($Argument, '[,\s]+');
}

Export-ModuleMember -Function Get-IntEnvVariable, Get-StringEnvVariable, Get-BooleanEnvVariable, Get-StringArrayEnvVariable
