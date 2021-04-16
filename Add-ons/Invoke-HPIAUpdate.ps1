param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $RepoDir,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $LogsDir,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $UpdateType = "Live",
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $PWBin = (Get-ChildItem -Filter *.bin | Select-Object -ExpandProperty FullName),
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $LogName = "HPIAUpdate.log",
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
    $HPModel = Get-CimInstance -Namespace root\wmi -ClassName MS_SystemInformation -ErrorAction Stop | Select-Object -ExpandProperty SystemProductName
    $OSBuild = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -ExpandProperty Version
    $FullLogPath = Join-Path -Path $LogsDir -ChildPath $env:COMPUTERNAME

    # Create HPIA argument string
    if ($null -eq $PWBin) {
        $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All'
        Write-CMLogEntry -Value "HP BIOS password detected." -Severity 1
    }
    else {
        $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /BIOSPwdFile:"{0}"' -f $PWBin
        Write-CMLogEntry -Value "No HP BIOS password detected." -Severity 1
    }

    # Switch for UpdateType (background or interactive)
    switch ($UpdateType) {
        "Live" { $ArgumentString = ($ArgumentString + ' /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath) }
        "Background" { $ArgumentString = ' /Silent /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "Online" { $ArgumentString = ' /noninteractive /ReportFolder:"{0}"' -f $FullLogPath }
        "DriversOnly" { $ArgumentString = ' /Category:Drivers,Software /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "BIOSOnly" { $ArgumentString = ' /Category:BIOS,Firmware /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "OSD" {
            # Load CM environment
            try {
                $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
            }

            # Gather TS variables
            $FullLogPath = $TSEnvironment.Value("_SMSTSLogPath")
            Write-CMLogEntry -Value "Log path re-evaluated to $FullLogPath" -Severity 1

            # Construct argument string
            $ArgumentString = ' /Category:Drivers,Software /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath
            Write-CMLogEntry -Value "Argument string: $ArgumentString" -Severity 1
        }
    }
}
process {
    if (Test-Path -Path $RepoDir) {
        # Run HP Image Assistant
        try {
            Start-Process '.\HPImageAssistant.exe' -ArgumentList $ArgumentString -Wait -ErrorAction Stop
            exit 0;
        }
        catch [System.SystemException] {
            Write-CMLogEntry -Value "Error - Couuld not run HPIA. Message: $($_.Exception.Message)" -Severity 2
            exit 1;
        }
    } else {
        Write-CMLogEntry -Value "Error - Directory $($RepoDir) not available." -Severity 2
        exit 2;
    }
}
