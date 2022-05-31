 $SettingsArray = @"
BackgroundIntelligentTransfer
ClientPolicy
Cloud
ComplianceSettings
ComputerAgent
ComputerRestart
EndpointProtection
HardwareInventory
MeteredNetwork
MobileDevice
NetworkAccessProtection
PowerManagement
RemoteTools
SoftwareDeployment
SoftwareInventory
SoftwareMetering
SoftwareUpdates
StateMessaging
UserAndDeviceAffinity
"@ -split "`n" | ForEach-Object {$_.Trim()}

$ClientSettings = New-Object -TypeName System.Collections.ArrayList

foreach ($Setting in $SettingsArray) {
    $temp = [PSCustomObject]@{
        Setting = $Setting
    }
    (Get-CMClientSetting -Id 0 -Setting $Setting).GetEnumerator().ForEach({
        $temp | Add-Member -MemberType NoteProperty -Name $_.Key -Value $_.Value
    })
    [void]$ClientSettings.Add($temp)

} 
