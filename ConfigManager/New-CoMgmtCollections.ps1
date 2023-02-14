try {
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
    Set-location $SiteCode":" -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message
}

$CMWorkloadCollectionPrefix = "Co-Management Workload"
$CMCollectionDirectory = "$($SiteCode.SiteCode):\DeviceCollection\Co-Management"

$Groups = @("Co-Management Pilot", "Co-Management Production", "Co-Management Exclusions", "Co-Management Enrollment")
$Groups | ForEach-Object {
    try {
        $Collection = New-CMCollection -CollectionType Device -Name $_ -LimitingCollection (Get-CMCollection -Id "SMS00001") -RefreshType Periodic -RefreshSchedule (New-CMSchedule -RecurInterval Days -RecurCount 1)
        $Collection | Move-CMObject -FolderPath $CMCollectionDirectory -ErrorAction SilentlyContinue
    }
    catch [System.Exception]
    {
        Write-Warning $_.Exception
    }
}

$Workloads = @("Compliance Policies", "Device Configuration", "Endpoint Protection", "Resource Access Policies", "Client Apps", "Office Click-to-Run Apps", "Windows Update Policies")
$Workloads | ForEach-Object {
    try {
        if (!($Collection = Get-CMCollection -Name ("{0} - {1}" -f $CMWorkloadCollectionPrefix, $_))) {
            $Collection = New-CMCollection -CollectionType Device -Name ("{0} - {1}" -f $CMWorkloadCollectionPrefix, $_) -LimitingCollection (Get-CMCollection -Id "SMS00001") -RefreshType Periodic -RefreshSchedule (New-CMSchedule -RecurInterval Days -RecurCount 1) -ErrorAction Stop
            $Collection | Move-CMObject -FolderPath $CMCollectionDirectory -ErrorAction SilentlyContinue
        }
        $Collection | Add-CMDeviceCollectionIncludeMembershipRule -IncludeCollectionName "Co-management Pilot"
    }
    catch [System.Exception]
    {
        Write-Warning $_.Exception
    }
}