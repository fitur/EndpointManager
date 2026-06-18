# Variables
$CMPackageName = "HP Image Assistant Binary Package"

# Modules
Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop

# CM values
$script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
Set-Location -Path $SiteCode":" -ErrorAction Stop

if ($null -eq (Get-CMPackage -name $CMPackageName -Fast)) {
    $HPIABinaryPath = Read-Host -Prompt "Path to save HPIA binary files"
    $HPIAPackage = New-CMPackage -Name $CMPackageName -Path $HPIABinaryPath -ErrorAction Stop
} else {
    $HPIAPackage = Get-CMPackage -Name $CMPackageName -Fast -ErrorAction Stop
    $HPIABinaryPath = $HPIAPackage.PkgSourcePath
}

# HPIA variables
$URI = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html"
$WebReq = Invoke-WebRequest -Uri $URI -ErrorAction Stop
$SoftPaqURL = $WebReq.Links | Where-Object {$_.href -match "exe"} | Select-Object -ExpandProperty href
$SoftPaqDownloadPath = "{0}\{1}" -f $env:TEMP, ($SoftPaqURL | Split-Path -Leaf)
$HPIAVersion = (($WebReq.AllElements | Where-Object {($_.tagname -eq 'tr') -and ($_.innerHTML -match $SoftPaqURL)}).innerHTML -split "`n" | Select-Object -First 1) -replace "<TD>","" -replace "</TD>",""
$HPIADescription = (($WebReq.AllElements | Where-Object {($_.tagname -eq 'tr') -and ($_.innerHTML -match $SoftPaqURL)}).innerHTML -split "`n" | Select-Object -Skip 1 -First 1) -replace "<TD>","" -replace "</TD>",""
$HPIAInstallParams = '-f"{0}" -s -e' -f $HPIABinaryPath

# Run installer if version is greater than current
if (([string]::IsNullOrEmpty($HPIAPackage.Version)) -or ([System.Version]$HPIAVersion -gt [System.Version]$HPIAPackage.Version)) {
    Start-BitsTransfer -Source $SoftPaqURL -Destination $SoftPaqDownloadPath
    $HPIAInstallExecutable = Get-Item $SoftPaqDownloadPath -ErrorAction Stop
    Start-Process -FilePath $HPIAInstallExecutable.FullName -ArgumentList $HPIAInstallParams -Wait -ErrorAction Stop
    $HPIAPackage | Set-CMPackage -Version $HPIAVersion -Description $HPIADescription

    # Distribute CM package
    if ((Get-CMDistributionStatus -Id $HPIAPackage.PackageID | Select-Object -ExpandProperty Targeted) -gt 0) {
        $HPIAPackage | Invoke-CMContentRedistribution -ErrorAction Stop
    } else {
        $HPIAPackage | Start-CMContentDistribution -DistributionPointName (Get-CMDistributionPointInfo | Sort-Object -Descending Groupcount | Select-Object -First 1 -ExpandProperty Name)
    }
}