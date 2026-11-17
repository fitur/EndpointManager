<#
.SYNOPSIS
    Detects saved Wi-Fi profiles whose name contains "Guest".

.EXAMPLE
    .\Detect-SavedGuestWiFi.ps1

.DESCRIPTION
    Lists saved WLAN profiles with netsh and reports non-compliant if any profile name
    matches $ProfilePattern (case-insensitive regex, default 'Guest'), so devices do not
    silently prefer a guest network over the corporate one.

    Profile names are read from the text after the colon on each profile line, which
    works regardless of the Windows display language.

    Exit 0 = compliant (no matching profile, or no WLAN service on the device)
    Exit 1 = non-compliant (matching profile found, or detection itself failed)

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

    Intune shows only the last line of output, so each exit path writes a single
    summary line immediately before exiting.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Rewritten detection. 1.0.0 reported every device as non-compliant: an empty
            -match result is an empty array, not $null, so the "no guest Wi-Fi" branch
            never ran, and the next line read an undefined $RasphonePath (left over
            from a VPN script), which threw and exited 1. Now parses profile names and
            matches only on the name.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$ProfilePattern = 'Guest'

try {
    $NetshOutput = netsh.exe wlan show profiles

    # Non-zero when the WLAN AutoConfig service is absent or stopped (e.g. desktops)
    if ($LASTEXITCODE -ne 0) {
        Write-Output "Not applicable: netsh wlan returned exit code $LASTEXITCODE (no WLAN service)."
        exit 0
    }

    # Profile lines look like "    All User Profile     : <name>" in every language
    $Matching = @(
        $NetshOutput |
            ForEach-Object { if ($_ -match '^\s+[^:]+:\s*(\S.*?)\s*$') { $Matches[1] } } |
            Where-Object { $_ -match $ProfilePattern }
    )

    if ($Matching.Count -gt 0) {
        Write-Output "Non-compliant: saved guest Wi-Fi profile(s): $($Matching -join ', ') - triggering remediation."
        exit 1
    }

    Write-Output "Compliant: no saved Wi-Fi profile matches '$ProfilePattern'."
    exit 0
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
