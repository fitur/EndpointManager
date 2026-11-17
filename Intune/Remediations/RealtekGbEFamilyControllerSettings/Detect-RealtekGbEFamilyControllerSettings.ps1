<#
.SYNOPSIS
    Detects power-saving settings on Realtek USB GbE Family Controller adapters that cause
    intermittent disconnects.

.EXAMPLE
    .\Detect-RealtekGbEFamilyControllerSettings.ps1

.DESCRIPTION
    The Realtek USB GbE Family Controller driver (common in USB-C docks and dongles)
    enables Green Ethernet and Energy-Efficient Ethernet by default, which causes
    intermittent link drops. The script checks these advanced properties on every
    matching adapter:

        *EEE                    = 0  (Energy-Efficient Ethernet off)
        *PriorityVLANTag        = 3  (Priority and VLAN enabled)
        EnableExtraPowerSaving  = 0
        EnableGreenEthernet     = 0

    A property the driver does not expose is treated as not applicable.

    Exit 0 = compliant (all exposed properties correct, or no matching adapter)
    Exit 1 = non-compliant (one or more properties differ, or detection itself failed)

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
    - Only adapters connected at detection time are checked. A dock that is unplugged
      during the run is checked on the next run.

    Intune shows only the last line of output, so each exit path writes a single
    summary line immediately before exiting.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Evaluates each matching adapter separately (with two docks attached, the
            values were previously compared as an array). The compliant path writes a
            summary line and exits 0 explicitly; all output uses Write-Output instead
            of Write-Verbose/Write-Warning so it reaches the Intune report.
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

    $Incorrect = @()

    foreach ($Adapter in $Adapters) {
        foreach ($Keyword in $DesiredSettings.Keys) {
            $Property = Get-NetAdapterAdvancedProperty -Name $Adapter.Name -RegistryKeyword $Keyword -ErrorAction SilentlyContinue

            # Property not exposed by this driver version - nothing to enforce
            if (-not $Property) { continue }

            $Current = [string]($Property.RegistryValue | Select-Object -First 1)
            if ($Current -ne $DesiredSettings[$Keyword]) {
                $Incorrect += "$($Adapter.Name): $Keyword=$Current"
            }
        }
    }

    if ($Incorrect.Count -gt 0) {
        Write-Output "Non-compliant: $($Incorrect -join '; ') - triggering remediation."
        exit 1
    }

    Write-Output "Compliant: $($Adapters.Count) Realtek USB GbE adapter(s) correctly configured."
    exit 0
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
