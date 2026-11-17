<#
.SYNOPSIS
    Disables power-saving settings on Realtek USB GbE Family Controller adapters that cause
    intermittent disconnects.

.EXAMPLE
    .\Remediate-RealtekGbEFamilyControllerSettings.ps1

.DESCRIPTION
    Sets these advanced properties on every matching adapter where the driver exposes
    them and the current value differs:

        *EEE                    = 0  (Energy-Efficient Ethernet off)
        *PriorityVLANTag        = 3  (Priority and VLAN enabled)
        EnableExtraPowerSaving  = 0
        EnableGreenEthernet     = 0

    Changes are written without restarting the adapter, then each changed adapter is
    restarted once so the new values take effect.

    Exit 0 = all differing properties set (or no matching adapter)
    Exit 1 = remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2022-05-31
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-RealtekGbEFamilyControllerSettings.ps1 / Remediate-RealtekGbEFamilyControllerSettings.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Known limitations:
    - Restarting the adapter drops the wired connection for a few seconds.
    - 1.0.0 never changed anything (see Changelog), so 1.1.0 is the first version that
      actually writes these settings. Pilot it before broad rollout.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Removed a hard-coded -WhatIf on Set-NetAdapterAdvancedProperty, which meant
            1.0.0 only simulated the change and the pair re-triggered on every run.
            Evaluates each matching adapter separately, restarts each changed adapter
            once instead of once per property, and writes a summary line before exit.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$AdapterPattern  = 'Realtek USB GbE Family Controller*'
$DesiredSettings = [ordered]@{
    '*EEE'                   = '0'
    '*PriorityVLANTag'       = '3'
    'EnableExtraPowerSaving' = '0'
    'EnableGreenEthernet'    = '0'
}

try {
    $Adapters = @(Get-NetAdapter | Where-Object { $_.InterfaceDescription -like $AdapterPattern })

    if ($Adapters.Count -eq 0) {
        Write-Output "Not applicable: no '$AdapterPattern' adapter present."
        exit 0
    }

    $Changed = @()

    foreach ($Adapter in $Adapters) {
        $AdapterChanged = $false

        foreach ($Keyword in $DesiredSettings.Keys) {
            $Property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $Keyword -ErrorAction SilentlyContinue
            if (-not $Property) { continue }

            $Current = [string]($Property.RegistryValue | Select-Object -First 1)
            if ($Current -ne $DesiredSettings[$Keyword]) {
                # -NoRestart: collect all changes, then restart the adapter once below
                Set-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $Keyword -RegistryValue $DesiredSettings[$Keyword] -NoRestart
                $Changed += "$($Adapter.Name): $Keyword $Current->$($DesiredSettings[$Keyword])"
                $AdapterChanged = $true
            }
        }

        if ($AdapterChanged) {
            Restart-NetAdapter -Name $Adapter.Name -Confirm:$false
        }
    }

    if ($Changed.Count -eq 0) {
        Write-Output "Remediated: nothing to change on $($Adapters.Count) adapter(s)."
    } else {
        Write-Output "Remediated: $($Changed -join '; ')."
    }
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
