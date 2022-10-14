# HPIA & CMSL variables
$HPIADir = "\\sccm07\Sources\HPIA" # Change this
$RepoDir = Join-Path -Path $HPIADir -ChildPath "Repository"
$BinaryDir = Join-Path -Path $HPIADir -ChildPath "Binary"
$ModuleDir = Join-Path -Path $HPIADir -ChildPath "Modules"
$LogsDir = Join-Path -Path $HPIADir -ChildPath "Logs"
$CVAPath = Join-Path -Path $HPIADir -ChildPath "CVA.txt"
$HPIABlackListPath = Join-Path -Path $HPIADir -ChildPath "Blacklist.csv"

# Temporary variables
$CMSLURI = "https://hpia.hpcloud.hp.com/downloads/cmsl/hp-cmsl-1.6.8.exe"
$OSVersions = ("2009", "21H2")

# Configure CM variables
Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
$script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop

# Import HP modules
if ($null -eq (Get-Command -Name Get-RepositoryInfo*)) {
    try {
        # Download HPCMSL
        Start-BitsTransfer -Source $CMSLURI -Destination $ModuleDir
        $CMSLInstallExecutable = Get-Item -Path (Join-Path -Path $ModuleDir -ChildPath ($CMSLURI | Split-Path -Leaf)) -ErrorAction Stop
        $CMSLInstallParams = '/verysilent' -f $ModuleDir
        Start-Process -FilePath $CMSLInstallExecutable.FullName -ArgumentList $CMSLInstallParams -Wait -ErrorAction Stop

        # Import modules
        Import-Module $ModuleDir\HP.Sinks\HP.Sinks.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module $ModuleDir\HP.Utility\HP.Utility.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module $ModuleDir\HP.Firmware\HP.Firmware.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module $ModuleDir\HP.Softpaq\HP.Softpaq.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module $ModuleDir\HP.Private\HP.Private.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module $ModuleDir\HP.Repo\HP.Repo.psm1 -Force -ErrorAction SilentlyContinue
        Import-Module $ModuleDir\HP.ClientManagement\HP.ClientManagement.psm1 -Force -ErrorAction SilentlyContinue
    }
    catch [System.SystemException] {
        Write-Verbose -Verbose "Couldn't load HP script library modules"
    }
}

# Read blacklist if available
if (Test-Path -Path $HPIABlackListPath) {
    $HPIABlackList = Import-Csv -Path $HPIABlackListPath
} else {
    [PSCustomObject]@{
        ProdCode = "225a"
        OS = "2009"
    } | Export-Csv -NoTypeInformation -Path $HPIABlackListPath -Force -ErrorAction SilentlyContinue
}

# Create and step into directory
New-Item -Path $RepoDir -ItemType Directory -Force
Set-Location -Path $RepoDir -ErrorAction Stop

# Initialize repo
if ([System.DateTime]((Get-RepositoryInfo -ErrorAction SilentlyContinue | Select-Object -ExpandProperty DateLastModified) -split "T")[0] -lt (Get-Date).AddDays(-7)) {
    Initialize-Repository -Verbose -ErrorAction Stop
    Set-RepositoryConfiguration -Setting OnRemoteFileNotFound -Value LogAndContinue -Verbose
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable -Verbose
}

# Remove all filters from repo (cleanup)
Get-RepositoryInfo | Select-Object -ExpandProperty Filters | Select-Object -ExpandProperty Platform | ForEach-Object {Remove-RepositoryFilter -Platform $_ -Yes}

# Add all found models into repo filters
Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query 'select distinct Manufacturer, Model from SMS_G_System_COMPUTER_SYSTEM' | Where-Object {$_.Model -like "HP*"} | ForEach-Object {
    Get-HPDeviceDetails -Name $_.Model -Like -ErrorAction SilentlyContinue | ForEach-Object {
        if (($_.SystemID) -and ($_.SystemID -notin $HPIABlackList.ProdCode)) {
            Add-RepositoryFilter -Platform $_.SystemID -Os win10 -OsVer 21H2 -Category Bios,Software,Driver,Firmware -ReleaseType Recommended -Characteristic * -ErrorAction SilentlyContinue
            Add-RepositoryFilter -Platform $_.SystemID -Os win10 -OsVer 2009 -Category Bios,Software,Driver,Firmware -ReleaseType Recommended -Characteristic * -ErrorAction SilentlyContinue
        }
    }
}

# Add models from separate CVA-file into repo filters
#Get-Content -Path $CVAPath | ForEach-Object {
#    Get-HPDeviceDetails -Name $_ -Like -ErrorAction SilentlyContinue | ForEach-Object {
#        if ($_.SystemID) {
#            Add-RepositoryFilter -Platform $_.SystemID -Os win10 -OsVer 21H2 -Category Bios,Software,Driver,Software -ReleaseType Recommended -Characteristic * -ErrorAction SilentlyContinue
#            Add-RepositoryFilter -Platform $_.SystemID -Os win10 -OsVer 21H1 -Category Bios,Software,Driver,Software -ReleaseType Recommended -Characteristic * -ErrorAction SilentlyContinue
#        }
#    }
#}

# Initiate sync and cleanup
Invoke-RepositorySync
Invoke-RepositoryCleanup