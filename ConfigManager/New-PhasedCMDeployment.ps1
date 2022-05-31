Import-Module ($env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
$SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
Set-location -Path $SiteCode":" -ErrorAction Stop

$Application = Get-CMApplication -Name "Printix*"
$StartDate = "2022-02-23"
$LimitingCollection = Get-CMCollection -Name "All Swedish Computers"

$QuerySwap = "0","1-2","3-5","6-9","A-Z"
$QueryBase = 'select distinct SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.SMSUniqueIdentifier like'
$CollectionArray = New-Object -TypeName System.Collections.ArrayList

foreach ($Object in $QuerySwap) {
    $Collection = New-CMDeviceCollection -Name ("{0} - Device - Phase {1}" -f $Application.LocalizedDisplayName, ($QuerySwap.IndexOf($Object)+1)) -LimitingCollectionId $LimitingCollection.CollectionID -RefreshType Periodic -RefreshSchedule (New-CMSchedule -RecurInterval Days -RecurCount 1)
    $Collection | Add-CMDeviceCollectionQueryMembershipRule -QueryExpression ('{0} "GUID:%[{1}]"' -f $QueryBase, $Object) -RuleName "Query: GUID $Object"
    $CollectionArray.Add($Collection) | Out-Null
}

foreach ($Collection in $CollectionArray) {
    $Application | New-CMApplicationDeployment -AvailableDateTime (Get-Date -Format d) -DeadlineDateTime ((Get-Date $StartDate).AddDays($CollectionArray.IndexOf($Collection)*7)) -Collection $Collection -AllowRepairApp $true -TimeBaseOn Utc -UserNotification DisplaySoftwareCenterOnly -DeployAction Install -DeployPurpose Required
}
