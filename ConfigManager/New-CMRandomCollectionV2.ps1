try {
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
    Set-location $SiteCode":" -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message
}

$CollectionPrefix = "CoMgmt Migration Batch"
$LimitingCollection = "P010018F"
$Queries = "0","1-2", "3-5", "6-9", "a-z"
$QueryPrefix = 'select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.SMBIOSGUID like '

foreach ($Query in $Queries) {
    $Collection  = New-CMCollection -CollectionType Device -LimitingCollectionId $LimitingCollection -Name ("{0} {1}" -f $CollectionPrefix, $Queries.IndexOf($Query)) -RefreshType Periodic -RefreshSchedule (New-CMSchedule -RecurInterval Days -RecurCount 1)
    $Collection | Add-CMDeviceCollectionQueryMembershipRule -RuleName "Query" -QueryExpression ('{0}"%[{1}]"' -f $QueryPrefix, $Query)
}
