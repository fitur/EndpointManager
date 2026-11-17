<#
.SYNOPSIS
    TEMPLATE - Writes a registry value with the expected data.

.EXAMPLE
    .\Remediate-<Name>.ps1

.DESCRIPTION
    Starting point for a new remediation script. See Detect-Template.ps1 for how to use
    the template and the conventions every remediation script follows.

    As shipped, it creates the key if needed and writes a single registry value:

    Exit 0 = value written
    Exit 1 = remediation failed

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

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    2.0.0 - Turned from the RegValue pair into a repository template. Replaces the
            create/update branches (built on an inverted null check and cmd /c reg add)
            with New-Item + New-ItemProperty -Force, and no longer truncates the data
            with Substring(0,15), which threw for anything shorter than 15 characters.
    1.0.0 - Initial published version (Remediate-RegValue.ps1).
#>

$ErrorActionPreference = 'Stop'

# Set these - and keep them identical in Detect-<Name>.ps1
$RegPath   = 'HKCU:\Software\<Vendor>\<Product>'
$ValueName = '<ValueName>'
$Desired   = '<Data>'
$ValueType = 'String'   # String, ExpandString, DWord, QWord, Binary or MultiString

try {
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    # -Force overwrites an existing value, so create and update share one path
    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Desired -PropertyType $ValueType -Force | Out-Null

    Write-Output "Remediated: $ValueName written to $RegPath."
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
