<#

.SYNOPSIS
    PowerShell script to remove saved guest Wi-Fi networks.

.EXAMPLE
    .\Remediate-SavedGuestWiFi.ps1

.DESCRIPTION
    This PowerShell script is deployed as a remediation script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2024-03-22
    Last Updated:   2024-03-22
    Author:         Peter Olausson
    Contact:        fitur@duck.com

#>

[CmdletBinding()]

Param (

)

$GuestWiFi = (netsh.exe wlan show profiles) -match 'Guest'

Try {

    $GuestWiFi | ForEach-Object {
        netsh.exe wlan delete profile ($_ -split ": " | Select-Object -Last 1)
    }

}

Catch {

    $ErrorMessage = $_.Exception.Message 
    Write-Host $ErrorMessage
    Exit 1

}