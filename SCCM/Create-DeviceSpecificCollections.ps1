function Import-CMEnvironment {
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    }
}

function Show-Feedback {
    param (
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Text
    )
    Write-Output ("{0}: {1}" -f (Get-Date -Format g), $Text)
}

function Get-CMDeviceModels {
    begin {
        ## Load environment
        Import-CMEnvironment
    }
    process {
        try {
            $ModelData = Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query 'select distinct Manufacturer, Model from SMS_G_System_COMPUTER_SYSTEM' -ErrorAction Stop | Where-Object {
                (
                    ($_.Model -notmatch "Virtual") -and
                    ($_.Model -notlike "")
                )
            }
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
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
        [string]$CollectionName = "All Active Computers Last $ActiveDays Days",

        # Specifies the name of the limiting collection sub-directory
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "Name of limiting collection sub-directory.")]
        [ValidateNotNullOrEmpty()]
        [string]$CollectionSubDirectory = "Limiting Collections"
    )
    begin {
        ## Load environment
        Import-CMEnvironment

        ## Get collection info
        $Collection = Get-CMCollection -Name $CollectionName -ErrorAction SilentlyContinue
    }
    process {
        try {
            if ($null -eq $Collection) {
                ## Create new collection
                $Collection = New-CMCollection -Name $CollectionName -CollectionType Device -LimitingCollectionId $LimitingCollection -Comment "Online last $ActiveDays days" -RefreshSchedule (New-CMSchedule -Start "$((Get-Date).Year)-01-01" -RecurInterval Days -RecurCount 1) -RefreshType Periodic -ErrorAction Stop

                ## Add query rule to collection
                if ((Get-CMDiscoveryMethod | Where-Object {$_.ComponentName -eq "SMS_AD_SYSTEM_DISCOVERY_AGENT"} | Select-Object -ExpandProperty Flag) -eq 6) {
                    $Query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=$ActiveDays) and AgentName = 'SMS_AD_SYSTEM_DISCOVERY_AGENT')) and SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=$ActiveDays) and AgentName = 'Heartbeat Discovery'))"
                } else {
                    $Query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System where SMS_R_System.Name in (select Name from SMS_R_System where ((DATEDIFF(day, SMS_R_SYSTEM.AgentTime, getdate()) <=$ActiveDays) and AgentName = 'Heartbeat Discovery'))"
                }
                Add-CMDeviceCollectionQueryMembershipRule -CollectionName $CollectionName -RuleName "Heartbeat last $ActiveDays days" -QueryExpression $Query -ErrorAction Stop

                ## Create limiting collection sub-directory if required
                if (!(Get-Item -Path $SiteCode":\DeviceCollection\$CollectionSubDirectory" -ErrorAction SilentlyContinue)) {
                    try {
                        ## Create new limiting collection sub-directory
                        New-Item -Path $SiteCode":\DeviceCollection" -Name $CollectionSubDirectory -ItemType Directory -ErrorAction Stop
                    }
                    catch [System.Exception] {
                        Write-Warning -Message $_.Exception.Message
                    }
                }
                try {
                    ## Move collection to new sub-directory
                    Move-CMObject -ObjectId $Collection.CollectionID -FolderPath $SiteCode":\DeviceCollection\$CollectionSubDirectory" -ErrorAction Stop
                }
                catch [System.Exception] {
                    Write-Warning -Message $_.Exception.Message
                }
                
            }
            else {
                throw "Collection ""$CollectionName"" already exist. Returning information to pipeline."
            }
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
        }
    }
    end {
        return $Collection
    }
}

function New-CMDeviceCollectionPerModel {
    [CmdletBinding()]
    param (
        # Specifies the name of the limiting collection
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "Array of model objects")]
        [ValidateNotNullOrEmpty()]
        $Models = (Get-CMDeviceModels),

        # Specifies the name of the sub-directory
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "CM root sub-directory")]
        [ValidateNotNullOrEmpty()]
        $SubDirectory = "Hardware Collections",

        # Specifies which limiting collection to use
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true,
            HelpMessage = "Specify CollectionID of limiting collection, else use -LimitingCollection (New-CMLimitingCollection <parameters>).CollectionID")]
        [ValidateNotNullOrEmpty()]
        $LimitingCollection = (New-CMLimitingCollection).CollectionID
    )
    
    begin {
        ## Load environment
        Import-CMEnvironment
        
        ## Get current collections to compare and avoid creating duplicates
        $CurrentCollections = Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query 'select Name, LimitToCollectionID from SMS_Collection'
    }
    
    process {
        $Models | ForEach-Object {
            ## Gather manufacturer details, rename and set Manufacturer variable
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
                "Lenovo*" {
                    $Manufacturer = "Lenovo"
                }
                "Asus*" {
                    $Manufacturer = "Asus"
                }
            }
        
            ## Gather model details, rename if required and set Model variable
            switch -Wildcard ($_.Model) {
                "*HP*" {
                    $Model = $_ -replace "HP ", ""
                }
                default {
                    $Model = $_
                }
            }
        
            ## Create device string for collection naming purpose
            $DeviceCollection = ("{0} {1}" -f $Manufacturer, $Model)
        
            ## Create collection if not exists
            if ($DeviceCollection -notin $CurrentCollections.Name) {                
                try {
                    ## Show which device is being parsed
                    Show-Feedback -Text "Parsing $($DeviceCollection) - ($([int]$Models.IndexOf($_)+1) of $($Models.Count))"

                    ## Attempt to create device specific CM collection
                    Show-Feedback -Text "Creating collection for $($DeviceCollection)"
                    $Collection = New-CMDeviceCollection -Name $DeviceCollection -LimitingCollectionId $LimitingCollection -RefreshSchedule (New-CMSchedule -Start "$((Get-Date).Year)-01-01" -RecurInterval Days -RecurCount 1) -RefreshType Periodic -ErrorAction Stop
            
                    ## Add query rule to above collection
                    Show-Feedback -Text "Adding query rule to $($Collection.Name)"
                    $Query = "select SMS_R_SYSTEM.ResourceID,SMS_R_SYSTEM.ResourceType,SMS_R_SYSTEM.Name,SMS_R_SYSTEM.SMSUniqueIdentifier,SMS_R_SYSTEM.ResourceDomainORWorkgroup,SMS_R_SYSTEM.Client from SMS_R_System inner join SMS_G_System_COMPUTER_SYSTEM on SMS_G_System_COMPUTER_SYSTEM.ResourceID = SMS_R_System.ResourceId where SMS_G_System_COMPUTER_SYSTEM.Manufacturer = ""$($_.Manufacturer)"" and SMS_G_System_COMPUTER_SYSTEM.Model = ""$($_.Model)"""
                    Add-CMDeviceCollectionQueryMembershipRule -CollectionId $Collection.CollectionID -RuleName $_.Model -QueryExpression $Query -ErrorAction Stop
                    
                    ## Create root and manufacturer specific sub-directory if required
                    if (!(Get-Item -Path $SiteCode":\DeviceCollection\$SubDirectory\$Manufacturer" -ErrorAction SilentlyContinue)) {
                        try {
                            if (!(Get-Item -Path $SiteCode":\DeviceCollection\$SubDirectory" -ErrorAction SilentlyContinue)) {
                                ## Create new root sub-directory
                                Show-Feedback -Text "Creating new console directory $($SubDirectory)"
                                New-Item -Path $SiteCode":\DeviceCollection" -Name $SubDirectory -ItemType Directory -ErrorAction Stop
                            }
                            ## Create new manufacturer specific sub-directory
                            Show-Feedback -Text "Creating new manufacturer specific console directory for $($Manufacturer)"
                            New-Item -Path $SiteCode":\DeviceCollection\$SubDirectory" -Name $Manufacturer -ItemType Directory -ErrorAction Stop
                        }
                        catch [System.Exception] {
                            Write-Warning -Message $_.Exception.Message
                        }
                    }
                    try {
                        ## Move collection to new sub-directory
                        Show-Feedback -Text "Moving collection $($Collection.CollectionID) to $($Manufacturer)"
                        Move-CMObject -ObjectId $Collection.CollectionID -FolderPath $SiteCode":\DeviceCollection\$SubDirectory\$Manufacturer" -ErrorAction Stop
                    }
                    catch [System.Exception] {
                        Write-Warning -Message $_.Exception.Message
                    }
                }
                catch [System.Exception] {
                    Write-Warning -Message $_.Exception.Message
                }

                ## New line at end of object
                Show-Feedback -Text "-------------------"
            }
            else {
                ## Show which device is being skipped
                Show-Feedback -Text "Skipping $($DeviceCollection), already exists - ($([int]$Models.IndexOf($_)+1) of $($Models.Count))"
                Show-Feedback -Text "-------------------"
            }
        }
    }
}
