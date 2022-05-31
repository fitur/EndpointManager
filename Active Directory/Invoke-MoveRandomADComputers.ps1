function MoveRandom {
    param (
        # AD computer array
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $ADComputers,

        # Base OU
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $BaseOU,

        # New OU
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        $NewOU,

        # Number of items
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        $Count = 15
    )

    begin {
        $ADComputersToMove = New-Object -TypeName System.Collections.ArrayList
    }

    process {
        # Get 10 random objects
        for ($i = 0; $i -lt $Count; $i++) {
            $Random = Get-Random -InputObject $ADComputers
            [void]$ADComputersToMove.Add($Random)
        }
        
        # Move objects to new OU
        foreach ($ADComputer in $ADComputersToMove) {
            Move-ADObject -Identity $ADComputer.ObjectGuid -TargetPath $NewOU -Verbose
        }
    }

    end {
        $ADComputersToMove | Select-Object Name | Out-GridView
    }
}

## Test
$d = [DateTime]::Today.AddDays(-30)
$ADComputers = Get-ADComputer -Filter { (PasswordLastSet -ge $d) -and (OperatingSystem -eq "Windows 10 Enterprise") } -SearchBase $BaseOU -Properties *

