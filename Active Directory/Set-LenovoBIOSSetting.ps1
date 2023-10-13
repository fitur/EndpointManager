$SettingName = "SecureBoot"
$SettingValue = "Enable"
$SettingPassword = "syi02nw"

$Lenovo_SetBiosSetting = Get-WmiObject -Class Lenovo_SetBiosSetting -Namespace root/WMI
$Lenovo_BiosSetting = Get-WmiObject -Class Lenovo_BiosSetting -Namespace root/WMI
$Lenovo_BiosPasswordSettings = Get-WmiObject -Namespace root\wmi -Class Lenovo_BiosPasswordSettings
$Lenovo_SaveBiosSettings = Get-WmiObject -Namespace root\wmi -Class Lenovo_SaveBiosSettings

# BIOS-lösenord
if ($Lenovo_BiosPasswordSettings.PasswordState -ne 0) {
    $SettingPasswordSplat = ",$SettingPassword,ascii,us"
    $SavePasswordSplat = "$SettingPassword,ascii,us"
    Write-Output "BIOS är lösenordsskyddat. Splat blir $SavePasswordSplat"
} else {
    $SettingPasswordSplat = $null
    $SavePasswordSplat = $null
    Write-Output "BIOS är inte lösenordsskyddat. Splat blir $SavePasswordSplat"
}

# BIOS-inställning
$SettingState = ($Lenovo_BiosSetting | Where-Object {$_.CurrentSetting -match $SettingName} | Select-Object -ExpandProperty CurrentSetting) -split "$($SettingName),"
if ($SettingState -ne $SettingValue) {
    # Justera inställning
    $SettingResult = $Lenovo_SetBiosSetting.SetBiosSetting("$SettingName,$SettingValue$SettingPasswordSplat")
    if ($SettingResult.return -ne "Success") {
        Write-Output "Kunde inte justera inställning: $($SettingResult.return)."
    } else {
        Write-Output "Justerade inställning: $($SettingResult.return)."
    }

    # Spara inställning
    $SaveResult = $Lenovo_SaveBiosSettings.SaveBiosSettings("$SavePasswordSplat")
    if ($SettingResult.return -ne "Success") {
        Write-Output "Kunde inte spara inställning: $($SaveResult.return)."
    } else {
        Write-Output "Sparade inställning: $($SaveResult.return)."
    }
} else {
    Write-Output "Inställningen stämmer redan överens med förbestämda värdet."
}