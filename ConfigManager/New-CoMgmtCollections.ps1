# Load CM PS module and connect to environment
try {
    Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
    Set-location $SiteCode":" -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message
}

# Connect to AzureAD environment
try {
    Connect-AzureAD -TenantId $AADTenant.TenantID -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message
}

$CMWorkloadCollectionPrefix = "Co-Management Workload"
$CMFolderName = "Cloud"
$CMLimitingCollection = "SMS00001"
$AADWorkloadGroupPrefix = "AZ-MDM-Role-Device"
$AADTenant = Get-CMAADTenant -Name "lindahl"

if (!($CMFolder = Get-CMFolder -Name $CMFolderName -ParentFolderPath DeviceCollection)) {
    Write-Output "Creating CM folder $CMFolderName"
    $CMFolder = New-CMFolder -Name $CMFolderName -ParentFolderPath DeviceCollection
}

$Groups = @("Co-Management Pilot", "Co-Management Production", "Co-Management Exclusions", "Co-Management Enrollment")
$Groups | ForEach-Object {
    try {
        if (!($Collection = Get-CMCollection -Name $_)) {
            Write-Output "Creating CM Co-Management group collection $_"
            $Collection = New-CMCollection -CollectionType Device -Name $_ -LimitingCollection (Get-CMCollection -Id $CMLimitingCollection) -RefreshType Periodic -RefreshSchedule (New-CMSchedule -RecurInterval Days -RecurCount 1) -ErrorAction Stop
            $Collection | Move-CMObject -FolderPath "$($SiteCode.SiteCode):\DeviceCollection\$($CMFolder.Name)" -ErrorAction SilentlyContinue
        }
    }
    catch [System.Exception]
    {
        Write-Warning $_.Exception
    }
}

$Workloads = @("Compliance Policies", "Device Configuration", "Endpoint Protection", "Resource Access Policies", "Client Apps", "Office Click-to-Run Apps", "Windows Update Policies")
$Workloads | ForEach-Object {
    try {
        # Create CM collection
        if (!($Collection = Get-CMCollection -Name ("{0} - {1}" -f $CMWorkloadCollectionPrefix, $_))) {
            Write-Output "Creating CM Co-Management workload collection $("{0} - {1}" -f $CMWorkloadCollectionPrefix, $_)"
            $Collection = New-CMCollection -CollectionType Device -Name ("{0} - {1}" -f $CMWorkloadCollectionPrefix, $_) -LimitingCollection (Get-CMCollection -Id $CMLimitingCollection) -RefreshType Periodic -RefreshSchedule (New-CMSchedule -RecurInterval Days -RecurCount 1) -ErrorAction Stop
            Write-Output "Adding include membership to collection $_"
            $Collection | Add-CMDeviceCollectionIncludeMembershipRule -IncludeCollectionName "Co-Management Pilot"
            Write-Output "Moving collection $_ to $CMFolderName"
            $Collection | Move-CMObject -FolderPath "$($SiteCode.SiteCode):\DeviceCollection\$($CMFolder.Name)" -ErrorAction SilentlyContinue
        }
        # Create AzureAD group
        if (!($AADGroup = Get-AzureADGroup -SearchString ("{0}-{1}" -f $AADWorkloadGroupPrefix, ($_ -replace " ","")))) {
            Write-Output "Creating AAD Co-Management group $("{0}-{1}" -f $AADWorkloadGroupPrefix, ($_ -replace ' ',''))"
            $AADGroup = New-AzureADGroup -DisplayName ("{0}-{1}" -f $AADWorkloadGroupPrefix, ($_ -replace " ","")) -MailEnabled $false -SecurityEnabled $true -MailNickName "NotSet" -ErrorAction Stop
            #Write-Output "Setting cloud sync to collection $_"
            #Set-CMCollectionCloudSync -InputObject $Collection -AddGroupName $AADGroup.DisplayName -EnableAssignEndpointSecurityPolicy $true -TenantObject $AADTenant -ErrorAction Stop
        }
    }
    catch [System.Exception]
    {
        Write-Warning $_.Exception
    }
}