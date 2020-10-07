try {
    Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
    #Set-location $SiteCode":" -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message
}

$Query = @"
select distinct SMS_R_System.Name, SMS_R_System.IPAddresses, SMS_R_System.SystemOUName, SMS_CombinedDeviceResources.CurrentLogonUser, SMS_G_System_SYSTEM_CONSOLE_USAGE.TopConsoleUser, SMS_G_System_COMPUTER_SYSTEM.UserName, SMS_G_System_COMPUTER_SYSTEM.Manufacturer, SMS_G_System_COMPUTER_SYSTEM.Model, SMS_G_System_PC_BIOS.SerialNumber, SMS_G_System_OPERATING_SYSTEM.Caption, SMS_G_System_OPERATING_SYSTEM.BuildNumber, SMS_G_System_X86_PC_MEMORY.TotalPhysicalMemory, SMS_R_System.LastLogonTimestamp
from SMS_R_System
left join SMS_CombinedDeviceResources on SMS_CombinedDeviceResources.Name = SMS_R_System.Name
left join SMS_G_System_SYSTEM_CONSOLE_USAGE on SMS_G_System_SYSTEM_CONSOLE_USAGE.ResourceID = SMS_R_System.ResourceId
left join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId
left join SMS_G_System_PC_BIOS on SMS_G_System_PC_BIOS.ResourceID = SMS_R_System.ResourceId
left join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceID = SMS_R_System.ResourceId
left join SMS_G_System_X86_PC_MEMORY on SMS_G_System_X86_PC_MEMORY.ResourceID = SMS_R_System.ResourceId
where SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=60) and AgentName = 'SMS_AD_SYSTEM_DISCOVERY_AGENT')) and SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=60) and AgentName = 'Heartbeat Discovery'))
"@

$Devices = Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query $Query

# Placeholder
$CMDeviceInfo = New-Object -TypeName System.Collections.ArrayList

foreach ($Device in $Devices) {
    if (![string]::IsNullOrEmpty($Device.SMS_G_System_SYSTEM_CONSOLE_USAGE.TopConsoleUser)) {
        $TempADPrimaryUserObject = Get-ADUser -Identity ($Device.SMS_G_System_SYSTEM_CONSOLE_USAGE.TopConsoleUser | Split-Path -Leaf) -Properties DisplayName, Office, Department, Description
    }
    if (![string]::IsNullOrEmpty($Device.SMS_CombinedDeviceResources.CurrentLogonUser)) {
        $TempADCurrentUserObject = Get-ADUser -Identity ($Device.SMS_CombinedDeviceResources.CurrentLogonUser | Split-Path -Leaf) -Properties DisplayName, Office, Department, Description
    }

    $temp = New-Object -TypeName PSCustomObject
    $temp | Add-Member -MemberType NoteProperty -Name "Computer" -Value $Device.SMS_R_System.Name
    $temp | Add-Member -MemberType NoteProperty -Name "Computer OU" -Value ($Device.SMS_R_System.SystemOUName | Select-Object -Last 1)
    #$temp | Add-Member -MemberType NoteProperty -Name "IPv4 Address" -Value $TempADDeviceObject.IPv4Address

    if (![string]::IsNullOrEmpty($Device.SMS_G_System_SYSTEM_CONSOLE_USAGE.TopConsoleUser)) {
        $temp | Add-Member -MemberType NoteProperty -Name "Primary User" -Value $Device.SMS_G_System_SYSTEM_CONSOLE_USAGE.TopConsoleUser
    }

    if (!$null -eq $TempADPrimaryUserObject) {
        $temp | Add-Member -MemberType NoteProperty -Name "Pimary User Name" -Value $TempADPrimaryUserObject.DisplayName
        $temp | Add-Member -MemberType NoteProperty -Name "Primary User Department" -Value $TempADPrimaryUserObject.Department
        $temp | Add-Member -MemberType NoteProperty -Name "Primary User Description" -Value $TempADPrimaryUserObject.Description
    }

    if (![string]::IsNullOrEmpty($Device.SMS_G_System_COMPUTER_SYSTEM.UserName)) {
        $temp | Add-Member -MemberType NoteProperty -Name "Current User" -Value $Device.SMS_G_System_COMPUTER_SYSTEM.UserName
    }

    if (!$null -eq $TempADCurrentUserObject) {
        $temp  | Add-Member -MemberType NoteProperty -Name "Current User Name" -Value $TempADCurrentUserObject.DisplayName
        $temp | Add-Member -MemberType NoteProperty -Name "Current User Department" -Value $TempADCurrentUserObject.Department
        $temp | Add-Member -MemberType NoteProperty -Name "Current User Description" -Value $TempADCurrentUserObject.Description
    }

    $temp | Add-Member -MemberType NoteProperty -Name "Last Logon" -Value (Get-Date ("{0}-{1}-{2}" -f $Device.SMS_R_System.LastLogonTimestamp.Substring(0,4), $Device.SMS_R_System.LastLogonTimestamp.Substring(4,2), $Device.SMS_R_System.LastLogonTimestamp.Substring(6,2)) -Format d)
    $temp | Add-Member -MemberType NoteProperty -Name "Operating System Name" -Value $Device.SMS_G_System_OPERATING_SYSTEM.Caption
    $temp | Add-Member -MemberType NoteProperty -Name "Operating System Build Version" -Value $Device.SMS_G_System_OPERATING_SYSTEM.BuildNumber
    $temp | Add-Member -MemberType NoteProperty -Name "Total Memory" -Value $Device.SMS_G_System_X86_PC_MEMORY.TotalPhysicalMemory
    $temp | Add-Member -MemberType NoteProperty -Name "Manufacturer" -Value $Device.SMS_G_System_COMPUTER_SYSTEM.Manufacturer
    $temp | Add-Member -MemberType NoteProperty -Name "Model" -Value $Device.SMS_G_System_COMPUTER_SYSTEM.Model
    $temp | Add-Member -MemberType NoteProperty -Name "Serial Number" -Value $Device.SMS_G_System_PC_BIOS.SerialNumber

    $CMDeviceInfo.Add($temp)
    Remove-Variable temp
} 
