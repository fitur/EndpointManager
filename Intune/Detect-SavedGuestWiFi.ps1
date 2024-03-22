<#

.SYNOPSIS
    PowerShell script to detect saved guest Wi-Fi networks.

.EXAMPLE
    .\Detect-SavedGuestWiFi.ps1

.DESCRIPTION
    This PowerShell script is deployed as a detection script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  Mars 22, 2024
    Last Updated:   Mars 22, 2024
    Author:         Peter Olausson
    Contact:        admin@fitur.se

#>

[CmdletBinding()]

Param (

)

$GuestWiFi = (netsh.exe wlan show profiles) -match 'Guest'

Try {

    If ($null -eq $GuestWiFi) {

        Write-Host 'No guest Wi-Fi found.'
        Exit 0

    }

    $RasphoneData = (Get-Content $RasphonePath | Select-String UseRasCredentials) | ConvertFrom-StringData

    If ($RasphoneData.UseRasCredentials -eq '1') {

        Write-Host 'Guets Wi-Fi found. Remediation required.'
        Exit 1

    }

}

Catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}