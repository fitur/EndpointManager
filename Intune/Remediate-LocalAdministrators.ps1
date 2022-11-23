<#

.SYNOPSIS
    PowerShell script to detect unallowed users with administrative privileges.

.EXAMPLE
    .\Remediate-LocalAdministrators.ps1

.DESCRIPTION
    This PowerShell script is deployed as a remediation script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.NOTES
    Version:        1.0
    Creation Date:  November 23, 2022
    Last Updated:   November 23, 2022
    Author:         Peter Olausson
    Contact:        admin@fitur.se
    Web Site:       https://github.com/fitur

#>

[CmdletBinding()]
param (
)
## Variables
$TunnelName = "NLTG VPN CA"
$OldTunnelName = "NLTG-ST-VPN"
try {
    Get-VpnConnection -Name $OldTunnelName -AllUserConnection -ErrorAction SilentlyContinue | ForEach-Object {
        rasdial $_.Name /DISCONNECT
        Wait-Event -Timeout 5
        rasdial $_.Name /DISCONNECT
        Remove-VpnConnection -Name $_.Name -AllUserConnection -Force
    }
}
catch {
    $ErrorMessage = $_.Exception.Message 
    Write-Warning $ErrorMessage
    exit 1
}