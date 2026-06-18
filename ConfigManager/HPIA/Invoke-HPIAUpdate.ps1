[CmdletBinding()]
param (
    # Central repository UNC path
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.IO.FileInfo]$RepoDir = (Join-Path -Path $env:SystemDrive -ChildPath "HPIA\Downloads"),

    # Log directory
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [System.IO.FileInfo]$LogDir = (Join-Path -Path $env:SystemDrive -ChildPath "HPIA\Logs"),

    # Log name
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [String]$LogName = "Invoke-HPIAUpdate.log",

    # Update type decides visibility, central repository or online, etc.
    [Parameter(Mandatory = $false)]
    [ValidateSet("Online","Offline","OSD","Live")]
    [String]$UpdateType = "Online",

    # HP BIOS password bin file
    [Parameter(Mandatory = $false)]
    [System.IO.FileInfo]$PWBin = (Get-ChildItem -Filter *.bin | Select-Object -ExpandProperty FullName)
)
begin {
    # Create functions
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
        $LogFilePath = (Join-Path -Path $LogDir -ChildPath $FileName)
		
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

    # Create variables
    $ArgumentString = '/Operation:Analyze /Selection:All /Noninteractive /Silent /SoftpaqDownloadFolder:"{0}" /Debug' -f (Join-Path -Path $env:SystemDrive -ChildPath "HPIA\Downloads")

    # Create HPIA argument string if BIOS password exist
    if ($null -ne $PWBin) {
        Write-CMLogEntry -Value "HP BIOS password bin file detected. Adjusting argument string." -Severity 2
        $ArgumentString = ($ArgumentString + ' /BIOSPwdFile:"{0}"' -f $PWBin)
    } else {
        Write-CMLogEntry -Value "No HP BIOS password bin file detected." -Severity 1
    }

    # Update type switch
    switch ($UpdateType) {
        Online  { $ArgumentString = ($ArgumentString + ' /Action:Install /ReportFolder:"{0}"' -f $LogDir) }
        Offline { $ArgumentString = ($ArgumentString + ' /Action:Install /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $LogDir) }
        OSD     { $ArgumentString = ($ArgumentString + ' /Action:Install /Offlinemode:"{0}" /ReportFolder:"%_SMSTSLogPath%"' -f $RepoDir) }
        List    { $ArgumentString = ($ArgumentString + ' /Action:List /ReportFolder:"{0}"' -f $LogDir) }
    }
}
process {
    # Run HP Image Assistant
    try {
        Write-CMLogEntry -Value "Running HPIA with the following argument string: $ArgumentString" -Severity 1
        $Process = Start-Process ".\HPImageAssistant.exe" -ArgumentList $ArgumentString -Wait -PassThru -ErrorAction Stop
        
        # Switch depending on HPIA return code
        switch ($Process.ExitCode) {
            0 { Write-CMLogEntry -Value "Successfully updated." -Severity 1; exit 0 }
            256 { Write-CMLogEntry -Value "The analysis returned no recommendations." -Severity 1; exit 0 }
            257 { Write-CMLogEntry -Value "There were no recommendations selected for the analysis." -Severity 1; exit 0 }
            3010 { Write-CMLogEntry -Value "Install Reboot Required - SoftPaq installations are successful, and at least one requires a reboot." -Severity 1; exit 3010 }
            3020 { Write-CMLogEntry -Value "Install failed — One or more SoftPaq installations failed." -Severity 2; exit 1 }
            4096 { Write-CMLogEntry -Value "The platform is not supported." -Severity 2; exit 1 }
            4097 { Write-CMLogEntry -Value "The parameters are invalid." -Severity 2; exit 1 }
            4098 { Write-CMLogEntry -Value "There is no Internet connection." -Severity 2; exit 1 }
            Default { Write-CMLogEntry -Value "Return code $($Process.ExitCode). Please refer to https://ftp.ext.hp.com/pub/caps-softpaq/cmit/whitepapers/HPIAUserGuide.pdf." -Severity 1; exit 0 }
        }
    }
    catch [System.SystemException] {
        Write-CMLogEntry -Value "Error - Could not run HPIA. Message: $($_.Exception.Message)" -Severity 3; exit 1
    }
}
