<#

.SYNOPSIS
    PowerShell script to detect whether Focused Inbox is disabled in Outlook (classic).

.EXAMPLE
    .\Detect-OutlookFocusedInbox.ps1

.DESCRIPTION
    This PowerShell script checks the registry for the per-account Focused Inbox
    setting used by classic Outlook. Each mail account that has ever toggled
    Focused Inbox gets its own value, named "<smtp-address>_IsFocusedInboxEnabled",
    under HKCU:\SOFTWARE\Microsoft\Office\Outlook\Settings\Data. The value is a
    JSON string containing (among other things) a "value" property (true/false).

    The script enumerates every "*_IsFocusedInboxEnabled" value under that key and
    checks that "value" is false for all of them. If at least one such value exists
    and all are false, it outputs "Compliant" and exits 0. If none exist yet, or any
    is true/unparsable, it outputs "Not Compliant" and exits 1.

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
    Unlike the Outlook-Default-Font script this is modelled on, this registry
    location and value format are NOT documented or supported by Microsoft. They
    were reverse-engineered from client behaviour and may change or disappear in
    any Outlook build without notice. The supported way to control Focused Inbox
    is the tenant-wide Exchange Online setting:
        Set-OrganizationConfig -FocusedInboxOn $false
    That tenant setting does not prevent a user from re-enabling Focused Inbox in
    the client, and does not create/update this registry value on its own - hence
    this script exists as a client-side companion, not a replacement.

    Also note: the value only exists for an account AFTER Outlook has loaded that
    account's mail settings at least once. On a brand-new profile/device this key
    will not exist yet, so this will correctly report "Not Compliant" (nothing to
    verify) rather than false-report "Compliant".

    Runs in the USER context (per-account, per-user setting).

#>

[CmdletBinding()]

Param (

)

$RegPath = 'HKCU:\SOFTWARE\Microsoft\Office\Outlook\Settings\Data'

try {

    if (!(Test-Path $RegPath)) {

        Write-Host "Not Compliant"
        Exit 1

    }

    $Properties = Get-Item -Path $RegPath -ErrorAction Stop |
        Select-Object -ExpandProperty Property |
        Where-Object { $_ -like '*_IsFocusedInboxEnabled' }

    if (-not $Properties -or $Properties.Count -eq 0) {

        Write-Host "Not Compliant"
        Exit 1

    }

    $AllDisabled = $true

    foreach ($PropertyName in $Properties) {

        $RawValue = Get-ItemProperty -Path $RegPath -Name $PropertyName -ErrorAction Stop |
            Select-Object -ExpandProperty $PropertyName

        try {
            $Parsed = $RawValue | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $AllDisabled = $false
            continue
        }

        if ($Parsed.value -ne $false) {
            $AllDisabled = $false
        }

    }

    if ($AllDisabled) {

        Write-Host "Compliant"
        Exit 0

    } else {

        Write-Host "Not Compliant"
        Exit 1

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}