<#
.SYNOPSIS
    Removes saved Wi-Fi profiles whose name contains "Guest".

.EXAMPLE
    .\Remediate-SavedGuestWiFi.ps1

.DESCRIPTION
    Deletes every saved WLAN profile whose name matches $ProfilePattern
    (case-insensitive regex, default 'Guest') with netsh, one profile at a time, and
    checks netsh's exit code for each deletion.

    Exit 0 = all matching profiles removed (or none found)
    Exit 1 = one or more profiles could not be removed, or remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2024-03-22
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-SavedGuestWiFi.ps1 / Remediate-SavedGuestWiFi.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Keep $ProfilePattern identical in both scripts of the pair.

    Known limitations:
    - Profiles deployed by Group Policy or Intune are read-only and cannot be deleted;
      they are reported as failures. Exclude them by tightening $ProfilePattern.
    - The user can reconnect to the guest network, which saves the profile again until
      the next run.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Parses profile names the same way as the detection script and deletes by
            exact name (name="..."), checking netsh's exit code per profile. 1.0.0
            split on ": " without quoting and never reported a failed deletion.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$ProfilePattern = 'Guest'

try {
    $NetshOutput = netsh.exe wlan show profiles

    if ($LASTEXITCODE -ne 0) {
        Write-Output "Not applicable: netsh wlan returned exit code $LASTEXITCODE (no WLAN service)."
        exit 0
    }

    $Matching = @(
        $NetshOutput |
            ForEach-Object { if ($_ -match '^\s+[^:]+:\s*(\S.*?)\s*$') { $Matches[1] } } |
            Where-Object { $_ -match $ProfilePattern }
    )

    $Removed = @()
    $Failed  = @()

    foreach ($ProfileName in $Matching) {
        $null = netsh.exe wlan delete profile name="$ProfileName"
        if ($LASTEXITCODE -eq 0) { $Removed += $ProfileName } else { $Failed += $ProfileName }
    }

    if ($Failed.Count -gt 0) {
        Write-Output "Partially remediated: removed $($Removed.Count), could not remove: $($Failed -join ', ')."
        exit 1
    }

    Write-Output "Remediated: removed $($Removed.Count) guest Wi-Fi profile(s)$(if ($Removed.Count) { ': ' + ($Removed -join ', ') })."
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
