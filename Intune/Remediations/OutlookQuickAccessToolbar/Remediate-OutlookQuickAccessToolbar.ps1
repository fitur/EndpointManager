<#
.SYNOPSIS
    Sets Outlook's QuickAccessToolbarStyleExplorer value to 16.

.EXAMPLE
    .\Remediate-OutlookQuickAccessToolbar.ps1

.DESCRIPTION
    Writes QuickAccessToolbarStyleExplorer = 16 (DWORD) under
    HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Toolbars\Outlook, creating the key and
    value if they are missing.

    Exit 0 = value written
    Exit 1 = remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2025-04-29
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-OutlookQuickAccessToolbar.ps1 / Remediate-OutlookQuickAccessToolbar.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = Yes
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Known limitations:
    - Outlook reads the value at startup; restart Outlook to see the change.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Renamed from Remediate-QuickAccessToolbarStyleExplorer.ps1. Creates the
            Toolbars\Outlook key when it is missing (New-ItemProperty failed before),
            writes the value with a single New-ItemProperty -Force, and exits 0 with a
            summary line. The output messages were reversed in 1.0.0.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$RegPath   = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Toolbars\Outlook'
$ValueName = 'QuickAccessToolbarStyleExplorer'
$Desired   = 16

try {
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Desired -PropertyType DWord -Force | Out-Null

    Write-Output "Remediated: $ValueName set to $Desired. Restart Outlook to apply."
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
