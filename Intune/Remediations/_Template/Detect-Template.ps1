<#
.SYNOPSIS
    TEMPLATE - Detects whether a registry value has the expected data.

.EXAMPLE
    .\Detect-<Name>.ps1

.DESCRIPTION
    Starting point for a new detection script. Copy the _Template folder to a new
    <Name> folder, rename both files to Detect-<Name>.ps1 / Remediate-<Name>.ps1, set the
    variables below and rewrite this help block for the real check.

    As shipped, it checks a single registry value:

    Exit 0 = compliant (value exists and equals $Desired)
    Exit 1 = non-compliant (value missing or different, or detection itself failed)

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        2.0.0
    Creation Date:  2025-05-14
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-<Name>.ps1 / Remediate-<Name>.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = Yes for HKCU, No for HKLM
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Conventions for every remediation script in this repository:
    - $ErrorActionPreference = 'Stop' and one try/catch around the whole body.
    - Exactly one Write-Output summary line immediately before every exit; Intune
      shows only the last line of output.
    - Explicit exit 0 / exit 1 on every path. Prefix the line with Compliant,
      Non-compliant, Not applicable or Detection failed.
    - Keep the variables identical in both scripts of the pair.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    2.0.0 - Turned from the RegValue pair into a repository template. Compares the data
            as a string with the same rules as the remediation template.
    1.0.0 - Initial published version (Detect-RegValue.ps1).
#>

$ErrorActionPreference = 'Stop'

# Set these - and keep them identical in Remediate-<Name>.ps1
$RegPath   = 'HKCU:\Software\<Vendor>\<Product>'
$ValueName = '<ValueName>'
$Desired   = '<Data>'

try {
    # SilentlyContinue: a missing key or value is a compliance result, not an error
    $Current = (Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction SilentlyContinue).$ValueName

    if ($null -eq $Current) {
        Write-Output "Non-compliant: $ValueName is not set - triggering remediation."
        exit 1
    }

    if ([string]$Current -eq [string]$Desired) {
        Write-Output "Compliant: $ValueName has the expected data."
        exit 0
    }

    Write-Output "Non-compliant: $ValueName = '$Current', expected '$Desired' - triggering remediation."
    exit 1
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
