function Get-ComputerInfo {
    [CmdletBinding()]
    param (
        # Computer name to view
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern( "^((?<prefix>[a-z]{2})(?<number>\d{5}))$" )]
        [string]$ComputerName,

        # SerachBase
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern( "^((ou=(?<OU>\w+))(|,)|(dc=(?<DC>\w+))(|,))+$" )]
        [string]$SearchBase,

        # Test or actually load modules
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [bool]$LoadModules = $true
    )
    
    begin {
        try {
            if ($LoadModules -eq $true) {
                Import-Module -Name ActiveDirectory -ErrorAction Stop
            }
        }
        catch [System.Exception] {
            Write-Host "Could not load Active Directory module. Exiting."
            throw
        }

        ## Create base variables
        $ArrayList = New-Object -TypeName System.Collections.ArrayList
    }
    
    process {
        
    }
    
    end {
        
    }
}


Get-ComputerInfo -ComputerName "ws12345" -SearchBase "ou=Group64,ou=Computers,dc=demo,dc=SS64,dc=com" -LoadModules $false