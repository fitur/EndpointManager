 #Requires -Modules GroupPolicy
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
    Write-CMLogEntry -Value "----------- Starting Client Health installation." -Severity 1

    # Generate download URI for Client Health
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $WebRequest = Invoke-WebRequest -Uri $URI
    $DownloadURI = "{0}{1}" -f ($URI | Split-Path -Parent), ($WebRequest.Links | Where-Object { $_.innerText -like "ConfigMgrClientHealth-*.zip" } | Select-Object -ExpandProperty data-url)

    # Gather shared folders information - Part 1
    try {
        $CMDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { $_.Name -match "SMS_$($SiteCode)" } | Select-Object -ExpandProperty Name))))
        $CHDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { (($_.Name -match $CHShareName) -and ($_.Name -notmatch "Logs")) } | Select-Object -ExpandProperty Name))))
        $CHLogsDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { (($_.Name -match $CHShareName) -and ($_.Name -match "Logs")) } | Select-Object -ExpandProperty Name))))
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering directories. Message: $($_.Exception.Message)" -Severity 2
    }

    # Gather basic information, download Client Health and create new directories
    if ($CHDir -notmatch $CHShareName) {
        try {
            ## Create Client Health share
            Invoke-Command -ComputerName $SiteCode.SiteServer -ArgumentList $SiteCode, $CHShareName, $DownloadURI -Verbose -ScriptBlock {
                param (
                    $SiteCode = $args[0],
                    $CHShareName = $args[1],
                    $DownloadURI = $args[2]
                )

                # Generate variables
                $LocalPath = (Join-Path -Path ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer | Where-Object { $_.Name -match "SMS_$($SiteCode.SiteCode)" } | Select-Object -ExpandProperty Path).SubString(0, 3)) -ChildPath $CHShareName)

                # Create directory & set ACL
                if (!(Test-Path -Path $LocalPath)) {
                    # Create directory
                    New-Item -Path $LocalPath -ItemType Directory -ErrorAction Stop
            
                    # Set ACL
                    $ACL = Get-Acl -Path $LocalPath -ErrorAction Stop
                    $ROAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule("$(Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain)\Domain Computers", "ReadAndExecute, Synchronize", "ContainerInherit, ObjectInherit", "None" , "Allow")
                    $ACL.AddAccessRule($ROAccessRule)
                    $ACL | Set-Acl -Path $LocalPath -ErrorAction Stop
                }

                # Share directory
                if (!(Get-SmbShare -Name "$($CHShareName)$" -ErrorAction SilentlyContinue)) {
                    New-SmbShare -Name "$($CHShareName)$" -Path $LocalPath -FullAccess Everyone
                }

                # Download and extract Client Health
                if (!(Test-Path ("{0}\{1}" -f $LocalPath, ($DownloadURI | Split-Path -Leaf)))) {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    Invoke-WebRequest -Uri $DownloadURI -OutFile ("{0}\{1}" -f $LocalPath, ($DownloadURI | Split-Path -Leaf)) -ErrorAction Stop
                    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
                    [System.IO.Compression.ZipFile]::ExtractToDirectory($("{0}\{1}" -f $LocalPath, ($DownloadURI | Split-Path -Leaf)), $LocalPath)
                }

                # Share Logs directory
                if (!(Get-SmbShare -Name "$($CHShareName)Logs$" -ErrorAction SilentlyContinue)) {
                    # Set Logs ACL
                    $ACL = Get-Acl -Path (Join-Path -Path $LocalPath -ChildPath "Logs")
                    $RWAccessRule = New-Object -TypeName System.Security.AccessControl.FileSystemAccessRule("$(Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain)\Domain Computers", "FullControl", "ContainerInherit, ObjectInherit", "None" , "Allow")
                    $ACL.SetAccessRule($RWAccessRule)
                    $ACL | Set-Acl -Path (Join-Path -Path $LocalPath -ChildPath "Logs")

                    # Share directory
                    New-SmbShare -Name "$($CHShareName)Logs$" -Path (Join-Path -Path $LocalPath -ChildPath "Logs") -FullAccess Everyone -ErrorAction Stop
                }

                # Copy CM Client installation files
                if (!(Test-Path -Path (Join-Path -Path $LocalPath -ChildPath "Client"))) {
                    $CMDir = Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { $_.Name -match "SMS_$($SiteCode)" } | Select-Object -ExpandProperty Path
                    Copy-Item -Path (Join-Path -Path $CMDir -ChildPath "Client") -Destination $LocalPath -Recurse -Force
                }
            }
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "Failed to create directories. Message: $($_.Exception.Message)" -Severity 2
        }
    }

    # Gather shared folders information - Part 2
    try {
        $CMDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { $_.Name -match "SMS_$($SiteCode)" } | Select-Object -ExpandProperty Name))))
        $CHDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { (($_.Name -match $CHShareName) -and ($_.Name -notmatch "Logs")) } | Select-Object -ExpandProperty Name))))
        $CHLogsDir = ("\\{0}" -f (Join-Path -Path $SiteCode.SiteServer -ChildPath ((Get-WmiObject -Class Win32_Share -ComputerName $SiteCode.SiteServer -ErrorAction Stop | Where-Object { (($_.Name -match $CHShareName) -and ($_.Name -match "Logs")) } | Select-Object -ExpandProperty Name))))
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error gathering directories. Message: $($_.Exception.Message)" -Severity 2
    }

    # Edit XML configuration version number
    if ($CHDir -match $CHShareName) {
        try {
            # Get siteserver FQDN
            try {
                $SiteServer = Invoke-Command -ComputerName $SiteCode.SiteServer -Verbose -ScriptBlock {[System.Net.Dns]::GetHostByName($env:computerName)} -ErrorAction Stop | Select-Object -ExpandProperty HostName
            }
            catch [System.Exception] {
                $SiteServer = $SiteCode.SiteServer
            }

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
            $temp[1].InnerXml = [string]("MP=$SiteServer")
            $temp[2].InnerXml = [string]("FSP=$SiteServer")
            $temp[3].InnerXml = [string]("DNSSUFFIX=$(Get-WmiObject Win32_Computersystem | Select-Object -ExpandProperty Domain)")
            $temp[4].InnerXml = [string]("/Source:$(Join-Path -Path $CHDir -ChildPath "Client")")
            $temp[5].InnerXml = [string]("/MP=$SiteServer")

            # Log
            $ConfigXML.Configuration.Log[0].Share = [string]($CHLogsDir)
            $ConfigXML.Configuration.Log[1].Server = [string]($SiteServer)
            $ConfigXML.Configuration.Log[1].Enable = [string]($false)

            # Options
            $ConfigXML.Configuration.Option[6].StartRebootApplication = [string]($false)

            # Save XML
            $ConfigXML.Save("$(Join-Path -Path $CHDir -ChildPath ($ConfigXML.BaseURI | Split-Path -Leaf))")
        }
        catch [System.Exception] {
            Write-CMLogEntry -Value "Error writing data to configuration XML. Message: $($_.Exception.Message)" -Severity 2
        }
    }

    # Edit ConfigMgrClientHealth.ps1 if neccessary
    try {
        #$CHPSScript = Get-Content -Path "filesystem::$(Join-Path -Path $CHDir -ChildPath "ConfigMgrClientHealth.ps1")"
        #$CHScriptLine = $CHPSScript.IndexOf(($CHPSScript | Select-String -SimpleMatch '(($Webservice -eq $null)) -or ($Webservice -eq ""))'))
        #$CHPSScript[$CHScriptLine] = 'if (($SQLLogging -like "true") -and (($Webservice -eq $null) -or ($Webservice -eq ""))) {'
        #$CHPSScript | Out-File -FilePath "filesystem::$(Join-Path -Path $CHDir -ChildPath "ConfigMgrClientHealth.ps1")" -Force
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error editing ps1. Message: $($_.Exception.Message)" -Severity 2
    }

    # Create, edit and import GPO
    try {
        # Create GPO
        # $GPO = New-GPO -Domain (Get-WmiObject Win32_ComputerSystem | Select-Object -ExpandProperty Domain) -Name "[Temp]ConfigMgr Client Health" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-CMLogEntry -Value "Error importing GPO. Message: $($_.Exception.Message)" -Severity 2
    }
}
 
