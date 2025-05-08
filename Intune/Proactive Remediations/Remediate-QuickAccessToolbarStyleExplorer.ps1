<#

.SYNOPSIS
    PowerShell script to remediate the QuickAccessToolbarStyleExplorer registry value for Outlook.

.EXAMPLE
    .\Remediate-QuickAccessToolbarStyleExplorer.ps1

.DESCRIPTION
    This PowerShell script is deployed as a remediation script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2025-04-29
    Last Updated:   2025-04-29
    Author:         Peter Olausson
    Contact:        admin@fitur.se
#>

[CmdletBinding()]

Param (

)

$RegPath = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Toolbars\Outlook\'
[string[]]$Functions = Get-ItemPropertyValue $RegPath -Name QuickAccessToolbarStyleExplorer -ErrorAction SilentlyContinue

try {

    if ($Functions) {

        Write-Host 'Creating QuickAccessToolbarStyleExplorer property...'
        Set-ItemProperty -Path $RegPath -Name "QuickAccessToolbarStyleExplorer" -Value 16 -Force

    } else {

        Write-Host "Unable to read $RegPath."
        New-ItemProperty -Path $RegPath -Name "QuickAccessToolbarStyleExplorer" -PropertyType DWord -Value 16 -Force 

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Warning $ErrorMessage
    Exit 1

}