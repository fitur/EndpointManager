<#
.SYNOPSIS
    Disables IPv6 by setting the DisabledComponents registry value to 0xFF.

.EXAMPLE
    .\Remediate-DisableIPv6.ps1

.DESCRIPTION
    Writes HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\DisabledComponents
    = 0xFF (DWORD), creating the key and value if they are missing. The change takes
    effect at the next reboot - the script does not reboot the device.

    Exit 0 = value written (reboot pending)
    Exit 1 = remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://learn.microsoft.com/troubleshoot/windows-server/networking/configure-ipv6-in-windows

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

    Known limitations:
    - Microsoft recommends 0x20 (prefer IPv4 over IPv6) rather than disabling IPv6
      completely; some Windows components are only tested with IPv6 enabled. 0xFF is
      kept here because it is what the deployed baseline expects.
    - Requires a reboot. Detection reports compliant as soon as the value is written.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Renamed from Remediate-DisabledComponents.ps1. The description previously
            said the script enables IPv6 and the output referred to an unrelated
            Outlook value. Writes the value as an integer DWORD with a single
            New-ItemProperty -Force instead of two branches built on an inverted
            null check, and exits 0 explicitly on success.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$RegPath   = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
$ValueName = 'DisabledComponents'
$Desired   = 0xFF

try {
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    # -Force overwrites an existing value, so no separate create/update branches are needed
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Desired -PropertyType DWord -Force | Out-Null

    Write-Output ("Remediated: {0} set to 0x{1:X}. Reboot required to take effect." -f $ValueName, $Desired)
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
