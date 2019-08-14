[CmdletBinding()]
param (
	$LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp"),
	$LogName = "MoveToOU.log",
	[parameter(Mandatory = $true, HelpMessage = "URL to ConfigMgr webservice")]
	[ValidateNotNullOrEmpty()]
	$URI,
	[parameter(Mandatory = $true, HelpMessage = "ConfigMgr webservice secret key")]
	[ValidateNotNullOrEmpty()]
	$SecretKey,
	[parameter(Mandatory = $true, HelpMessage = "OU LDAP string")]
	[ValidateNotNullOrEmpty()]
	$OU
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
	}

	# Load Microsoft.SMS.TSEnvironment COM object
	try {
		$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "Unable to construct Microsoft.SMS.TSEnvironment object. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3, exit 1
	}

	# Construct new web service proxy
	try {
		$WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-CMLogEntry -Value "Unable to establish a connection to ConfigMgr WebService. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)" -Severity 3; exit 1
	}
}
Process {
    # Gather OSD variables
    if (($TSEnvironment.Value('_SMSTSMachineName')) -like 'MININT*') {
        $OSDComputerName = $TSEnvironment.Value('OSDComputerName')
    }
    else {
        $OSDComputerName = $TSEnvironment.Value('_SMSTSMachineName')
    }

    # Attempt to move computer into OU
    $Invocation = $WebService.SetADOrganizationalUnitForComputer($SecretKey, $OU, $OSDComputerName)
    $ADComputer = $WebService.GetADComputer($SecretKey, $OSDComputerName)

    switch ($Invocation) {
        $true {
		    Write-CMLogEntry -Value "Successfully moved $OSDComputerName to $OU." -Severity 1
            exit 0
        }
        $false {
            if (($ADComputer.DistinguishedName -replace "CN=$($ADComputer.CanonicalName),") -eq $OU) {
		        Write-CMLogEntry -Value "Failed to move $OSDComputerName. Object is already in $($ADComputer.DistinguishedName -replace "CN=$($ADComputer.CanonicalName),")." -Severity 1
                exit 0
            }
            else {
                Write-CMLogEntry -Value "Failed to move $OSDComputerName to $OU. Currently in $($ADComputer.DistinguishedName -replace "CN=$($ADComputer.CanonicalName),")." -Severity 2
                exit 1
            }
        }
    }
}
