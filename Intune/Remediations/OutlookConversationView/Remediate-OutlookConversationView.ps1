<#
.SYNOPSIS
    PowerShell script to remediate (turn off) Conversation view as a default in Outlook.

.EXAMPLE
    .\Remediate-OutlookConversationView.ps1

.DESCRIPTION
    This PowerShell script sets the Outlook value
        HKCU:\Software\Microsoft\Office\16.0\Outlook\Setup\UpgradeToConversations = 0 (DWORD)
    and then writes the marker value checked by Detect-OutlookConversationView.ps1:
        HKCU:\Software\Advania\IntuneDefaults\OutlookConversationViewOff = 1 (DWORD)

    Missing keys are created. If both values are written, it outputs "Remediated"
    and exits 0. On any error, it outputs the error message and exits 1.

    It is meant to be run as a remediation script using Proactive Remediations
    in Microsoft Endpoint Manager/Intune, in the USER context.

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.1
    Creation Date:  2026-10-20
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-OutlookConversationView.ps1 / Remediate-OutlookConversationView.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = Yes
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    VERIFY BEFORE ROLLOUT:
    The registry path, value name and value ($RegPath, $ValueName, $Desired)
    must be verified against the Office ADMX templates / a test machine before
    this is deployed.

    ONE-TIME DEFAULT, NOT ENFORCEMENT:
    Once the marker is written, the detection script reports "Compliant" and
    this remediation will not run again, even if the user turns Conversation
    view back on afterwards.

    Runs in the USER context (per-user setting).

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.0.1 - Summary lines use Write-Output; the empty CmdletBinding scaffold is replaced
            by $ErrorActionPreference = 'Stop'. Header aligned with the repository
            standard.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

# VERIFY these against ADMX / test machine before rollout
$RegPath   = 'HKCU:\Software\Microsoft\Office\16.0\Outlook\Setup'
$ValueName = 'UpgradeToConversations'
$Desired   = 0

$MarkerPath = 'HKCU:\Software\Advania\IntuneDefaults'
$MarkerName = 'OutlookConversationViewOff'

try {

    if (!(Test-Path $RegPath)) {

        New-Item -Path $RegPath -Force -ErrorAction Stop | Out-Null

    }

    if (!(Test-Path $MarkerPath)) {

        New-Item -Path $MarkerPath -Force -ErrorAction Stop | Out-Null

    }

    New-ItemProperty -Path $RegPath -Name $ValueName -Value $Desired -PropertyType DWord -Force -ErrorAction Stop | Out-Null
    New-ItemProperty -Path $MarkerPath -Name $MarkerName -Value 1 -PropertyType DWord -Force -ErrorAction Stop | Out-Null

    Write-Output "Remediated"
    exit 0

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Output $ErrorMessage
    exit 1

}
