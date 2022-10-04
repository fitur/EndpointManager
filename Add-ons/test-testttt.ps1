 function Import-CMEnvironment {
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        #Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    }
}

$HPIADir = "\\han-res-103\sources$\OSD\Drivers\HPIA"
$RepoDir = Join-Path -Path $HPIADir -ChildPath "Repository"
$BinaryDir = Join-Path -Path $HPIADir -ChildPath "Binary"
$ModuleDir = Join-Path -Path $HPIADir -ChildPath "Modules"
$LogsDir = Join-Path -Path $HPIADir -ChildPath "Logs"
$CVAPath = Join-Path -Path $HPIADir -ChildPath "CVA.txt"

# Create and step into directory
New-Item -Path $RepoDir -ItemType Directory -Force
Set-Location -Path $RepoDir -ErrorAction Stop

# Initialize repo
Initialize-Repository -Verbose -ErrorAction Stop
Set-RepositoryConfiguration -Setting OnRemoteFileNotFound -Value LogAndContinue -Verbose
Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable -Verbose

Get-RepositoryInfo | Select-Object -ExpandProperty Filters | Select-Object -ExpandProperty Platform | ForEach-Object {Remove-RepositoryFilter -Platform $_ -Yes}

Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query 'select distinct Manufacturer, Model from SMS_G_System_COMPUTER_SYSTEM' | Where-Object {$_.Model -like "HP*"} | ForEach-Object {
    $SystemID = Get-HPDeviceDetails -Name $_.Model -Like | Select-Object -ExpandProperty SystemID
    #Add-RepositoryFilter -Platform $SystemID -Os win10 -OsVer 21H2 -Category Bios,Software,Driver,Software -ReleaseType Recommended -Characteristic *
}
    


#Add-RepositoryFilter -Platform 894F -Os win10 -OsVer 21H2 -Category Bios,Firmware,Driver,Software -ReleaseType Recommended -Characteristic *
#Add-RepositoryFilter -Platform 8952 -Os win10 -OsVer 21H2 -Category Bios,Firmware,Driver,Software -ReleaseType Recommended -Characteristic *

Invoke-RepositorySync
Invoke-RepositoryCleanup
 
