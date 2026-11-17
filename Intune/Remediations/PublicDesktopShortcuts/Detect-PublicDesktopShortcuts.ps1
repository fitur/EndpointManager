<#
.SYNOPSIS
    Detects shortcuts (.lnk) on the Public Desktop.

.EXAMPLE
    .\Detect-PublicDesktopShortcuts.ps1

.DESCRIPTION
    Looks for .lnk files in %PUBLIC%\Desktop, typically left there by application
    installers and shown on every user's desktop.

    Exit 0 = compliant (no shortcuts)
    Exit 1 = non-compliant (one or more shortcuts found, or detection itself failed)

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.1
    Creation Date:  2025-05-16
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-PublicDesktopShortcuts.ps1 / Remediate-PublicDesktopShortcuts.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Intune shows only the last line of output, so each exit path writes a single
    summary line immediately before exiting.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.0.1 - Corrected the synopsis (it described an unrelated IPv6 script). The file
            lookup runs inside try/catch and the output includes the shortcut count.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$PublicDesktop = Join-Path -Path $env:PUBLIC -ChildPath 'Desktop'

try {
    # @() so Count is reliable for zero and one result in Windows PowerShell 5.1
    $Shortcuts = @(Get-ChildItem -Path $PublicDesktop -Filter '*.lnk' -File -ErrorAction SilentlyContinue)

    if ($Shortcuts.Count -eq 0) {
        Write-Output "Compliant: no shortcuts on the Public Desktop."
        exit 0
    }

    Write-Output "Non-compliant: $($Shortcuts.Count) shortcut(s) on the Public Desktop - triggering remediation."
    exit 1
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
