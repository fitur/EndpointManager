<#

.SYNOPSIS
    PowerShell script to enable Secure Boot in the BIOS on Lenovo devices.

.EXAMPLE
    .\Remediate-LenovoSecureBoot.ps1

.DESCRIPTION
    This PowerShell script enables Secure Boot through Lenovo's BIOS WMI interface
    (Lenovo_SetBiosSetting) and commits the change (Lenovo_SaveBiosSettings). The change
    takes effect at the next reboot - the script does not reboot the device.

    BitLocker is suspended for one reboot before the BIOS change, since changing Secure
    Boot alters the PCR7 measurement and would otherwise trigger BitLocker recovery.

    Devices with a BIOS supervisor password are not changed - the script reports this
    and exits 1.

    Exit 0 = Secure Boot enabled in BIOS (reboot pending), already enabled, or not applicable
    Exit 1 = remediation failed

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2026-10-19
    Last Updated:   2026-10-19
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-LenovoSecureBoot.ps1 / Remediate-LenovoSecureBoot.ps1
    Intune Remediation settings: "Run this script using the logged-on credentials" = No,
    "Run script in 64-bit PowerShell" = Yes.

    Secure Boot requires UEFI boot mode. If CSM/Legacy boot is enabled, the BIOS may
    reject the change.

    Intune shows only the last line of output, so each exit path writes a single
    summary line immediately before exiting.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.
#>

$ErrorActionPreference = 'Stop'

$BitLockerSuspended = $false

try {
    # Applicability: Lenovo only
    $Manufacturer = (Get-CimInstance -ClassName Win32_ComputerSystem).Manufacturer
    if ($Manufacturer -notmatch 'Lenovo') {
        Write-Host "Not applicable: Manufacturer is '$Manufacturer'."
        exit 0
    }

    # Lenovo BIOS WMI interface is missing on some models (e.g. many IdeaPads)
    $BiosClass = Get-CimClass -Namespace 'root\wmi' -ClassName 'Lenovo_BiosSetting' -ErrorAction SilentlyContinue
    if (-not $BiosClass) {
        Write-Host "Not supported: Lenovo_BiosSetting WMI class not found on this model."
        exit 0
    }

    # ThinkPad: "SecureBoot,Enable"  |  ThinkCentre: "Secure Boot,Enabled;[Optional:Disabled,Enabled]"
    $SecureBootSetting = Get-CimInstance -Namespace 'root\wmi' -ClassName 'Lenovo_BiosSetting' |
        Where-Object { $_.CurrentSetting -match '^\s*Secure\s?Boot\s*,' } |
        Select-Object -First 1

    if (-not $SecureBootSetting) {
        Write-Host "Not supported: No SecureBoot setting exposed in the Lenovo BIOS WMI interface."
        exit 0
    }

    $SettingName  = ($SecureBootSetting.CurrentSetting -split ',', 2)[0].Trim()
    $SettingValue = (($SecureBootSetting.CurrentSetting -split ',', 2)[1] -split ';')[0].Trim()

    if ($SettingValue -match '^Enabled?$') {
        Write-Host "Already compliant: BIOS '$SettingName' = '$SettingValue'. No change made."
        exit 0
    }

    # Use the same value format as the model reports ("Disable" -> "Enable", "Disabled" -> "Enabled")
    $TargetValue = if ($SettingValue -match 'd$') { 'Enabled' } else { 'Enable' }

    # Supervisor (2) or System Management (64) password blocks unauthenticated BIOS changes
    $PasswordSettings = Get-CimInstance -Namespace 'root\wmi' -ClassName 'Lenovo_BiosPasswordSettings' -ErrorAction SilentlyContinue
    if ($PasswordSettings -and ($PasswordSettings.PasswordState -band (2 -bor 64))) {
        Write-Host "Remediation failed: BIOS supervisor/system management password is set (PasswordState = $($PasswordSettings.PasswordState)). Secure Boot cannot be changed without it."
        exit 1
    }

    # Suspend BitLocker for one reboot so the Secure Boot change does not trigger recovery
    $OsVolume = Get-BitLockerVolume -MountPoint $env:SystemDrive -ErrorAction SilentlyContinue
    if ($OsVolume -and $OsVolume.ProtectionStatus -eq 'On') {
        Suspend-BitLocker -MountPoint $env:SystemDrive -RebootCount 1 | Out-Null
        $BitLockerSuspended = $true
    }

    # Apply the setting
    $SetResult = Get-CimInstance -Namespace 'root\wmi' -ClassName 'Lenovo_SetBiosSetting' |
        Invoke-CimMethod -MethodName 'SetBiosSetting' -Arguments @{ parameter = "$SettingName,$TargetValue" }

    if ($SetResult.return -ne 'Success') {
        throw "SetBiosSetting '$SettingName,$TargetValue' returned '$($SetResult.return)'."
    }

    # Commit - without this the change is discarded at reboot
    $SaveResult = Get-CimInstance -Namespace 'root\wmi' -ClassName 'Lenovo_SaveBiosSettings' |
        Invoke-CimMethod -MethodName 'SaveBiosSettings' -Arguments @{ parameter = '' }

    if ($SaveResult.return -ne 'Success') {
        throw "SaveBiosSettings returned '$($SaveResult.return)'."
    }

    $BitLockerNote = if ($BitLockerSuspended) { ' BitLocker suspended for 1 reboot.' } else { '' }
    Write-Host "Remediated: BIOS '$SettingName' set to '$TargetValue'. Reboot required to take effect.$BitLockerNote"
    exit 0
} catch {
    # Resume BitLocker if the BIOS change did not go through
    if ($BitLockerSuspended) {
        try { Resume-BitLocker -MountPoint $env:SystemDrive | Out-Null } catch { }
    }
    Write-Host "Remediation failed: $($_.Exception.Message)"
    exit 1
}
