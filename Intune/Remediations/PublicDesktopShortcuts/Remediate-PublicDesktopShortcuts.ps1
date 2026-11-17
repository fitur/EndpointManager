<#
.SYNOPSIS
    Removes all shortcuts (.lnk) from the Public Desktop.

.EXAMPLE
    .\Remediate-PublicDesktopShortcuts.ps1

.DESCRIPTION
    Deletes every .lnk file in %PUBLIC%\Desktop. Each file is removed individually so one
    locked shortcut does not stop the others from being removed.

    Exit 0 = all shortcuts removed
    Exit 1 = one or more shortcuts could not be removed, or remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2025-05-16
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-PublicDesktopShortcuts.ps1 / Remediate-PublicDesktopShortcuts.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No (users cannot delete from
            the Public Desktop)
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Known limitations:
    - Deletes every shortcut, including ones placed there on purpose. Applications that
      recreate their shortcut on update will be cleaned up again on the next run.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Failed deletions are now counted and reported with exit 1. Previously
            Remove-Item ran with -ErrorAction SilentlyContinue, so the catch block could
            never run and the script always reported success. Corrected the synopsis.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$PublicDesktop = Join-Path -Path $env:PUBLIC -ChildPath 'Desktop'

try {
    $Shortcuts = @(Get-ChildItem -Path $PublicDesktop -Filter '*.lnk' -File -ErrorAction SilentlyContinue)

    $Removed = 0
    $Failed  = @()

    foreach ($Shortcut in $Shortcuts) {
        try {
            Remove-Item -LiteralPath $Shortcut.FullName -Force
            $Removed++
        } catch {
            $Failed += $Shortcut.Name
        }
    }

    if ($Failed.Count -gt 0) {
        Write-Output "Partially remediated: removed $Removed, failed $($Failed.Count) ($($Failed -join ', '))."
        exit 1
    }

    Write-Output "Remediated: removed $Removed shortcut(s) from the Public Desktop."
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
