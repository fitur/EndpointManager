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

# HPIA variables
$URI = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html"
$WebReq = Invoke-WebRequest -Uri $URI -UseBasicParsing
$SoftPaqURL = $WebReq.Links | Where-Object {$_.href -match "exe"} | Select-Object -ExpandProperty href
$SoftPaqDownloadPath = "{0}\{1}" -f $env:TEMP, ($SoftPaqURL | Split-Path -Leaf)

# Download HPIA
Start-BitsTransfer -Source $SoftPaqURL -Destination $SoftPaqDownloadPath
$HPIAInstallExecutable = Get-Item $SoftPaqDownloadPath -ErrorAction Stop

# Set script variables
$OS = "Win10"
$SSMONLY = "ssm"
$Category1 = "bios"
$Category2 = "driver"
$Category3 = "firmware"
$RepositoryPath = "\\sccm07\sources\HPIA" # Change me
$LogFile = "$RepositoryPath\RepoUpdate.log"

# Import model data from CSV
$ModelImport = Import-Csv -Path "$RepositoryPath\Models.csv" | Sort-Object -Unique Model

foreach ($Model in $ModelImport) {
    Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
    Log -Message "Checking if repository for model $($Model.Model) aka $($Model.ProdCode) exists" -LogFile $LogFile
    if (Test-Path "$($RepositoryPath)\$($Model.Model)\Repository") { Log -Message "Repository for model $($Model.Model) aka $($Model.ProdCode) already exists" -LogFile $LogFile }
    if (-not (Test-Path "$($RepositoryPath)\$($Model.Model)\Repository")) {
        Log -Message "Repository for $($Model.Model) does not exist, creating now" -LogFile $LogFile
        New-Item -ItemType Directory -Path "$($RepositoryPath)\$($Model.Model)\Repository"
        if (Test-Path "$($RepositoryPath)\$($Model.Model)\Repository") {
            Log -Message "$($Model.Model) HPIA folder and repository subfolder successfully created" -LogFile $LogFile
            }
        else {
            Log -Message "Failed to create repository subfolder!" -LogFile $LogFile
            Exit
        }
    }
    if (-not (Test-Path "$($RepositoryPath)\$($Model.Model)\Repository\.repository")) {
        Log -Message "Repository not initialized, initializing now" -LogFile $LogFile
        Set-Location -Path "$($RepositoryPath)\$($Model.Model)\Repository"
        Initialize-Repository
        if (Test-Path "$($RepositoryPath)\$($Model.Model)\Repository\.repository") {
            Log -Message "$($Model.Model) repository successfully initialized" -LogFile $LogFile
        }
        else {
            Log -Message "Failed to initialize repository for $($Model.Model)" -LogFile $LogFile
            Exit
        }
    }    
    
    Log -Message "Set location to $($Model.Model) repository" -LogFile $LogFile
    Set-Location -Path "$($RepositoryPath)\$($Model.Model)\Repository"

    ## Extract HPIA executable into Repository directory
    $HPIAInstallParams = '-f"{0}" -s -e' -f "$($RepositoryPath)\$($Model.Model)"
    Start-Process -FilePath $HPIAInstallExecutable.FullName -ArgumentList $HPIAInstallParams -Wait -ErrorAction Stop
      
    #Log -Message "Configure notification for $($Model.Model)" -LogFile $LogFile
    #Set-RepositoryNotificationConfiguration your.smtp.server
    #Add-RepositorySyncFailureRecipient -to you@yourdomain.com
    
    Log -Message "Remove any existing repository filter for $($Model.Model) repository" -LogFile $LogFile
    Remove-RepositoryFilter -Platform $($Model.ProdCode) -Yes
    
    Log -Message "Applying repository filter to $($Model.Model) repository ($os $($Model.OSVER), $Category1 and $Category2 and $Category3)" -LogFile $LogFile
    Add-RepositoryFilter -Platform $($Model.ProdCode) -Os $OS -OsVer $($Model.OSVER) -Category $Category1
    Add-RepositoryFilter -Platform $($Model.ProdCode) -Os $OS -OsVer $($Model.OSVER) -Category $Category2
    Add-RepositoryFilter -Platform $($Model.ProdCode) -Os $OS -OsVer $($Model.OSVER) -Category $Category3
    
    Log -Message "Invoking repository sync for $($Model.Model) repository ($OS $($Model.OSVER), $Category1 and $Category2 and $Category3)" -LogFile $LogFile
    Invoke-RepositorySync
    
    Log -Message "Invoking repository cleanup for $($Model.Model) repository for $Category1 and $Category2 and $Category3 categories" -LogFile $LogFile
    Invoke-RepositoryCleanup

    Log -Message "Confirm HPIA files are up to date for $($Model.Model)" -LogFile $LogFile
    $RobocopySource = "$($RepositoryPath)\HPIA Base"
    $RobocopyDest = "$($RepositoryPath)\$($Model.Model)"
    $RobocopyArg = '"'+$RobocopySource+'"'+' "'+$RobocopyDest+'"'+' /E'
    $RobocopyCmd = "robocopy.exe"
    Start-Process -FilePath $RobocopyCmd -ArgumentList $RobocopyArg -Wait

    # Create SCCM package
    Log -Message "Invoking SCCM environment $($SiteCode.SiteCode) on server $($SiteCode.SiteServer)" -LogFile $LogFile
    Invoke-CMEnvironment
    $CMPackageName = ("HPIA - $($Model.Model) - $($Model.OSVER)")
    $CMDPGroupName = Get-CMDistributionPointGroup -ErrorAction SilentlyContinue | Sort-Object -Descending MemberCount | Select-Object -First 1 -ExpandProperty Name
    if ($null -eq (Get-CMPackage -Name $CMPackageName -Fast)) {
        $CMPackage = New-CMPackage -Name $CMPackageName -Path "$($RepositoryPath)\$($Model.Model)" -Description ('select * from win32_baseboard where product like "%{0}%"' -f $Model.ProdCode) -ErrorAction Stop
        Start-CMContentDistribution -InputObject $CMPackage -DistributionPointGroupName $CMDPGroupName
        
        # Set local directory path
        Set-Location $env:SystemDrive
        
        Log -Message "Created and distributed SCCM package $CMPackageName ($($CMPackage.PackageID))." -LogFile $LogFile
    }
    else {
        $CMPackage = Get-CMPackage -Name $CMPackageName -Fast
        Invoke-CMContentRedistribution -InputObject $CMPackage -DistributionPointGroupName $CMDPGroupName

        # Set local directory path
        Set-Location $env:SystemDrive
        
        Log -Message "Redistributed SCCM package $CMPackageName ($($CMPackage.PackageID))." -LogFile $LogFile
    }

    # Set local directory path
    Set-Location -Path $RepositoryPath
}
Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
Log -Message "Repository Update Complete" -LogFile $LogFile
Log -Message "----------------------------------------------------------------------------" -LogFile $LogFile
Set-Location -Path $RepositoryPath