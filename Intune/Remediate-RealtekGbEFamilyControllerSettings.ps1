<#

.SYNOPSIS
    PowerShell script to remediate the settings for Realtek USB GbE Family Controller driver.
    Realtek USB GbE Family Controller enables Green Ethernet as default, which causes intermittent disconnects.

.EXAMPLE
    .\Remediate-RealtekGbEFamilyControllerSettings.ps1

.DESCRIPTION
    This PowerShell script is deployed as a remediation script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.NOTES
    Version:        1.0
    Creation Date:  May 31, 2022
    Last Updated:   May 31, 2022
    Author:         Peter Olausson
    Contact:        admin@fitur.se
    Web Site:       https://github.com/fitur

#>

[CmdletBinding()]
param (
)
## Variables
$AdapterName = "Realtek USB GbE Family Controller*"
$AdapterSettings = ("*EEE", "*PriorityVLANTag", "EnableExtraPowerSaving", "EnableGreenEthernet")
$AdapterValues = (0, 3, 0, 0)
$Remediation = 0
try {
    if (!($NetAdapter = Get-NetAdapter | Where-Object {$_.InterfaceDescription -like $AdapterName})) {
        Write-Warning "Network adapter $AdapterName not found."
        exit 0
    }
    foreach ($DesiredSetting in $AdapterSettings) {
        $CurrentValue = ($NetAdapter | Get-NetAdapterAdvancedProperty -RegistryKeyword $DesiredSetting -ErrorAction SilentlyContinue | Select-Object -ExpandProperty RegistryValue)
        if (($CurrentValue -ne $AdapterValues[$AdapterSettings.IndexOf($DesiredSetting)]) -and (![string]::IsNullOrEmpty($CurrentValue))) {
            Write-Verbose "$DesiredSetting is incorrect. Remediating." -Verbose
            $NetAdapter | Set-NetAdapterAdvancedProperty -RegistryKeyword $DesiredSetting -RegistryValue $AdapterValues[$AdapterSettings.IndexOf($DesiredSetting)] -WhatIf -Verbose -ErrorAction Stop
        }
        else {
            Write-Verbose "$DesiredSetting is correct or N/A. Skipping." -Verbose
        }
    }
    if ($Remediation -gt 0) {
        Write-Verbose "Remediation required." -Verbose
        exit 1
    }
}
catch {
    $ErrorMessage = $_.Exception.Message 
    Write-Warning $ErrorMessage
    exit 1
}