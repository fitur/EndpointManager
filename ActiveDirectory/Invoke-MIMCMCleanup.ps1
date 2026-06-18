[CmdletBinding()]
param (
    [Parameter(mandatory=$true, HelpMessage="Specify an Active Directory OU to scan.")]
    [ValidateNotNullOrEmpty()]
    [string]$OU,

    [Parameter(mandatory=$true, HelpMessage="Specify a Configuration Manager site server.")]
    [ValidateNotNullOrEmpty()]
    [string]$CMServer,

    [Parameter(mandatory=$true, HelpMessage="Specify a Configuration Manager site code.")]
    [ValidateNotNullOrEmpty()]
    [string]$CMSiteCode,

    [Parameter(mandatory=$false, HelpMessage="Specify an amount of days to use as a search interval.")]
    [ValidateNotNullOrEmpty()]
    [int]$DateInterval = 31,

    [Parameter(mandatory=$false, HelpMessage="Run a test (True/False).")]
    [ValidateNotNullOrEmpty()]
    $DryRun = $true
)

begin {
    # Start logging
    Start-Transcript -Path (Join-Path -Path $env:Temp -ChildPath "Invoke-MIMCMCleanup-$(Get-Date -Format MMMM).log") -Append -ErrorAction Stop

    # Import Active Directory module
    try {
        Import-Module -Name ActiveDirectory -Force -ErrorAction Stop
    }
    catch [System.IO.FileNotFoundException] {
        Write-Error "Could not load Active Directory module. Terminating."
        # Write-LogEntry -Value "Could not load Active Directory module. Terminating." -Severity 3
        exit 1
    }
    
    # Identify specified OU
    try {
        [void](Get-ADOrganizationalUnit -Identity $OU -ErrorAction Stop)
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Error "Could not find Active Directory OU. Terminating."
        # Write-LogEntry -Value "Could not find Active Directory OU. Terminating." -Severity 3
        exit 1
    }
    
    # Connect to Configuration Manager server
    try {
        $script:CimParam = @{
            CimSession = New-CimSession -ComputerName $CMServer -ErrorAction Stop
            Namespace = 'root/sms/site_{0}' -f $CMSiteCode
        }
    }
    catch [Microsoft.Management.Infrastructure.CimException] {
        Write-Error "Could not connect to Configuration Manager environment."
        # Write-LogEntry -Value "Could not connect to Configuration Manager environment." -Severity 3
        exit 1
    }
}

process {
    Get-ADComputer -Filter * -SearchBase $OU -Properties Enabled, whenChanged, Description | Where-Object { ($_.Enabled -ne $true) -and ($_.whenChanged -gt (Get-Date).AddDays(-$DateInterval)) -and ($_.Description -eq "Deprovisioned") } | ForEach-Object {
        # Remove Active Directory computer object
        Write-Output "Attempting to remove $($_.Name) from Active Directory."
        # Write-LogEntry -Value "Attempting to remove $($_.Name) from Active Directory." -Severity 1

        try {
            Get-ADComputer -Identity $_.Name | Where-Object {$_.DistinguishedName -match $OU} | Remove-ADObject -Recursive -Verbose -WhatIf:$DryRun -Confirm:$DryRun -ErrorAction Stop
        }
        catch {
            Write-Error "Could not remove Active Diretory computer object: $($_.Name)."
            # Write-LogEntry -Value "Could not remove Active Diretory computer object: $($_.Name)." -Severity 3
        }

        # Remove Configuration Manager computer object
        if ($null -ne ($CMResource = Get-CimInstance @CimParam SMS_R_SYSTEM -Filter ('Name = "{0}"' -f $_.Name) -ErrorAction Stop)) {
            Write-Output "Attempting to remove $($_.Name) from Configuration Manager environment."
            try {
                $CMResource | Remove-CimInstance -WhatIf:$DryRun -ErrorAction Stop
            }
            catch {
                Write-Error "Could not remove Configuration Manager computer object: $($_.Name)."
                # Write-LogEntry -Value "Could not remove Configuration Manager computer object: $($_.Name)." -Severity 3
            }
        } else {
            Write-Output "$($_.Name) not found in Configuration Manager database."
            # Write-LogEntry -Value "$($_.Name) not found in Configuration Manager database." -Severity 1
        }
        
        Write-Output "--------"
        # Write-LogEntry -Value "--------" -Severity 1
        # Wait-Event -Timeout 0.7
    }
}
end {
    Stop-Transcript -ErrorAction SilentlyContinue
}