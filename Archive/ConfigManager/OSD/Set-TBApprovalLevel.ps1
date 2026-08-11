# Create payload
$TBFix = {
		$RegistryKey = "SYSTEM\CurrentControlSet\Services\ThunderboltService\TbtServiceSettings"
    $ACLinfo = Get-Acl "HKLM:\$RegistryKey"
    $RegKeyDotNETItem = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($RegistryKey,[Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,[System.Security.AccessControl.RegistryRights]::ChangePermissions)
    $DotNET_ACL = $RegKeyDotNETItem.GetAccessControl()
    $DotNET_AccessRule = New-Object System.Security.AccessControl.RegistryAccessRule ("System","FullControl","Allow")
    $DotNET_ACL.SetAccessRule($DotNET_AccessRule)
    $RegKeyDotNETItem.SetAccessControl($DotNET_ACL)
    Set-ItemProperty -Path "HKLM:\$RegistryKey" -Name "ApprovalLevel" -Value 1 -Force
    Set-Acl -AclObject $ACLinfo -Path "HKLM:\$RegistryKey"
}

# Create, run & unregister task if value doesn't exist
if (!(Test-Path -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ThunderboltService\TbtServiceSettings")) {
    New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ThunderboltService\TbtServiceSettings" -Force
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ThunderboltService\TbtServiceSettings" -Name "ApprovalLevel" -Value 1 -Force
} else {
    $Action = New-ScheduledTaskAction -Execute powershell.exe -Argument "-noprofile -encodedcommand $([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($TBFix)))"
    $Task = Register-ScheduledTask -Action $Action -TaskName ([guid]::NewGuid().Guid) -RunLevel Highest -User S-1-5-18 -Force
    $Task | Start-ScheduledTask
    $Task | Unregister-ScheduledTask -Confirm:$false
}

# Wait for registry to refresh
Wait-Event -Timeout 5

# Verify
if ((Get-ItemPropertyValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\ThunderboltService\TbtServiceSettings" -Name "ApprovalLevel") -eq 1) {
    exit 0
} else {
    Write-Verbose "Thunderbolt non-admin authorization change failed."; exit 1
}
