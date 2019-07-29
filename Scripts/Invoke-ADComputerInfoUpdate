[CmdletBinding()]
param (
    # Where logs are saved
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp"),

    # Log name
    $LogName = "AdjustADComputerInfo.log"
)
Begin {
    # Load CM module
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') 
    $SiteCode = Get-PSDrive -PSProvider CMSITE 
    Set-location $SiteCode":"

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
		$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""OSImageUpdateScheduler"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"

		# Add value to log file
		try {
			Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
		}
		catch [System.Exception] {
			Write-Warning -Message "Unable to append log entry to $($LogName) file. Error message: $($_.Exception.Message)"
		}
	}
}
Process{
    # Import AD computer information
    $Computers = Get-ADComputer -Filter * -SearchBase "OU=Windows 10,OU=Computers,OU=Workplace,OU=Advania,DC=ramiad,DC=com" -Properties Enabled, Description, ManagedBy
    $UMComputers = $Computers | Where-Object {$_.Description -like ""}
    $MComputers = $Computers | Where-Object {$_.Description -notlike ""}

    ## Process for unmanaged computers
    # Log header
    Write-CMLogEntry -Value "(1/2) Starting processing of $($UMComputers | Measure-Object | Select-Object -ExpandProperty Count) unmanaged AD objects" -Severity 1

    # Computer loop
    foreach ($Computer in $UMComputers) {

        # Counter
        Write-CMLogEntry -Value "$($Computer.Name): Processing computer ($($UMComputers.IndexOf($Computer)+1)/$($UMComputers.Count))" -Severity 1

        # Get user & device relation
        try {
            $TempCMUDA = Get-CMUserDeviceAffinity -DeviceName $Computer.Name -ErrorAction Stop | Where-Object {($_.Sources -contains 4) -or ($_.Sources -contains 6)} | Sort-Object CreationTime | Select-Object -First 1
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "$($Computer.Name): Get user & device relation failed. Error message: $($_.Exception.Message)" -Severity 2
        }

        # CMUserDeviceAffinity exist; attempt to get ADUser information and set AD Computer information
        if ($TempCMUDA.UniqueUserName) {

            # Get AD user information
            try {
                $TempADUser = Get-ADUser -Identity ($TempCMUDA.UniqueUserName | Split-Path -Leaf) -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value "$($Computer.Name): Get AD user information ($($TempCMUDA.UniqueUserName | Split-Path -Leaf)) failed. Error message: $($_.Exception.Message)" -Severity 2
            }

            # Set AD Computer information
            if ($TempADUser.Name) {
                try {
                    #Get-ADComputer -Identity $Computer.Name | Set-ADComputer -Description ("$($TempADUser.SamAccountName.ToLower()), $(Get-Date -Format d)") -ManagedBy $TempADUser.DistinguishedName -ErrorAction Stop | Out-Null
                    Write-CMLogEntry -Value "$($Computer.Name): Attempting to set $($TempADUser.Name) as owner of $($Computer.Name)." -Severity 1
                }
                catch [System.Exception] {
                    Write-CMLogEntry -Value "$($Computer.Name): Set AD computer information failed. Error message: $($_.Exception.Message)" -Severity 3
                }
            }
            else {
                Write-CMLogEntry -Value "$($Computer.Name): Failed to get AD user information" -Severity 2
            }
        }
        else {
            Write-CMLogEntry -Value "$($Computer.Name): Failed to get user & device relation. Skipping." -Severity 2
        }

        # Remove temporary variable
        Remove-Variable Temp*
        Wait-Event -Timeout 0.5
    }
    
    ## Process for already managed computers
    # Header
    Write-CMLogEntry -Value "(2/2) Starting processing of $($MComputers | Measure-Object | Select-Object -ExpandProperty Count) already managed AD objects" -Severity 1

    # Computer loop
    foreach ($Computer in $MComputers) {

        # Counter
        Write-CMLogEntry -Value "$($Computer.Name): Processing computer ($($MComputers.IndexOf($Computer)+1)/$($MComputers.Count))" -Severity 1

        # Get user & device relation
        try {
            $TempCMUDA = Get-CMUserDeviceAffinity -DeviceName $Computer.Name -ErrorAction Stop | Where-Object {($_.Sources -contains 4) -or ($_.Sources -contains 6)} | Sort-Object CreationTime | Select-Object -First 1
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "$($Computer.Name): Get user & device relation failed. Error message: $($_.Exception.Message)" -Severity 2
        }

        # CMUserDeviceAffinity exist; attempt to get ADUser information and set AD Computer information
        if ($TempCMUDA.UniqueUserName) {

            # Get AD user information
            try {
                $TempADUser = Get-ADUser -Identity ($TempCMUDA.UniqueUserName | Split-Path -Leaf) -ErrorAction Stop
            }
            catch [System.Exception] {
                Write-CMLogEntry -Value "$($Computer.Name): Get AD user information ($($TempCMUDA.UniqueUserName | Split-Path -Leaf)) failed. Error message: $($_.Exception.Message)" -Severity 2
            }

            # Update AD Computer information if primary user changed
            if ($TempADUser.Name) {
                try {
                    if ($Computer.ManagedBy -ne $TempADUser.DistinguishedName) {
                        #Get-ADComputer -Identity $Computer.Name | Set-ADComputer -Description ("$($TempADUser.SamAccountName.ToLower()), $(Get-Date -Format d)") -ManagedBy $TempADUser.DistinguishedName -ErrorAction Stop | Out-Null
                        Write-CMLogEntry -Value "$($Computer.Name): Adjusting $($TempADUser.Name) as new owner for $($Computer.Name)." -Severity 1
                    }
                }
                catch [System.Exception] {
                    Write-CMLogEntry -Value "$($Computer.Name): Update AD computer information failed. Error message: $($_.Exception.Message)" -Severity 3
                }
            }
            else {
               Write-CMLogEntry -Value "$($Computer.Name): Failed to get AD user information" -Severity 2
            }
        }
        else {
            Write-CMLogEntry -Value "$($Computer.Name): Failed to get user & device relation. Skipping." -Severity 2
        }

        # Remove temporary variable and wait 0.5 seconds
        Remove-Variable Temp*
        Wait-Event -Timeout 0.5
    }
}
