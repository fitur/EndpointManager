<#

.SYNOPSIS
    PowerShell script to detect saved guest Wi-Fi networks.

.EXAMPLE
    .\Detect-SavedGuestWiFi.ps1

.DESCRIPTION
    This PowerShell script is used to check if any guest Wi-Fi networks are saved on the local system.
    If any guest Wi-Fi networks are found, it outputs "Guest Wi-Fi found. Remediation required." and exits with a status code of 1.
    If no guest Wi-Fi networks are found, it outputs "No guest Wi-Fi found." and exits with a status code of 0.

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

Try {
    
    $GuestWiFi = (netsh.exe wlan show profiles) -match $SSID
    if ($null -eq $GuestWiFi) {

        Write-Host 'No guest Wi-Fi found.'
        Exit 0

    } else {

        Write-Host 'Guets Wi-Fi found. Remediation required.'
        Exit 1

    }

}

Catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}