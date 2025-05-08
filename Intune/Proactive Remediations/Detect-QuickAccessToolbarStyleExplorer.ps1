<#

.SYNOPSIS
    PowerShell script to detect the QuickAccessToolbarStyleExplorer registry value for Outlook.

.EXAMPLE
    .\Detect-QuickAccessToolbarStyleExplorer.ps1

.DESCRIPTION
    This Powershell script checks the registry for the presence of the QuickAccessToolbarStyleExplorer value in the specified registry path.

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

if (-not ($Functions)) {

    Write-Host 'Unable to read $RegPath.'
    Exit 1

}

try {

    if ($Functions -Match '16') {

        Write-Host 'QuickAccessToolbarStyleExplorer value detected. No remediation required.'
        Exit 0

    } else {

        Write-Host 'QuickAccessToolbarStyleExplorer value not detected. Remediation required.'
        Exit 1

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}