<#
.SYNOPSIS
    Detects whether IPv6 is disabled through the DisabledComponents registry value.

.EXAMPLE
    .\Detect-DisableIPv6.ps1

.DESCRIPTION
    Reads HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\DisabledComponents.
    The value 0xFF disables all IPv6 components except the loopback interface.

    Exit 0 = compliant (DisabledComponents = 0xFF)
    Exit 1 = non-compliant (value missing or different, or detection itself failed)

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2025-05-09
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-DisableIPv6.ps1 / Remediate-DisableIPv6.ps1
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
    1.1.0 - Renamed from Detect-DisabledComponents.ps1. Compares the value numerically,
            separates "missing" from "wrong value" in the output, and uses
            Write-Output for the summary line.
    1.0.1 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$RegPath   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
$ValueName = 'DisabledComponents'
$Desired   = 0xFF

try {
    # SilentlyContinue: a missing key or value is a compliance result, not an error
    $Current = (Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName

    if ($null -eq $Current) {
        Write-Output "Non-compliant: $ValueName is not set - triggering remediation."
        exit 1
    }

    if ([int]$Current -eq $Desired) {
        Write-Output ("Compliant: {0} = 0x{1:X}." -f $ValueName, [int]$Current)
        exit 0
    }

    Write-Output ("Non-compliant: {0} = 0x{1:X}, expected 0x{2:X} - triggering remediation." -f $ValueName, [int]$Current, $Desired)
    exit 1
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
