<#
.SYNOPSIS
    Detects whether Outlook's QuickAccessToolbarStyleExplorer value is set to 16.

.EXAMPLE
    .\Detect-OutlookQuickAccessToolbar.ps1

.DESCRIPTION
    Reads QuickAccessToolbarStyleExplorer under
    HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Toolbars\Outlook, which controls how the
    Quick Access Toolbar is shown in the Outlook main window.

    Exit 0 = compliant (value = 16)
    Exit 1 = non-compliant (value missing or different, or detection itself failed)

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

    Intune shows only the last line of output, so each exit path writes a single
    summary line immediately before exiting.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Renamed from Detect-QuickAccessToolbarStyleExplorer.ps1. Compares the value
            numerically; -match '16' also accepted 116, 160 and so on. The "unable to
            read" message no longer prints the literal text $RegPath.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$RegPath   = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\Toolbars\Outlook'
$ValueName = 'QuickAccessToolbarStyleExplorer'
$Desired   = 16

try {
    # SilentlyContinue: a missing key or value is a compliance result, not an error
    $Current = (Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName

    if ($null -eq $Current) {
        Write-Output "Non-compliant: $ValueName is not set - triggering remediation."
        exit 1
    }

    if ([int]$Current -eq $Desired) {
        Write-Output "Compliant: $ValueName = $Current."
        exit 0
    }

    Write-Output "Non-compliant: $ValueName = $Current, expected $Desired - triggering remediation."
    exit 1
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
