<#

.SYNOPSIS
    PowerShell script to remediate (disable) Focused Inbox in Outlook (classic).

.EXAMPLE
    .\Remediate-OutlookFocusedInbox.ps1

.DESCRIPTION
    This PowerShell script disables Focused Inbox for every mail account that
    already has a Focused Inbox value under
    HKCU:\SOFTWARE\Microsoft\Office\Outlook\Settings\Data
    ("<smtp-address>_IsFocusedInboxEnabled"), by rewriting the "value" property
    inside that value's JSON payload to false, preserving any other properties
    already present in the JSON.

    It is meant to be run as a remediation script using Proactive Remediations
    in Microsoft Endpoint Manager/Intune, in the USER context.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

    .NOTES
    Version:        1.0.0
    Creation Date:  2026-09-18
    Last Updated:   2026-09-18
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    IMPORTANT - THIS IS NOT AN OFFICIALLY DOCUMENTED SETTING:
    See Detect-OutlookFocusedInbox.ps1 for the full caveat. In short: this
    registry location/format is undocumented, per-account, and can change or
    disappear in any Outlook build. It complements - it does not replace - the
    supported tenant-wide control:
        Set-OrganizationConfig -FocusedInboxOn $false

    LIMITATION: this script can only flip values that already exist. It cannot
    create the "<smtp-address>_IsFocusedInboxEnabled" value for an account that
    has never had Focused Inbox toggled/loaded by Outlook yet, because the key
    name requires the account's SMTP address and Outlook itself decides when to
    first write it. On such a device the detection script will keep reporting
    "Not Compliant" until Outlook has created the value at least once (i.e.
    after the user has opened Outlook with that account). If this remediation
    finds nothing to fix, it reports that explicitly and exits 1 (not
    remediated) rather than a false-positive success.

    Runs in the USER context (per-account, per-user setting).

#>

[CmdletBinding()]

Param (

)

$RegPath = 'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Settings\Data'

try {

    if (!(Test-Path $RegPath)) {

        Write-Host "Not remediated: registry key does not exist yet (Outlook has not initialised Focused Inbox settings for any account on this profile)."
        Exit 1

    }

    $Properties = Get-Item -Path $RegPath -ErrorAction Stop |
        Select-Object -ExpandProperty Property |
        Where-Object { $_ -like '*_IsFocusedInboxEnabled' }

    if (-not $Properties -or $Properties.Count -eq 0) {

        Write-Host "Not remediated: no *_IsFocusedInboxEnabled values found (no account has loaded Focused Inbox settings yet)."
        Exit 1

    }

    $AnyChanged = $false
    $AnyFailed = $false

    foreach ($PropertyName in $Properties) {

        $RawValue = Get-ItemProperty -Path $RegPath -Name $PropertyName -ErrorAction Stop |
            Select-Object -ExpandProperty $PropertyName

        try {
            $Parsed = $RawValue | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $AnyFailed = $true
            continue
        }

        $Parsed.value = $false
        $NewValue = $Parsed | ConvertTo-Json -Compress

        Set-ItemProperty -Path $RegPath -Name $PropertyName -Value $NewValue -ErrorAction Stop
        $AnyChanged = $true

    }

    if ($AnyChanged -and -not $AnyFailed) {

        Write-Host "Remediated"
        Exit 0

    } else {

        Write-Host "Partially or not remediated: one or more values could not be parsed/updated."
        Exit 1

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}