# Repo settings variables
$HPIARepoPath = "\\sccm07\sources\HPIARepository" # Change this

# HPIA variables
$URI = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html"
$WebReq = Invoke-WebRequest -Uri $URI -UseBasicParsing
$SoftPaqURL = $WebReq.Links | Where-Object {$_.href -match "exe"} | Select-Object -ExpandProperty href
$SoftPaqDownloadPath = "{0}\{1}" -f $env:TEMP, ($SoftPaqURL | Split-Path -Leaf)

# Download HPIA
Start-BitsTransfer -Source $SoftPaqURL -Destination $SoftPaqDownloadPath

# Device variables
$HPProductInfo = Get-WmiObject -Namespace Root\WMI -Class MS_SystemInformation | Select-Object BaseBoardProduct, SystemProductName
$WindowsVersion = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' –Name ReleaseID –ErrorAction Stop).ReleaseID
[PSCustomObject]@{ProdCode = $HPProductInfo.BaseBoardProduct; Model = $HPProductInfo.SystemProductName; OSVER = $WindowsVersion} | Export-Csv -Path ("{0}\Models.csv" -f $HPIARepoPath) -Force -NoTypeInformation -Append

# Install HPIA
$HPIAInstallExecutable = Get-Item $SoftPaqDownloadPath -ErrorAction Stop
$HPIAInstallParams = '-f"{0}\HPIA" -s -e' -f ${env:ProgramFiles(x86)}
Start-Process -FilePath $HPIAInstallExecutable.FullName -ArgumentList $HPIAInstallParams -Wait -ErrorAction Stop