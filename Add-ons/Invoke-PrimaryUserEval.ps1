#Requires -Modules ActiveDirectory
#Requires -Modules ConfigurationManager
[CmdletBinding()]
param (
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp"),
    $LogName = "PrimaryUserEvaluation.log",
    [parameter(Mandatory = $true, HelpMessage = "Limiting Collection ID. Will use All Systems if not specified.")]
    [ValidateNotNullOrEmpty()]
    $LimColID = "SMS00001",
    [parameter(Mandatory = $true, HelpMessage = "Remove faulty User Device Affinity relationshop. ")]
    [ValidateNotNullOrEmpty()]
    [ValidateSet($true,$false)]
    $RemoveFaultyUDA = $false

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
        $LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
		
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
        Start-Sleep -Milliseconds 500 -ErrorAction Stop
    }

    # Construct customer environment
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1')
        Import-Module GroupPolicy
        $SiteCode = Get-PSDrive -PSProvider CMSITE 
        Set-location $SiteCode":" 
    }
    catch {
        Write-CMLogEntry -Value "Error loading customer specific settings. Message: $($_.Exception.Message)" -Severity 2
    }
}
Process {
    # Log start
    Write-CMLogEntry -Value "----------- Starting primary user evaluation." -Severity 1

    # Gather Active Directory domain information
    Write-CMLogEntry -Value "Gathering required Active Directory information." -Severity 1
    try {
        $Domain = Get-ADDomain -ErrorAction Stop | Select-Object -ExpandProperty Name
        if (![string]::IsNullOrEmpty($Domain)) {
            Write-CMLogEntry -Value "Domain name set to $Domain." -Severity 1
        }
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering CM devices. Message: $($_.Exception.Message)" -Severity 2; exit 1
    }

    # Gather CM devices based on collection membership
    Write-CMLogEntry -Value "Gathering CM devices in collection ID $LimColID." -Severity 1
    try {
        $Computers = Get-CMDevice -CollectionId $LimColID -Fast -ErrorAction Stop
        if (![string]::IsNullOrEmpty($Computers)) {
            Write-CMLogEntry -Value "Found $($Computers.Count) devices." -Severity 1
        }
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering CM devices. Message: $($_.Exception.Message)" -Severity 2; exit 1
    }

    #
    foreach ($Computer in $Computers) {
        Write-CMLogEntry -Value "- Evaluating $($Computer.Name) with resource ID $($Computer.ResourceID) ($($Computers.IndexOf($Computer)+1)/$($Computers.Count))." -Severity 1
        try {

            # Gather AD device information
            $ADComputer = Get-ADComputer -Identity $Computer.Name -Properties ManagedBy -ErrorAction Stop
            if (![string]::IsNullOrEmpty($ADComputer)) {
                Write-CMLogEntry -Value "- Found Active Directory device $($ADComputer.Name) with GUID $($ADComputer.ObjectGUID)." -Severity 1

                # Gather AD user based on AD device attribute ManagedBy
                $ADPrimaryUser = Get-ADUser -Identity $ADComputer.ManagedBy -ErrorAction Stop
                if (![string]::IsNullOrEmpty($ADPrimaryUser)) {
                    Write-CMLogEntry -Value "- Found Active Directory user $($ADPrimaryUser.Name) with GUID $($ADPrimaryUser.ObjectGUID)." -Severity 1

                    # Gather CM primary users for device
                    $CMPrimaryUsers = Get-CMUserDeviceAffinity -DeviceId $Computer.ResourceID -ErrorAction Stop | Where-Object {$_.Types -eq 1}
                    if (![string]::IsNullOrEmpty($CMPrimaryUser)) {
                        Write-CMLogEntry -Value "- Found $($CMPrimaryUsers | Measure-Object | Select-Object -ExpandProperty Count) Config Manager primary user(s)." -Severity 1

                        # Separate rows for each primary user in log
                        foreach ($CMPrimaryUser in $CMPrimaryUsers) {
                            Write-CMLogEntry -Value "-- User $($CMPrimaryUser.UniqueUserName) with GUID $($CMPrimaryUser.UniqueIdentifier.Guid)." -Severity 1
                        }

                        # Evaluate if AD user is CM primary user
                        if (("$($Domain)\$($ADPrimaryUser.Name)") -in $CMPrimaryUsers.UniqueUserName) {
                            Write-CMLogEntry -Value "-- User $($ADPrimaryUser.Name) already primary user on $($Computer.Name)." -Severity 1
                        }
                        else {
                            Write-CMLogEntry -Value "-- User $($ADPrimaryUser.Name) is not primary user on $($Computer.Name)." -Severity 2

                            # Gather CM user based on AD user information
                            $CMADUser = Get-CMUser -Name ("$($Domain)\$($ADPrimaryUser.Name)") -ErrorAction Stop
                            if (![string]::IsNullOrEmpty($CMADUser)) {
                                Write-CMLogEntry -Value "--- Found Config Manager user $($CMADUser.SMSID) with GUID $($CMADUser.UniqueIdentifier.Guid). Adding User affinity to device $($Computer.Name)." -Severity 1

                                # Add CM user to device
                                $Eval = Add-CMUserAffinityToDevice -DeviceId $Computer.ResourceID -UserId $CMADUser.ResourceID -ErrorAction Stop
                            }
                            else {
                                Write-CMLogEntry -Value "--- Couldn't find a valid Config Manager user for Active Directory user $($ADPrimaryUser.Name)." -Severity 2
                            }
                        }

                        # Remove faulty UDA if parameter set to true
                        if ($RemoveFaultyUDA) {
                            Write-CMLogEntry -Value "-- Script parameter RemoveFaultyUDA set to true." -Severity 1

                            # Gather CM user based on AD user information
                            $CMADUser = Get-CMUser -Name ("$($Domain)\$($ADPrimaryUser.Name)") -ErrorAction Stop
                            if (![string]::IsNullOrEmpty($CMADUser)) {

                                # Remove all faulty primary users unless set as ManagedBy on AD device
                                $CMPrimaryUsers | Where-Object {$_.UniqueUserName -ne $CMADUser.SMSID} | ForEach-Object {
                                    Write-CMLogEntry -Value "--- Removing $($_.UniqueUserName) from $($Computer.Name)" -Severity 1

                                    # Run removal command
                                    $Eval = Remove-CMUserAffinityFromDevice -DeviceName $_.ResourceName -UserName $_.UniqueUserName -Force -ErrorAction Stop
                                }
                            }
                            else {
                                Write-CMLogEntry -Value "--- Couldn't find a valid Config Manager user for Active Directory user $($ADPrimaryUser.Name)." -Severity 2
                            }
                        }

                    }
                    else {
                        Write-CMLogEntry -Value "- Couldn't find Config Manager user relationship for object $($Computer.Name). Adding User affinity to device $($Computer.Name)." -Severity 1

                        # Gather CM user based on AD user information
                        $CMADUser = Get-CMUser -Name ("$($Domain)\$($ADPrimaryUser.Name)") -ErrorAction Stop
                        if (![string]::IsNullOrEmpty($CMADUser)) {
                            Write-CMLogEntry -Value "-- Found Config Manager user $($CMADUser.SMSID) with GUID $($CMADUser.UniqueIdentifier.Guid). Adding User affinity to device $($Computer.Name)." -Severity 1

                            # Run addition of UDA
                            $Eval = Add-CMUserAffinityToDevice -DeviceId $Computer.ResourceID -UserId $CMADUser.ResourceID -ErrorAction Stop
                        }
                        else {
                            Write-CMLogEntry -Value "-- Couldn't find a valid Config Manager user for Active Directory user $($ADPrimaryUser.Name)." -Severity 2
                        }
                    }
                }
                else {
                    Write-CMLogEntry -Value "- Couldn't find Active Directory user for object $($ADComputer.Name)." -Severity 1
                }
            }
            else {
                Write-CMLogEntry -Value "- Couldn't find Active Directory device for object $Computer." -Severity 1
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "Error gathering AD device information for object $($Computer.Name) ($($Computers.IndexOf($Computer)+1)/$($Computers.Count)). Message: $($_.Exception.Message)" -Severity 2
        }
    }
    # Add line to end of evaluation
    Write-CMLogEntry -Value "----------- End of primary user evaluation" -Severity 1
}