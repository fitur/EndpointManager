<#
.SYNOPSIS
    Sets Outlook's default compose, reply and plain-text font to Arial 10 pt.

.EXAMPLE
    .\Remediate-OutlookDefaultFont.ps1

.DESCRIPTION
    Writes the Simple and Complex font values for compose, reply and plain text under
    HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\mailsettings, sets ThemeFont = 2 and
    clears NewTheme. Missing keys and values are created.

    Exit 0 = all values written
    Exit 1 = remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2025-04-29
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-OutlookDefaultFont.ps1 / Remediate-OutlookDefaultFont.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = Yes
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Known limitations:
    - Outlook reads these values at startup; a running Outlook keeps the old font until
      it is restarted.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - ThemeFont is now written when the mailsettings key is created from scratch.
            Previously that branch skipped it, so detection (which requires
            ThemeFont = 2) stayed non-compliant on new profiles and the pair looped.
            NewTheme is created with an explicit empty value, the two create/update
            branches are replaced by New-ItemProperty -Force, and the script exits 0
            with a summary line on success.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$RegPath = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\mailsettings'
$ValueSimple = "3C,00,00,00,1F,00,00,F8,00,00,00,40,C8,00,00,00,00,00,00,00,00,00,00,00,00,22,41,72,69,61,6C,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00,00"
$ValueComposeComplex = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,73,70,61,6E,2E,50,65,72,73,6F,6E,61,6C,43,6F,6D,70,6F,73,65,53,74,79,6C,65,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,61,6D,65,3A,22,50,65,72,73,6F,6E,61,6C,20,43,6F,6D,70,6F,73,65,20,53,74,79,6C,65,22,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,74,79,70,65,3A,70,65,72,73,6F,6E,61,6C,2D,63,6F,6D,70,6F,73,65,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,75,6E,68,69,64,65,3A,6E,6F,3B,0D,0A,09,6D,73,6F,2D,61,6E,73,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,32,2E,30,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,41,72,69,61,6C,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,61,73,63,69,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,68,61,6E,73,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,63,6F,6C,6F,72,3A,77,69,6E,64,6F,77,74,65,78,74,3B,0D,0A,09,66,6F,6E,74,2D,77,65,69,67,68,74,3A,6E,6F,72,6D,61,6C,3B,0D,0A,09,66,6F,6E,74,2D,73,74,79,6C,65,3A,6E,6F,72,6D,61,6C,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"
$ValueReplyComplex = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,73,70,61,6E,2E,50,65,72,73,6F,6E,61,6C,52,65,70,6C,79,53,74,79,6C,65,31,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,61,6D,65,3A,22,50,65,72,73,6F,6E,61,6C,20,52,65,70,6C,79,20,53,74,79,6C,65,31,22,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,74,79,70,65,3A,70,65,72,73,6F,6E,61,6C,2D,72,65,70,6C,79,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,75,6E,68,69,64,65,3A,6E,6F,3B,0D,0A,09,6D,73,6F,2D,61,6E,73,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,32,2E,30,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,41,72,69,61,6C,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,61,73,63,69,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,68,61,6E,73,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,63,6F,6C,6F,72,3A,77,69,6E,64,6F,77,74,65,78,74,3B,0D,0A,09,66,6F,6E,74,2D,77,65,69,67,68,74,3A,6E,6F,72,6D,61,6C,3B,0D,0A,09,66,6F,6E,74,2D,73,74,79,6C,65,3A,6E,6F,72,6D,61,6C,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"
$ValueTextComplex = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,70,2E,4D,73,6F,50,6C,61,69,6E,54,65,78,74,2C,20,6C,69,2E,4D,73,6F,50,6C,61,69,6E,54,65,78,74,2C,20,64,69,76,2E,4D,73,6F,50,6C,61,69,6E,54,65,78,74,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,70,72,69,6F,72,69,74,79,3A,39,39,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6C,69,6E,6B,3A,22,50,6C,61,69,6E,20,54,65,78,74,20,43,68,61,72,22,3B,0D,0A,09,6D,61,72,67,69,6E,3A,30,63,6D,3B,0D,0A,09,6D,73,6F,2D,70,61,67,69,6E,61,74,69,6F,6E,3A,77,69,64,6F,77,2D,6F,72,70,68,61,6E,3B,0D,0A,09,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,35,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,41,72,69,61,6C,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,66,61,72,65,61,73,74,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,70,74,6F,73,3B,0D,0A,09,6D,73,6F,2D,66,61,72,65,61,73,74,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,6C,61,74,69,6E,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,6D,73,6F,2D,66,6F,6E,74,2D,6B,65,72,6E,69,6E,67,3A,31,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,6C,69,67,61,74,75,72,65,73,3A,73,74,61,6E,64,61,72,64,63,6F,6E,74,65,78,74,75,61,6C,3B,0D,0A,09,6D,73,6F,2D,66,61,72,65,61,73,74,2D,6C,61,6E,67,75,61,67,65,3A,45,4E,2D,55,53,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"

# Value name -> comma-separated hex bytes
$FontValues = [ordered]@{
    ComposeFontSimple  = $ValueSimple
    ReplyFontSimple    = $ValueSimple
    TextFontSimple     = $ValueSimple
    ComposeFontComplex = $ValueComposeComplex
    ReplyFontComplex   = $ValueReplyComplex
    TextFontComplex    = $ValueTextComplex
}

try {
    if (-not (Test-Path -Path $RegPath)) {
        New-Item -Path $RegPath -Force | Out-Null
    }

    # -Force on New-ItemProperty overwrites existing values, so create and update share one path
    New-ItemProperty -Path $RegPath -Name 'NewTheme' -Value '' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $RegPath -Name 'ThemeFont' -Value 2 -PropertyType DWord -Force | Out-Null

    foreach ($Name in $FontValues.Keys) {
        # Cast inline - a helper function returning [byte[]] would unroll it into object[]
        $Bytes = [byte[]]($FontValues[$Name].Split(',') | ForEach-Object { [Convert]::ToByte($_, 16) })
        New-ItemProperty -Path $RegPath -Name $Name -Value $Bytes -PropertyType Binary -Force | Out-Null
    }

    Write-Output "Remediated: Outlook font values written ($($FontValues.Count) font values, ThemeFont = 2). Restart Outlook to apply."
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
