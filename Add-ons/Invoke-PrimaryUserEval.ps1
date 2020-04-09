#Requires -Modules ActiveDirectory
[CmdletBinding()]
param (
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp"),
    $LogName = "PrimaryUserEvaluation.log",
    $VerboseLog = $false,
    [parameter(Mandatory = $true, HelpMessage = "Limiting Collection ID. Will use All Systems if not specified.")]
    [ValidateNotNullOrEmpty()]
    $LimColID = "SMS00001",
    [parameter(Mandatory = $false, HelpMessage = "Dry run instead of actual modification.")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet($true,$false)]
    $DryRun = $false

)
Begin {
    # Functions
    function Write-CMLogEntry {
        param (
            [parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
            [ValidateNotNullOrEmpty()]
            [string]$Value,
            [parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
            [string]$Severity,
            [parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
            [ValidateNotNullOrEmpty()]
            [string]$FileName = $LogName
        )
        # Determine log file location
        $LogFilePath =  ("filesystem::{0}" -f (Join-Path -Path $LogsDirectory -ChildPath $FileName))
        
        # Construct time stamp for log entry
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
        
        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")
        
        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
        
        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""ClientHealthUpdate"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
        
        # Add value to log file
        try {
            Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to $($LogName) file. Error message: $($_.Exception.Message)"
        }

        # Add 0.5 second delay
        #Start-Sleep -Milliseconds 250 -ErrorAction Stop
    }

    # Construct customer environment
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        Import-Module GroupPolicy -ErrorAction Stop
        $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch {
        Write-CMLogEntry -Value "Error loading customer specific settings. Message: $($_.Exception.Message)" -Severity 2; exit 1
    }

    # Create empty array lists
    try {
        $AdditionQueue = New-Object -TypeName System.Collections.ArrayList -ErrorAction Stop
        $FailedAdditions = New-Object -TypeName System.Collections.ArrayList -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Failed to create array lists. Message: $($_.Exception.Message)" -Severity 2; exit 1
    }
}
Process {
    # Log start
    Write-CMLogEntry -Value "----------- Starting primary user evaluation." -Severity 1

    # Gather Active Directory domain information
    Write-CMLogEntry -Value "Gathering required Active Directory information." -Severity 1
    try {
        $Domain = Get-ADDomain -ErrorAction Stop | Select-Object -ExpandProperty Name
        if ($null -ne ($Domain)) {
            Write-CMLogEntry -Value "Domain name set to $Domain." -Severity 1
        }
        else {
            Write-CMLogEntry -Value "Domain name variable is empty. Exiting." -Severity 3; exit 1
        }
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering AD domain information. Message: $($_.Exception.Message)" -Severity 2; exit 1
    }

    # Gather limiting CM collection information
    Write-CMLogEntry -Value "Gathering limiting CM collection information" -Severity 1
    try {
        $CMCollectionInformation = Get-CMCollection -Id $LimColID -CollectionType Device -ErrorAction Stop
        if ($CMCollectionInformation.MemberCount -gt 0) {
            Write-CMLogEntry -Value "Limiting CM collection $LimColID evaluates to $($CMCollectionInformation.Name) with $($CMCollectionInformation.MemberCount) members." -Severity 1
        }
        else {
            Write-CMLogEntry -Value "Limiting CM collection $LimColID evaluates to $($CMCollectionInformation.Name) but is empty. Exiting." -Severity 3; exit 1
        }
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering limiting CM collection information. Message: $($_.Exception.Message)" -Severity 2; exit 1
    }

    # Gather CM devices based on collection membership
    Write-CMLogEntry -Value "Gathering CM devices in collection ID $LimColID." -Severity 1
    try {
        $CMDevices = Get-CMDevice -CollectionId $LimColID -Fast -ErrorAction Stop
        if ($null -ne ($CMDevices)) {
            Write-CMLogEntry -Value "Found $($CMDevices.Count) devices." -Severity 1
        }
        else {
            Write-CMLogEntry -Value "CM Devices variable is empty. Exiting." -Severity 3; exit 1
        }
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering CM devices. Message: $($_.Exception.Message)" -Severity 3; exit 1
    }

    # Repeat process for each CM device
    foreach ($CMDevice in $CMDevices) {
        Write-CMLogEntry -Value "-- Evaluating $($CMDevice.Name) with resource ID $($CMDevice.ResourceID) ($($CMDevices.IndexOf($CMDevice)+1)/$($CMDevices.Count))." -Severity 1
        try {

            # Gather AD device information
            $ADComputer = Get-ADComputer -Identity $CMDevice.Name -Properties ManagedBy -ErrorAction Stop
            if ($null -ne ($ADComputer)) {
                if ($VerboseLog -eq $true){Write-CMLogEntry -Value "---- Found Active Directory device $($ADComputer.Name) with GUID $($ADComputer.ObjectGUID)." -Severity 1}

                # Gather AD user based on AD device attribute ManagedBy
                $ADPrimaryUser = Get-ADUser -Identity $ADComputer.ManagedBy -ErrorAction Stop
                if ($null -ne ($ADPrimaryUser)) {
                    if ($VerboseLog -eq $true){Write-CMLogEntry -Value "---- Found Active Directory user $($ADPrimaryUser.Name) with GUID $($ADPrimaryUser.ObjectGUID)." -Severity 1}

                    # Gather CM primary users for device. If empty or incorrect, add to queue
                    $CMPrimaryUsers = Get-CMUserDeviceAffinity -DeviceId $CMDevice.ResourceID -ErrorAction Stop | Where-Object {$_.Types -eq 1}
                    if ($null -ne ($CMPrimaryUsers)) {
                        if ($VerboseLog -eq $true){Write-CMLogEntry -Value "---- Found $($CMPrimaryUsers | Measure-Object | Select-Object -ExpandProperty Count) CM primary user(s):" -Severity 1}

                        # Separate rows for each primary user in log
                        foreach ($CMPrimaryUser in $CMPrimaryUsers) {
                            if ($VerboseLog -eq $true){Write-CMLogEntry -Value "------ User $($CMPrimaryUser.UniqueUserName) with GUID $($CMPrimaryUser.UniqueIdentifier.Guid)." -Severity 1}
                        }

                        # Evaluate if AD user is CM primary user, else add to queue
                        if (("$($Domain)\$($ADPrimaryUser.Name)") -in $CMPrimaryUsers.UniqueUserName) {
                            if ($VerboseLog -eq $true){Write-CMLogEntry -Value "---- User $($ADPrimaryUser.Name) already primary user on $($CMDevice.Name)." -Severity 1}
                        }
                        else {
                            Write-CMLogEntry -Value "---- User $($ADPrimaryUser.Name) is not primary user on $($CMDevice.Name). Adding to queue." -Severity 2
                            [void]$AdditionQueue.Add([PSCustomObject]@{
                                Device = $CMDevice.Name
                                User = ("{0}\{1}" -f $Domain, $ADPrimaryUser.Name)
                            })
                        }
                    }
                    else {
                        Write-CMLogEntry -Value "---- Couldn't find CM user relation for device $($CMDevice.Name). Adding to queue." -Severity 2
                        [void]$AdditionQueue.Add([PSCustomObject]@{
                            Device = $CMDevice.Name
                            User = ("{0}\{1}" -f $Domain, $ADPrimaryUser.Name)
                        })
                    }
                }
                else {
                    Write-CMLogEntry -Value "---- Couldn't find Active Directory user for object $($ADComputer.Name)." -Severity 1
                }
            }
            else {
                Write-CMLogEntry -Value "---- Couldn't find a valid AD device for object $($CMDevice.Name)." -Severity 2
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "---- Error gathering device information for object $($CMDevice.Name) ($($CMDevices.IndexOf($CMDevice)+1)/$($CMDevices.Count)). Message: $($_.Exception.Message)" -Severity 2
        }
        
        # Emtpy variable list
        Remove-Variable -Name ADPrimaryUser, ADComputer, CMPrimaryUsers, CMPrimaryUser, CMUserToAdd, CMUser -Force -ErrorAction SilentlyContinue
    }

    # Process queue if not empty
    foreach ($DeviceToAdd in $AdditionQueue) {
        Write-CMLogEntry -Value "-- Processing queue for $($CMDevice.Name) ($($AdditionQueue.IndexOf($DeviceToAdd)+1)/$($AdditionQueue.Count))." -Severity 1

        # Gather CM objects
        $CMUser = Get-CMUser -Name $DeviceToAdd.User -ErrorAction Stop
        $CMDevice = Get-CMDevice -Name $DeviceToAdd.Device -Fast -ErrorAction Stop 
        if ($null -ne $CMUser) {
            Write-CMLogEntry -Value "---- Adding $($CMUser.SMSID) to $($CMDevice.Name)" -Severity 1
            try {
                if ($DryRun -ne $true) {
                    Add-CMUserAffinityToDevice -DeviceId $CMDevice.ResourceID -UserId $CMUser.ResourceID -ErrorAction Stop -WhatIf:$DryRun
                }
            }
            catch [System.Exception] {
                # Add failed addition attempt to array list
                Write-CMLogEntry -Value "------ Failed to add UDA. Message: $($_.Exception.Message)" -Severity 3
                [void]$FailedAdditions.Add([PSCustomObject]@{
                    Date =  Get-Date -Format G
                    Device = $CMDevice.Name
                    User = $DeviceToAdd.User
                    Error = $_.Exception.Message
                })
            }
        }
        else {
            # Add failed addition attempt to array list
            Write-CMLogEntry -Value "------ Failed to find valid CM user for $($DeviceToAdd.User)." -Severity 2
            [void]$FailedAdditions.Add([PSCustomObject]@{
                Date =  Get-Date -Format G
                Device = $CMDevice.Name
                User = $DeviceToAdd.User
                Error = "User doesn't exist in CM."
            })
        }
    }

    # Dump Failed Additions array list to file
    if ($null -ne $FailedAdditions) {
        $FailedAdditions | Export-Csv -Path ("filesystem::{0}\{1}.csv" -f $LogsDirectory, "PrimaryUserFailedAdditions") -Force -NoTypeInformation -Append -ErrorAction SilentlyContinue
    }

    # Add line to end of evaluation
    Write-CMLogEntry -Value "----------- End of primary user evaluation" -Severity 1
}
