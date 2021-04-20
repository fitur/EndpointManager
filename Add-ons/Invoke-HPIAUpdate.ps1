param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $RepoDir,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $ReportDir = (Join-Path -Path $env:SystemDrive -ChildPath "HPIA\Logs"),
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $UpdateType = "Live",
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $PWBin = (Get-ChildItem -Filter *.bin | Select-Object -ExpandProperty FullName),
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $LogName = "Invoke-HPIAUpdate.log",
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp")
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

    # Create variables
    $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /Noninteractive /SoftpaqDownloadFolder:"{0}" /Debug' -f ($ReportDir | Split-Path -Parent)

    # Create HPIA argument string if BIOS password exist
    if ($null -ne $PWBin) {
        Write-CMLogEntry -Value "HP BIOS password detected. Adjusting argument string." -Severity 2
        $ArgumentString = ($ArgumentString + ' /BIOSPwdFile:"{0}"' -f $PWBin)
    }
    else {
        Write-CMLogEntry -Value "No HP BIOS password detected." -Severity 1
    }

    # Switch for UpdateType (background or interactive)
    switch ($UpdateType) {
        "Live" { $ArgumentString = ($ArgumentString + '  /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $ReportDir) }
        "Online" { $ArgumentString = ($ArgumentString + ' /Silent /ReportFolder:"{0}"' -f $ReportDir) }
        "DriversOnly" { $ArgumentString = ($ArgumentString + ' /Silent /Category:Drivers,Software /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $ReportDir) }
        "BIOSOnly" { $ArgumentString = ($ArgumentString + ' /Silent /Category:BIOS,Firmware /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $ReportDir) }
        "OSD" {
            Write-CMLogEntry -Value "Running in OSD mode. Log path re-evaluated to %_SMSTSLogPath%" -Severity 1

            # Construct argument string
            $ArgumentString = ($ArgumentString + ' /Silent /Category:Drivers,Software,Firmware /Offlinemode:"{0}" /ReportFolder:"%_SMSTSLogPath%"' -f $RepoDir)
        }
    }
}
process {
    if (Test-Path -Path $RepoDir) {
        # Run HP Image Assistant
        try {
            Write-CMLogEntry -Value "Running HPIA with the following argument string: $ArgumentString" -Severity 1
            Start-Process '.\HPImageAssistant.exe' -ArgumentList $ArgumentString -Wait -ErrorAction Stop
            Wait-Process -ProcessName HPImageAssistant* -ErrorAction SilentlyContinue
            exit 0;
        }
        catch [System.SystemException] {
            Write-CMLogEntry -Value "Error - Could not run HPIA. Message: $($_.Exception.Message)" -Severity 3
            exit 1;
        }
    } else {
        Write-CMLogEntry -Value "Error - Directory $($RepoDir) not available." -Severity 2
        exit 2;
    }
}
