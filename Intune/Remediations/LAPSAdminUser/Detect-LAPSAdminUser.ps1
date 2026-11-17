<#
.SYNOPSIS
    Detects whether the local LAPSAdmin account exists.

.EXAMPLE
    .\Detect-LAPSAdminUser.ps1

.DESCRIPTION
    Checks for a local user named LAPSAdmin, the account that Windows LAPS is configured
    to manage on these devices.

    Exit 0 = compliant (LAPSAdmin exists)
    Exit 1 = non-compliant (LAPSAdmin missing, or detection itself failed)

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2025-05-07
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-LAPSAdminUser.ps1 / Remediate-LAPSAdminUser.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No
        Run script in 64-bit PowerShell                 = Yes (required - the
            LocalAccounts module is not available in 32-bit PowerShell on 64-bit Windows)
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Known limitations:
    - Only checks that the account exists, not that it is a member of Administrators.
    - Windows LAPS automatic account management (Windows 11 24H2 and later) can create
      and manage the account itself. On such baselines this pair is redundant.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - A missing account is reported as non-compliant instead of surfacing the raw
            UserNotFound error. Other errors are reported as detection failures.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$LAPSUser = 'LAPSAdmin'

try {
    $null = Get-LocalUser -Name $LAPSUser
    Write-Output "Compliant: local user '$LAPSUser' exists."
    exit 0
} catch {
    if ($_.FullyQualifiedErrorId -like 'UserNotFound*') {
        Write-Output "Non-compliant: local user '$LAPSUser' not found - triggering remediation."
    } else {
        Write-Output "Detection failed: $($_.Exception.Message)"
    }
    exit 1
}
