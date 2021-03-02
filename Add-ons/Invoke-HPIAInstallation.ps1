  begin {
    # Modules
    Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop

    # Functions
    function Log {
        Param (
		    [Parameter(Mandatory=$false)]
		    $Message,
 
		    [Parameter(Mandatory=$false)]
		    $ErrorMessage,
 
		    [Parameter(Mandatory=$false)]
		    $Component,
 
		    [Parameter(Mandatory=$false)]
		    [int]$Type,
		
		    [Parameter(Mandatory=$true)]
		    $LogFile
	    )
    <#
    Type: 1 = Normal, 2 = Warning (yellow), 3 = Error (red)
    #>
	    $Time = Get-Date -Format "HH:mm:ss.ffffff"
	    $Date = Get-Date -Format "MM-dd-yyyy"
 
	    if ($ErrorMessage -ne $null) {$Type = 3}
	    if ($Component -eq $null) {$Component = " "}
	    if ($Type -eq $null) {$Type = 1}
 
	    $LogMessage = "<![LOG[$Message $ErrorMessage" + "]LOG]!><time=`"$Time`" date=`"$Date`" component=`"$Component`" context=`"`" type=`"$Type`" thread=`"`" file=`"`">"
	    $LogMessage | Out-File -Append -Encoding UTF8 -FilePath $LogFile
    }

    function Invoke-CMEnvironment {
        try {
            Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
            $script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
            Set-location $SiteCode":" -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
        }
    }

    function Install-HPSL {
        # HP script library 
        $HPSLURI = "https://hpia.hpcloud.hp.com/downloads/cmsl/hp-cmsl-1.6.2.exe" # Make dynamic
        $HPSLDownloadPath = "{0}\{1}" -f $env:TEMP, ($HPSLURI | Split-Path -Leaf)
        Start-BitsTransfer -Source $HPSLURI -Destination $HPSLDownloadPath -ErrorAction Stop
        Start-Process -FilePath $HPSLDownloadPath -ArgumentList "/VERYSILENT /NOREBOOT" -Wait
    }

    # Import CM module
    Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
}
process {
    # HPIA variables
    $URI = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html"
    $WebReq = Invoke-WebRequest -Uri $URI -UseBasicParsing
    $SoftPaqURL = $WebReq.Links | Where-Object {$_.href -match "exe"} | Select-Object -ExpandProperty href
    $SoftPaqDownloadPath = "{0}\{1}" -f $env:TEMP, ($SoftPaqURL | Split-Path -Leaf)

    # Download HPIA
    Start-BitsTransfer -Source $SoftPaqURL -Destination $SoftPaqDownloadPath
    $HPIAInstallExecutable = Get-Item $SoftPaqDownloadPath -ErrorAction Stop

    # Set script variables
    $CMServer = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop | Select-Object -ExpandProperty Root
    $OS = "Win10"
    $SSMONLY = "ssm"
    $Category1 = "bios"
    $Category2 = "driver"
    $Category3 = "firmware"
    $RootPath = "\\$CMServer\sources\HPIA" # Change me
    $RepositoryRoot = "$RootPath\Repository" # Change me
    $LogFile = "$RootPath\RepoUpdate.log"

    # Import model data from CSV
    $ModelImport = Import-Csv -Path "$RootPath\Models.csv"

    foreach ($Model in $ModelImport) {
        Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
        Log -Message "Checking if repository for model $($Model.Model) aka $($Model.ProdCode) exists" -LogFile $LogFile

        # Create repository per model and OS version
        $ModelRepoPath = "{0}\{1}\{2}\{3}" -f $RepositoryRoot, $Model.Model, $Model.OSVER, "Repository"
    
        if (Test-Path -Path $ModelRepoPath) {
            Log -Message "Repository for model $($Model.Model) aka $($Model.ProdCode) already exists, continuing" -LogFile $LogFile
        } else {
            Log -Message "Repository for $($Model.Model) does not exist, creating now" -LogFile $LogFile

            # Create subdirectories per model and OS version
            try {
                New-Item -ItemType Directory -Path $ModelRepoPath -Force -ErrorAction Stop
                Log -Message "$($Model.Model) HPIA folder and repository subfolder successfully created" -LogFile $LogFile
            }
            catch [System.SystemException] {
                Log -ErrorMessage "Failed to create repository subfolder!" -LogFile $LogFile
            }
        }

        if (Test-Path -Path ("$ModelRepoPath\.repository")) {
            Log -Message "Repository already initialized, continuing" -LogFile $LogFile
        } else {
            Log -Message "Repository not initialized" -LogFile $LogFile
        
            try {
                Log -Message "Stepping into repository directory" -LogFile $LogFile
                Set-Location $ModelRepoPath -ErrorAction Stop
            }
            catch [System.SystemException] {
                Log -ErrorMessage "Failed to step into repository directory!" -LogFile $LogFile
            }

            try {
                Log -Message "Running HPIA repository initialization commandlet" -LogFile $LogFile
                Initialize-Repository -ErrorAction Stop
            }
            catch [System.SystemException] {
                Log -ErrorMessage "Failed to run HPIA initialization commandlet!" -LogFile $LogFile
            }

            if (Test-Path -Path ("$ModelRepoPath\.repository")) {
                Log -Message "Successfully initiated repository" -LogFile $LogFile
            } else {
                Log -ErrorMessage "Failed to initiate repository!" -LogFile $LogFile
            }
        }

        if (Test-Path -Path ("$($ModelRepoPath | Split-Path -Parent)\HPImageAssistant.exe")) {
            Log -Message "HPIA binaries already present, continuing" -LogFile $LogFile
        } else {
            ## Extract HPIA executable into Repository directory
            try {
                $HPIAInstallParams = '-f"{0}" -s -e' -f ($ModelRepoPath | Split-Path -Parent)
                Start-Process -FilePath $HPIAInstallExecutable.FullName -ArgumentList $HPIAInstallParams -Wait -ErrorAction Stop
                Log -Message "Extracted HPIA binaries into model root directory" -LogFile $LogFile
            }
            catch [System.SystemException] {
                Log -ErrorMessage "Failed to extract HPIA binaries into model root directory" -LogFile $LogFile
            }
        }

        Log -Message "Set location to $($Model.Model) repository" -LogFile $LogFile
        Set-Location -Path $ModelRepoPath -ErrorAction Stop

        #Log -Message "Configure notification for $($Model.Model)" -LogFile $LogFile
        #Set-RepositoryNotificationConfiguration your.smtp.server
        #Add-RepositorySyncFailureRecipient -to you@yourdomain.com
    
        try {
            Log -Message "Remove any existing repository filter for $($Model.Model) repository" -LogFile $LogFile
            Remove-RepositoryFilter -Platform $($Model.ProdCode) -Yes -ErrorAction Stop
        }
        catch [System.SystemException] {
            Log -ErrorMessage "Failed to remove existing repository filters for $($Model.Model) repository!" -LogFile $LogFile
        }
    
        try {
            Log -Message "Applying repository filter to $($Model.Model) repository ($OS $($Model.OSVER), $Category1 and $Category2 and $Category3)" -LogFile $LogFile
            Add-RepositoryFilter -Platform $($Model.ProdCode) -Os $OS -OsVer $($Model.OSVER) -Category $Category1 -ErrorAction Stop
            Add-RepositoryFilter -Platform $($Model.ProdCode) -Os $OS -OsVer $($Model.OSVER) -Category $Category2 -ErrorAction Stop
            Add-RepositoryFilter -Platform $($Model.ProdCode) -Os $OS -OsVer $($Model.OSVER) -Category $Category3 -ErrorAction Stop
        }
        catch [System.SystemException] {
            Log -ErrorMessage "Failed to apply repository filters for $($Model.Model) repository!" -LogFile $LogFile
        }
    
        try {
            Log -Message "Invoking repository sync for $($Model.Model) repository (this will take some time)" -LogFile $LogFile
            Invoke-RepositorySync -ErrorAction Stop
        }
        catch [System.SystemException] {
            Log -ErrorMessage "Failed to invoke repository sync for $($Model.Model)!" -LogFile $LogFile
        }
    
        try {
            Log -Message "Invoking repository cleanup for $($Model.Model) repository for all categories" -LogFile $LogFile
            Invoke-RepositoryCleanup -ErrorAction Stop
        }
        catch [System.SystemException] {
            Log -ErrorMessage "Failed to invoke repository cleanup for $($Model.Model)!" -LogFile $LogFile
        }

        # Create CM package
        Invoke-CMEnvironment
        $CMPackageName = ("HPIA - $($Model.Model) - $($Model.OSVER)")
        $CMDPGroupName = Get-CMDistributionPointGroup -ErrorAction SilentlyContinue | Sort-Object -Descending MemberCount | Select-Object -First 1 -ExpandProperty Name
        if ($null -eq (Get-CMPackage -Name $CMPackageName -Fast)) {
            $CMPackage = New-CMPackage -Name $CMPackageName -Path ($ModelRepoPath | Split-Path -Parent) -Description ('select * from win32_baseboard where product like "%{0}%"' -f $Model.ProdCode) -ErrorAction Stop
            #$CMProgram = New-CMProgram -PackageId $CMPackage.PackageId -CommandLine
            Start-CMContentDistribution -InputObject $CMPackage -DistributionPointGroupName $CMDPGroupName
        
            # Set local directory path
            Set-Location $env:SystemDrive
        
            Log -Message "Created and distributed SCCM package $CMPackageName ($($CMPackage.PackageID))" -LogFile $LogFile
        }
        else {
            $CMPackage = Get-CMPackage -Name $CMPackageName -Fast
            Invoke-CMContentRedistribution -InputObject $CMPackage -DistributionPointGroupName $CMDPGroupName

            # Set local directory path
            Set-Location $env:SystemDrive
        
            Log -Message "Redistributed SCCM package $CMPackageName ($($CMPackage.PackageID))" -LogFile $LogFile

        }

        Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
    }

    Log -Message "Repository Update Complete" -LogFile $LogFile
    Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
    Set-Location -Path $RepositoryRoot
}
