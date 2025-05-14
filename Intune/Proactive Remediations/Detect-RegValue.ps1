<#

.SYNOPSIS
    PowerShell script detect a registry key with a specific value.

.EXAMPLE
    .\Detect-RegValue.ps1

.DESCRIPTION
    This Powershell script detects if a specific registry key exists and if its value matches the expected value.
    If the value does not match, it indicates that remediation is required. The script will output a message indicating whether remediation is required.
    
.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2025-05-14
    Last Updated:   2025-05-14
    Author:         Peter Olausson
    Contact:        admin@fitur.se

#>

[CmdletBinding()]

Param (

)

# Set the registry parameters
$RegPath = "HKCU:\Software\CSI Helsinki Oy\CSI Lawyer\Databases\CSILawyer_Setterwalls_PRODUCTION"
$RegName = "ConnectionString"
$RegData = "Rb/cVDfW5FSwX9ipWDnxPT1xbAGkfjLex0COr1BJ5D/00CWGoKjCNt8WdlY8D3RDTHZv2k02AaEbrRlEsfqyIZcCSiB6qRPqnl58HWQo4DSSH9wkU7UI3rn63di7NsqzdGFq6XRQEv+X4Febs+XDbjIXm3jBwV+cjhFGGlz9ORlUQBLs0vX4EBg5i5GeTQeM5uwCHut83wXQvQCavWiHkSzo16hAID855WTN2ZtPPJlc4N7EdIJmdUc29eseQAR1jNW9J+i/6MciV12G83uB9P/sNju/0vVcxCxRqJOv/tKyJ6XLbAQs518zQwvn0vtidw2qR10rfz/PQy9U3APaYzkso38lpRKCJTbcoVq56a2Nr5lu5Qqc+NJ72YjQjlx2"

try {
    
    [string]$RegValue = Get-ItemPropertyValue $RegPath -Name $RegName -ErrorAction Stop

    if ($RegData -eq $RegValue) {

        # If the registry key exists and the value is correct, exit with success
        Write-Host "$RegName key found with correct value. No remediation required."
        Exit 0

    }
    else {

        # If the registry key exists but the value is incorrect, exit with failure
        Write-Host "$RegName key found with incorrect value. Remediation required."
        Exit 1

    }

}

catch {

    # If the registry key does not exist, exit with failure
    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}