<#

.SYNOPSIS
    PowerShell script to detect whether the "Conversation view off" default has been applied in Outlook.

.EXAMPLE
    .\Detect-OutlookConversationView.ps1

.DESCRIPTION
    This PowerShell script checks for a marker value written by the companion
    remediation once it has turned off Conversation view in Outlook:
        HKCU:\Software\Advania\IntuneDefaults\OutlookConversationViewOff = 1

    If the marker exists and equals 1, it outputs "Compliant" and exits 0.
    Otherwise (missing key/value or any other value), it outputs "Not Compliant"
    and exits 1.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

    .NOTES

    Version:        1.0.0
    Creation Date:  2026-10-20
    Last Updated:   2026-10-20
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    ONE-TIME DEFAULT, NOT ENFORCEMENT:
    This script only checks the marker, not Outlook's actual Conversation view
    setting. Once the default has been applied, the device stays "Compliant"
    even if the user turns Conversation view back on afterwards.

    Requires a companion remediation that turns Conversation view off and
    then sets the marker value to 1.

    Runs in the USER context (per-user setting).

#>

[CmdletBinding()]

Param (

)

$MarkerPath = 'HKCU:\Software\Advania\IntuneDefaults'
$MarkerName = 'OutlookConversationViewOff'

try {

    $Value = (Get-ItemProperty -Path $MarkerPath -Name $MarkerName -ErrorAction Stop).$MarkerName

    if ($Value -eq 1) {

        Write-Host "Compliant"
        Exit 0

    }

}

catch {

    # Marker key or value missing - default not applied yet

}

Write-Host "Not Compliant"
Exit 1
