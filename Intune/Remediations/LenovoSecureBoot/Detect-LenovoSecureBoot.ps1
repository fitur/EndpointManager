<#
.SYNOPSIS
    PowerShell script to detect whether Secure Boot is enabled in the BIOS on Lenovo devices.

.EXAMPLE
    .\Detect-LenovoSecureBoot.ps1

.DESCRIPTION
    This PowerShell script reads the Secure Boot setting through Lenovo's BIOS WMI
    interface (root\wmi : Lenovo_BiosSetting) and reports whether it is enabled.
    The BIOS setting decides compliance (not Confirm-SecureBootUEFI), so a device that
    has been remediated but not yet rebooted is reported as compliant. The OS-reported
    state is included in the output for information.

    Exit 0 = compliant (Secure Boot enabled, or device is not a supported Lenovo)
    Exit 1 = non-compliant (Secure Boot disabled, or detection itself failed)

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.1
    Creation Date:  2026-10-19
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-LenovoSecureBoot.ps1 / Remediate-LenovoSecureBoot.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Intune shows only the last line of output, so each exit path writes a single
    summary line immediately before exiting.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.0.1 - Summary lines use Write-Output. Header aligned with the repository standard.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

try {
    # Applicability: Lenovo only
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if ($Manufacturer -notmatch 'Lenovo') {
        Write-Output "Not applicable: Manufacturer is '$Manufacturer'."
        exit 0
    }

    # Lenovo BIOS WMI interface is missing on some models (e.g. many IdeaPads)
    $BiosClass = Get-CimClass -Namespace 'root\wmi' -ClassName 'Lenovo_BiosSetting' -ErrorAction SilentlyContinue
    if (-not $BiosClass) {
        Write-Output "Not supported: Lenovo_BiosSetting WMI class not found on this model."
        exit 0
    }

    # ThinkPad: "SecureBoot,Enable"  |  ThinkCentre: "Secure Boot,Enabled;[Optional:Disabled,Enabled]"
    $SecureBootSetting = Get-CimInstance -Namespace 'root\wmi' -ClassName 'Lenovo_BiosSetting' |
        Where-Object { $_.CurrentSetting -match '^\s*Secure\s?Boot\s*,' } |
        Select-Object -First 1

    if (-not $SecureBootSetting) {
        Write-Output "Not supported: No SecureBoot setting exposed in the Lenovo BIOS WMI interface."
        exit 0
    }

    $SettingName  = ($SecureBootSetting.CurrentSetting -split ',', 2)[0].Trim()
    $SettingValue = (($SecureBootSetting.CurrentSetting -split ',', 2)[1] -split ';')[0].Trim()

    # Informational only - reflects the current boot, not pending BIOS changes
    $OsState = try { [string](Confirm-SecureBootUEFI) } catch { 'Unknown' }

    if ($SettingValue -match '^Enabled?$') {
        Write-Output "Compliant: BIOS '$SettingName' = '$SettingValue' (OS reports Secure Boot: $OsState)."
        exit 0
    } elseif ($SettingValue -match '^Disabled?$') {
        Write-Output "Non-compliant: BIOS '$SettingName' = '$SettingValue' (OS reports Secure Boot: $OsState) - triggering remediation."
        exit 1
    } else {
        Write-Output "Non-compliant: Unexpected value for BIOS '$SettingName': '$SettingValue'."
        exit 1
    }
} catch {
    Write-Output "Detection failed: $($_.Exception.Message)"
    exit 1
}
