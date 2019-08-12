[CmdletBinding()]
param (
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Temp"),
    $LogName = "ClientHealthInstallation.log",
    [parameter(Mandatory = $false, HelpMessage = "Client Health share name (not including $)")]
	[ValidateNotNullOrEmpty()]
    $CHShareName = "ClientHealth",
    $URI = "https://gallery.technet.microsoft.com/ConfigMgr-Client-Health-ccd00bd7"
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
    Write-CMLogEntry -Value "----------- Starting Client Health installation." -Severity 1

    # Generate download URI for Client Health
    $WebRequest = Invoke-WebRequest -Uri $URI
    $DownloadURI = "{0}{1}" -f ($URI | Split-Path -Parent), ($WebRequest.Links | Where-Object {$_.innerText -like "ConfigMgrClientHealth-*.zip"} | Select-Object -ExpandProperty data-url)

    # Generate local path
    $LocalPath = (Join-Path -Path ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer | Where-Object {$_.Name -match "SMS_$($SiteCode)"} | Select-Object -ExpandProperty Path).SubString(0,3)) -ChildPath $CHShareName)

    # Gather basic information, download Client Health and create new directories
    try {
        ## Client Health share
        Invoke-Command -ComputerName $SiteCode.SiteServer -ArgumentList $LocalPath, $CHShareName, $DownloadURI -ScriptBlock {
            ## Client Health share
            # Create directory
            New-Item -Path $args[0] -ItemType Directory -ErrorAction Stop

            # Set ACL
            $ACL = Get-Acl -Path $args[0] -ErrorAction Stop
            $ROAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule("$(Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain)\Domain Computers","ReadAndExecute, Synchronize","ContainerInherit, ObjectInherit","None" ,"Allow")
            $ACL.AddAccessRule($ROAccessRule)
            $ACL | Set-Acl -Path $args[0] -ErrorAction Stop

            # Share directory
            New-SmbShare -Name "$($args[1])$" -Path $args[0] -FullAccess Everyone #("{0}\domain computers" -f (Get-WmiObject Win32_Computersystem | Select-Object -ExpandProperty Domain))

            # Download and extract Client Health
            Invoke-WebRequest -Uri $args[2] -OutFile ("{0}\{1}" -f $args[0], ($args[2] | Split-Path -Leaf)) -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
            [System.IO.Compression.ZipFile]::ExtractToDirectory($("{0}\{1}" -f $args[0], ($args[2] | Split-Path -Leaf)), $args[0])

            # Set Logs ACL
            $ACL = Get-Acl -Path (Join-Path -Path $args[0] -ChildPath "Logs")
            $RWAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule("$(Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain)\Domain Computers","FullControl","ContainerInherit, ObjectInherit","None" ,"Allow")
            $ACL.SetAccessRule($RWAccessRule)
            $ACL | Set-Acl -Path (Join-Path -Path $args[0] -ChildPath "Logs")

            # Share Logs directory
            New-SmbShare -Name "$($args[1])Logs$" -Path (Join-Path -Path $args[0] -ChildPath "Logs") -FullAccess Everyone -ErrorAction Stop
        }
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Failed to create directories. Message: $($_.Exception.Message)" -Severity 2
    }

    # Gather shared folders information
    try {
        $SharedFolders = Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop
        $CMDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath (($SharedFolders | Where-Object {$_.Name -match "SMS_$($SiteCode)"} | Select-Object -ExpandProperty Name))))
        $CHDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath (($SharedFolders | Where-Object {(($_.Name -match $CHShareName) -and ($_.Name -notmatch "Logs"))} | Select-Object -ExpandProperty Name))))
        $CHLogsDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath (($SharedFolders | Where-Object {(($_.Name -match $CHShareName) -and ($_.Name -match "Logs"))} | Select-Object -ExpandProperty Name))))
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering directories. Message: $($_.Exception.Message)" -Severity 2
    }

    # Copy CM Client installation package from CM to CH directory
    try {
        Copy-Item -Path "filesystem::$($CMDir)\Client" -Destination "filesystem::$($CHDir)" -Recurse -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Failed to copy CM Client installation directories. Message: $($_.Exception.Message)" -Severity 2
    }

    # Edit XML configuration version number
    try {
        $ConfigXML = New-Object -TypeName XML
        $ConfigXML.Load("$(Join-Path -Path $CHDir -ChildPath "config.xml")")

        # Edit child nodes
        # Local Files
        $ConfigXML.Configuration.LocalFiles = [string](Join-Path -Path $env:SystemRoot -ChildPath $CHShareName)

        # Client
        $ConfigXML.Configuration.Client[0].'#text' = [string]((Get-Item "filesystem::$(Join-Path -Path $CHDir -ChildPath "Client\ccmsetup.exe")" | Select-Object -ExpandProperty VersionInfo).FileVersion)
        $ConfigXML.Configuration.Client[1].'#text' = [string]($SiteCode.SiteCode)
        $ConfigXML.Configuration.Client[2].'#text' = [string](Get-WmiObject Win32_Computersystem | Select-Object -ExpandProperty Domain)
        $ConfigXML.Configuration.Client[4].'#text' = [string](Join-Path -Path $CHDir -ChildPath "Client")

        # Client Install Property
        $temp = $ConfigXML.SelectNodes("//ClientInstallProperty")
        $temp[0].InnerXml = [string]("SMSSITECODE=$($SiteCode.SiteCode)")
        $temp[1].InnerXml = [string]("MP=$($SiteCode.SiteServer)")
        $temp[2].InnerXml = [string]("FSP=$($SiteCode.SiteServer)")
        $temp[3].InnerXml = [string]("DNSSUFFIX=$(Get-WmiObject Win32_Computersystem | Select-Object -ExpandProperty Domain)")
        $temp[4].InnerXml = [string]("/Source:$(Join-Path -Path $CHDir -ChildPath "Client")")
        $temp[5].InnerXml = [string]("/MP=$($SiteCode.SiteServer)")

        # Log
        $ConfigXML.Configuration.Log[0].Share = [string]($CHLogsDir)
        $ConfigXML.Configuration.Log[1].Server = [string]($SiteCode.SiteServer)
        $ConfigXML.Configuration.Log[1].Enable = [string]($false)

        # Save XML
        $ConfigXML.Save("$(Join-Path -Path $CHDir -ChildPath ($ConfigXML.BaseURI | Split-Path -Leaf))")
    }
    catch {
        Write-CMLogEntry -Value "Error writing data to configuration XML. Message: $($_.Exception.Message)" -Severity 2
    }
}
