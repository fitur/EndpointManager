<#

.SYNOPSIS
    PowerShell script to remove saved guest Wi-Fi networks.

.EXAMPLE
    .\Remediate-SavedGuestWiFi.ps1

.DESCRIPTION
    This PowerShell script is used to remove saved guest Wi-Fi networks from the local system.
    It checks for any saved guest Wi-Fi networks and deletes them if found.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.1
    Creation Date:  2024-03-22
    Last Updated:   2025-05-08
    Author:         Peter Olausson
    Contact:        admin@fitur.se

#>

[CmdletBinding()]

Param (

)

# Specify the SSID of the guest Wi-Fi network to check for
$SSID = "Guest"

try {
    
    $GuestWiFi = (netsh.exe wlan show profiles) -match $SSID
    $GuestWiFi | ForEach-Object {
        #netsh.exe wlan delete profile ($_ -split ": " | Select-Object -Last 1)
        $Interface = Get-NetIPInterface | Where-Object { $_.InterfaceAlias -like "*$SSID*" }
        if ($Interface) {
            Set-NetIPInterface -InterfaceIndex $Interface.InterfaceIndex -AddressFamily IPv4 -InterfaceMetric 999
            Write-Host "Priority of SSID '$SSID' has been lowered."
        } else {
            Write-Host "No matching interface found for SSID '$SSID'."
        }
    }

}

catch {

    $ErrorMessage = $_.Exception.Message 
    Write-Host $ErrorMessage
    Exit 1

}