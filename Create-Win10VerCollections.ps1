 begin {
    try {
        # Load CM module
        Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
    }
}
process {
    tru {
        # Get Windows 10 release history from Microsoft
        $W10RelHistoryURI = "https://winreleaseinfoprod.blob.core.windows.net/winreleaseinfoprod/en-US.html"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $W10RelHistory = Invoke-WebRequest -Uri $W10RelHistoryURI
        $SATable = $W10RelHistory.ParsedHtml.getElementsByTagName("TABLE") | Where-Object {$_.OuterText -like "*Microsoft recommends*"} | Select-Object -First 1
        $W10Versions = New-Object -TypeName System.Collections.ArrayList
        foreach ($SARow in $SATable.rows) {
            $SARow | Where-Object {$_.childNodes[1].outerText -eq "Semi-Annual Channel"} | ForEach-Object {
                $temp = [PSCustomObject]@{
                    Version = $_.childNodes[0].outerText
                    OSBuild = $_.childNodes[3].outerText
                    EOL = $_.childNodes[6].outerText
                }
                [void]$W10Versions.Add($temp)
            }
        }
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    }

    ## Create limiting collection sub-directory if required
    if (!(Get-Item -Path $SiteCode":\DeviceCollection\Inventory Collections\Windows Version" -ErrorAction SilentlyContinue)) {
        try {
            ## Create new inventory collection sub-directory
            New-Item -Path $SiteCode":\DeviceCollection" -Name "Inventory Collections" -ItemType Directory -ErrorAction Stop
            New-Item -Path $SiteCode":\DeviceCollection\Inventory Collections" -Name "Windows Version" -ItemType Directory -ErrorAction Stop

        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
        }
    }


    # Create device collections in CM
    foreach ($W10Version in $W10Versions) {
        $Query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_OPERATING_SYSTEM on SMS_G_System_OPERATING_SYSTEM.ResourceId = SMS_R_System.ResourceId where SMS_G_System_OPERATING_SYSTEM.Name like 'Microsoft Windows 10 Enterprise%' and SMS_G_System_OPERATING_SYSTEM.Version = '$(([System.version]$W10Version.OSBuild).Major)'"
        $Collection = New-CMCollection -CollectionType Device -Comment "End-of-life: $($W10Version.EOL)" -LimitingCollectionId "SMS00001" -Name "All Windows 10 - $($W10Version.Version)" -RefreshType Periodic -RefreshSchedule (New-CMSchedule -Start (Get-Date).Date -RecurInterval Days -RecurCount 1)
        Add-CMDeviceCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -RuleName "Windows 10 version" -QueryExpression $Query
        Remove-Variable -Name Query -ErrorAction SilentlyContinue

        try {
            ## Move collection to new sub-directory
            Move-CMObject -ObjectId $Collection.CollectionID -FolderPath $SiteCode":\DeviceCollection\Inventory Collections\Windows Version" -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
        }
    }
}
 
