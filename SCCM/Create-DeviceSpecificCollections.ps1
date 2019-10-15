function Import-CMEnvironment {
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning  -Message $_.Exception.Message
    }
}

function Get-CMDeviceModels {
    process {
        try {
            $ModelData = Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query 'select distinct Manufacturer, Model from SMS_G_System_COMPUTER_SYSTEM' -ErrorAction Stop | Where-Object {
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
            }
        }
        catch [System.Exception] {
            Write-Warning  -Message $_.Exception.Message
        }
    }
    end {
        return $ModelData
    }
}


function New-CMLimitingCollection {
    param (
        # Specifies the limiting collection
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "Limiting collection ID.")]
        [ValidateNotNullOrEmpty()]
        [string]$LimitingCollection = 'SMS00001',

        # Specifies the last active days limit
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "Number of days to be active.")]
        [ValidateNotNullOrEmpty()]
        [int]$ActiveDays = 31,

        # Specifies the name of the limiting collection
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "Name of limiting collection.")]
        [ValidateNotNullOrEmpty()]
        [string]$CollectionName = "All Active Computers Last $ActiveDays Days"
    )
    process {
        try {
            if ($null -eq ($NewCollection = Get-CMCollection -Name $CollectionName)) {
                $Query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=$ActiveDays) and AgentName = 'SMS_AD_SYSTEM_DISCOVERY_AGENT')) and SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=$ActiveDays) and AgentName = 'Heartbeat Discovery'))"
                New-CMCollection -Name $CollectionName -CollectionType Device -LimitingCollectionId $LimitingCollection -Comment "Online last $ActiveDays days" -RefreshSchedule (New-CMSchedule -Start "$((Get-Date).Year)-01-01" -RecurInterval Days -RecurCount 1) -RefreshType Periodic -ErrorAction Stop
                Add-CMDeviceCollectionQueryMembershipRule -CollectionName $CollectionName -RuleName "Heartbeat last $ActiveDays days" -QueryExpression $Query -ErrorAction Stop
            }
            else {
                throw "Collection ""$CollectionName"" already exist. Returing information."
            }
        }
        catch [System.Exception] {
            Write-Warning  -Message $_.Exception.Message
        }
    }
    end {
        return $NewCollection
    }
}

function New-CMDeviceCollectionPerModel {
    [CmdletBinding()]
    param (
        # Specifies the name of the limiting collection
        [Parameter(Mandatory = $true,
        ValueFromPipeline = $true,
        HelpMessage = "Array of model objects")]
        [ValidateNotNullOrEmpty()]
        $Models,

        # Specifies the name of the sub-directory
        [Parameter(Mandatory = $true,
        ValueFromPipeline = $true,
        HelpMessage = "CM sub-directory")]
        [ValidateNotNullOrEmpty()]
        $SubDirectory        
    )
    
    begin {
        ## Load environment
        Import-CMEnvironment
        
        ## Create new environmental variables
        $CurrentCollections = Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query 'select Name, LimitToCollectionID from SMS_Collection'
        $LimitingCollection = New-CMLimitingCollection
    }
    
    process {
        $Models | ForEach-Object {
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
                    $Model = $_ -replace "HP ", ""
                }
                default {
                    $Model = $_
                }
            }
        
            ## Create device string for naming purposes
            $DeviceCollection = ("{0} {1}" -f $Manufacturer, $Model)
        
            ## Create collection if not exists
            if ($DeviceCollection -notin $CurrentCollections) {
        
                ## Inform which device is being parsed
                Write-Host "Creating collection for $DeviceCollection"
        
                $Collection = New-CMDeviceCollection -Name $DeviceCollection -LimitingCollectionId $LimitingCollection.CollectionID -RefreshSchedule (New-CMSchedule -Start "$((Get-Date).Year)-01-01" -RecurInterval Days -RecurCount 1) -RefreshType Periodic -ErrorAction Stop
        
                ## Add query to above collection
                Add-CMDeviceCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -RuleName $_.Model -QueryExpression "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where SMS_G_System_COMPUTER_SYSTEM.Manufacturer = ""$($_.Manufacturer)"" and SMS_G_System_COMPUTER_SYSTEM.Model = ""$($_.Model)""" -ErrorAction Stop
                
                ## Move collection to new sub-directory
                Move-CMObject -ObjectId $Collection.CollectionID -FolderPath $SiteCode":\DeviceCollection\$SubDirectory" -ErrorAction SilentlyContinue
            }
        }
    }
}