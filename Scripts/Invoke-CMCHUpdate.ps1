[CmdletBinding()]
param (
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp"),
    $LogName = "CHUpgradeLog.log",
    [parameter(Mandatory = $false, HelpMessage = "Client Health share name (not including $)")]
	[ValidateNotNullOrEmpty()]
    $CHShareName = "ClientHealth"
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

    # Construct customer environment
    try {
        Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') 
        $SiteCode = Get-PSDrive -PSProvider CMSITE 
        Set-location $SiteCode":" 
    }
    catch {
        Write-CMLogEntry -Value "Error loading customer specific settings. Message: $($_.Exception.Message)" -Severity 2
    }
}
Process {
    # Log start
    Write-CMLogEntry -Value "----------- Starting job Client Health Update." -Severity 1

    # Gather ConfigMgr Client Package information (mostly package 0-9)
    $ClientPackage = Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Class SMS_Package -ComputerName $SiteCode.SiteServer | Where-Object {
        ($_.Name -match "Configuration Manager Client Package") -and
        ($_.Manufacturer -match "Microsoft Corporation") -and
        ## This part might be  unnecessary
        (($_.PackageID).Substring(7) -lt 9)
    } | Select-Object -First 1

    # Process ConfigMgr Client Package installation files if exist
    if (($ClientPackage | Measure-Object).Count -ge 1) {
        Write-CMLogEntry -Value "Found $($ClientPackage | Select-Object -ExpandProperty Name) ($($ClientPackage | Select-Object -ExpandProperty PackageID))" -Severity 1

        # Gather shared folders information
        try {
            $SharedFolders = Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer
            [System.IO.FileInfo]$CMDir = (Join-Path -Path ($SharedFolders | Where-Object {$_.Name -match "SMS_$($SiteCode)"} | Select-Object -ExpandProperty Path) -ChildPath "Client" -Resolve)
            [System.IO.FileInfo]$CHDir = (Join-Path -Path ($SharedFolders | Where-Object {(($_.Name -match $CHShareName) -and ($_.Name -notmatch "Logs"))} | Select-Object -ExpandProperty Path) -ChildPath "Client" -Resolve)
        }
        catch {
            Write-CMLogEntry -Value "Error gathering directories. Message: $($_.Exception.Message)" -Severity 2
        }

        # Begin loop
        if ([System.Version](Get-Item (Join-Path -Path $CMDir -ChildPath "ccmsetup.exe" -Resolve) | Select-Object -ExpandProperty VersionInfo).FileVersion -gt [System.Version](Get-Item (Join-Path -Path $CHDir -ChildPath "ccmsetup.exe") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty VersionInfo).FileVersion) {
            
            # Copy setup files to Client Health directory
            try {
                Write-CMLogEntry -Value "Attempting to copy ConfigMgr setup files to directory $($CHDir.DirectoryName)" -Severity 1
                Copy-Item -Path $CMDir.FullName -Destination $CHDir.DirectoryName -Recurse -Force -Verbose
            }
            catch {
                Write-CMLogEntry -Value "Failed to copy installation files to Client Health directory. Message: $($_.Exception.Message)" -Severity 2
            }

            # Edit XML configuration version number
            try {
                Write-CMLogEntry -Value "Attempting to edit Client Health configuration XML." -Severity 1
                $ConfigXML = New-Object -TypeName XML
                $ConfigXML.Load((Join-Path -Path (Split-Path -Path $CHDir) -ChildPath "config.xml" -Resolve))
                $node = $ConfigXML.Configuration.ChildNodes
                $newChild = $ConfigXML.CreateElement("Version")
                $newChild.set_InnerXML((Get-Item (Join-Path -Path $CHDir -ChildPath "ccmsetup.exe" -Resolve) | Select-Object -ExpandProperty VersionInfo).FileVersion) 
                $ConfigXML.Configuration.ReplaceChild($newChild, $node.Item(1)) | Out-Null
                $ConfigXML.Save((Join-Path -Path (Split-Path -Path $CHDir) -ChildPath ($ConfigXML.BaseURI | Split-Path -Leaf)))
            }
            catch {
                Write-CMLogEntry -Value "Error writing data to configuration XML. Message: $($_.Exception.Message)" -Severity 2
            }
        }
        else {
            Write-CMLogEntry -Value "ConfigMgr Client version $((Get-Item (Join-Path -Path $CHDir -ChildPath "ccmsetup.exe" -Resolve) | Select-Object -ExpandProperty VersionInfo).FileVersion) is equal to Client Health setup files." -Severity 1
        }

        # Job complete
        Write-CMLogEntry -Value "----------- Completed update tasks for ConfigMgr Client verison $((Get-Item (Join-Path -Path $CHDir -ChildPath "ccmsetup.exe" -Resolve) | Select-Object -ExpandProperty VersionInfo).FileVersion)." -Severity 1
    }
    else {
        # Add error to log if ConfigMgr Client package could not be found
        Write-CMLogEntry -Value "Could not find Configuration Manager Client Package in site $SiteCode." -Severity 2
    }
}
