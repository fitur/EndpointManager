function Get-ComputerInfo {
    [CmdletBinding()]
    param (
        # Computer name to view
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern( "^((?<prefix>[a-z]{2})(?<number>\d{5}))$" )]
        [string]$ComputerName,

        # SerachBase
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern( "^((ou=(?<OU>\w+))(|,)|(dc=(?<DC>\w+))(|,))+$" )]
        [string]$SearchBase,

        # Test or actually load modules
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet( $true, $false )]
        [bool]$LoadModules = $true
    )
    
    begin {

        ## Load modules
        try {
            if ($LoadModules -eq $true) {
                Import-Module -Name ActiveDirectory -ErrorAction Stop
                Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
            }
        }
        catch [System.Exception] {
            Write-Host "Could not load required modules. Exiting."
            throw
        }

        ## Set location
        try {
            $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
            $OldLocation = Get-Location -ErrorAction Stop
            Set-location $SiteCode":" -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Host "Unable to set location to CM drive. Exiting."
        }

        ## Create base variables
        # $ArrayList = New-Object -TypeName System.Collections.ArrayList
    }
    
    process {

        ## Get AD information
        if ((Get-Module -Name ActiveDirectory -ErrorAction SilentlyContinue) -ne $null) {
            $ADComputer = Get-ADComputer -Identity $ComputerName -Properties * -ErrorAction SilentlyContinue
        }

        # Get CM information
        if ((Get-Module -Name ConfigurationManager -ErrorAction SilentlyContinue) -ne $null) {
            $CMComputer = Get-CMDevice -Name $ComputerName -ErrorAction SilentlyContinue
            $CMUDA = Get-CMUserDeviceAffinity -DeviceName $CMComputer.Name -ErrorAction SilentlyContinue | Sort-Object -Descending CreationTime | Select-Object -First 1
        }

        $Computer = [PSCustomObject]@{
            ADName = $ADComputer.Name
            ADUser = $ADComputer.ManagedBy -replace "(CN=(?<CN>\w+)).*",'$2'
            CMName = $CMComputer.Name
            CMUser = $CMUDA.UniqueUserName | Split-Path -Leaf -ErrorAction SilentlyContinue
        }
    }
    
    end {

        ## Set location
        Set-Location $OldLocation -ErrorAction Stop
        return $Computer
    }
}


$test = Get-ComputerInfo -ComputerName "ws07710" -LoadModules $true
