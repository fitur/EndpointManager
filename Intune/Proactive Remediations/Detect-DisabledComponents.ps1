<#

.SYNOPSIS
    PowerShell script detect if IPv6 is disabled in the registry.

.EXAMPLE
    .\Detect-DisabledComponents.ps1

.DESCRIPTION
    This Powershell script detects if IPv6 is disabled in the registry by checking the value of the DisabledComponents key.
    If the value is set to 0xFF, it indicates that IPv6 is disabled. The script will output a message indicating whether remediation is required.
    
.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.1
    Creation Date:  2025-05-09
    Last Updated:   2025-05-13
    Author:         Peter Olausson
    Contact:        admin@fitur.se

#>

[CmdletBinding()]

Param (

)

$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\"

try {
    
    [string[]]$RegValue = Get-ItemPropertyValue $RegPath -Name "DisabledComponents" -ErrorAction Stop

    if ("255" -eq $RegValue) {

        Write-Host 'DisabledComponents key found with correct value. No remediation required.'
        Exit 0

    }
    else {

        Write-Host 'DisabledComponents key found with incorrect value. Remediation required.'
        Exit 1

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}