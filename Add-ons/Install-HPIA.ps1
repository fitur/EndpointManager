 # Modules
Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop

# CM values
$script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
Set-Location -Path $SiteCode":" -ErrorAction Stop
$HPIAPackage = Get-CMPackage -Name "HP Image Assistant Binary Package" -Fast -ErrorAction Stop

# HPIA variables
$URI = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html"
$WebReq = Invoke-WebRequest -Uri $URI -ErrorAction Stop
$SoftPaqURL = $WebReq.Links | Where-Object {$_.href -match "exe"} | Select-Object -ExpandProperty href
$SoftPaqDownloadPath = "{0}\{1}" -f $env:TEMP, ($SoftPaqURL | Split-Path -Leaf)
Start-BitsTransfer -Source $SoftPaqURL -Destination $SoftPaqDownloadPath
$HPIAInstallExecutable = Get-Item $SoftPaqDownloadPath -ErrorAction Stop
$HPIABinaryPath = $HPIAPackage.PkgSourcePath

$HPIAVersion = (($WebReq.AllElements | Where-Object {($_.tagname -eq 'tr') -and ($_.innerHTML -match $SoftPaqURL)}).innerHTML -split "`n" | Select-Object -First 1) -replace "<TD>","" -replace "</TD>",""

# Run updater
$HPIAInstallParams = '-f"{0}" -s -e' -f $HPIABinaryPath
Start-Process -FilePath $HPIAInstallExecutable.FullName -ArgumentList $HPIAInstallParams -Wait -ErrorAction Stop
$HPIAPackage | Set-CMPackage -Version $HPIAVersion

# Distribute CM package
$HPIAPackage | Invoke-CMContentRedistribution 
