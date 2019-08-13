Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') 
$SiteCode = Get-PSDrive -PSProvider CMSITE 
Set-location $SiteCode":" 

Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query 'select distinct Manufacturer, Model from SMS_G_System_COMPUTER_SYSTEM' | Where-Object {
    (
        ($_.Model -notmatch "Virtual") -and
        ($_.Model -notlike "")
    ) -and
    (
        ($_.Manufacturer -match "Dell") -or
        ($_.Manufacturer -match "Hewlett") -or
        ($_.Manufacturer -match "HP") -or
        ($_.Manufacturer -match "Microsoft")
    )
} | ForEach-Object {
    ## Gather manufacturer details and rename
    switch -Wildcard ($_.Manufacturer) {
        "Dell*" {
            $Manufacturer = "Dell"
        }
        "Hewlett*" {
            $Manufacturer = "Hewlett-Packard"
        }
        "HP" {
            $Manufacturer = "Hewlett-Packard"
        }
        "Microsoft*" {
            $Manufacturer = "Microsoft"
        }
    }

    ## Gather model details and rename
    switch -Wildcard ($_.Model) {
        "*HP*" {
            $Model = $_ -replace "HP ",""
        }
        default {
            $Model = $_
        }
    }

    ## Create device string for naming purposes
    $Device = ("{0} {1}" -f $Manufacturer, $Model)

    ## Create collection if not exists
    if (!(Get-CMDeviceCollection -Name $Device)) {

        ## Inform which device is being parsed
        Write-Host "Creating collection for $Device"

        $Collection = New-CMDeviceCollection -Name $Device -LimitingCollectionId SMS00001 -RefreshSchedule ($Schedule = New-CMSchedule -Start "01/01/2016" -RecurInterval Days -RecurCount 1) -RefreshType Periodic -ErrorAction Stop

        ## Add query to above collection
        Add-CMDeviceCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -RuleName $_.Model -QueryExpression "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where SMS_G_System_COMPUTER_SYSTEM.Manufacturer = ""$($_.Manufacturer)"" and SMS_G_System_COMPUTER_SYSTEM.Model = ""$($_.Model)""" -ErrorAction Stop
        #Move-CMObject -ObjectId $Collection.CollectionID -FolderPath "C01:\DeviceCollection\_Client\4. Hardware Inventory\Computers Based On Model\$Manufacturer" -ErrorAction SilentlyContinue
    }
}
