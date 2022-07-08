# HPIA variables
$URI = "http://ftp.hp.com/pub/caps-softpaq/cmit/HPIA.html"
$SPList = "https://rgintunew10.blob.core.windows.net/drivers/splist.txt"
$HPIAPath = Join-Path -Path $env:SystemDrive -ChildPath "HPIA"

# Scrape HPIA download link
$WebReq = Invoke-WebRequest -Uri $URI -UseBasicParsing -ErrorAction Stop
$SoftPaqURL = $WebReq.Links | Where-Object {$_.href -match "exe"} | Select-Object -ExpandProperty href

# Package attributes
if ($SoftPaqURL) {
    $SoftPaqDownloadPath = "{0}\{1}" -f $env:TEMP, ($SoftPaqURL | Split-Path -Leaf)
    $HPIAInstallParams = '-f"{0}" -s -e' -f $HPIAPath
}

# Download process
if ($SoftPaqDownloadPath) {
    Invoke-WebRequest -Uri $SoftPaqURL -UseBasicParsing -OutFile $SoftPaqDownloadPath -ErrorAction Stop
    $HPIAInstallExecutable = Get-Item $SoftPaqDownloadPath -ErrorAction Stop
}

# Extract process
if ($HPIAInstallExecutable) {
    Start-Process -FilePath $HPIAInstallExecutable.FullName -ArgumentList $HPIAInstallParams -Wait -ErrorAction Stop
    $HPIABinary = Get-ChildItem -Path $HPIAPath -Filter "HPImageAssistant.exe" -ErrorAction Stop
}

# SPList enumerate process
Invoke-WebRequest -Uri $SPlist -UseBasicParsing -OutFile (Join-Path -Path $HPIAPath -ChildPath ($SPlist | Split-Path -Leaf)) -ErrorAction Stop
$SPListFile = Get-ChildItem -Path $HPIAPath -Filter ($SPlist | Split-Path -Leaf) -ErrorAction SilentlyContinue

# Driver update process
if ($HPIABinary) {
    if ($HPIAFile) {
        Start-Process -FilePath $HPIABinary.FullName -ArgumentList "/Silent /Noninteractive /Debug /Operation:Analyze /SoftpaqDownloadFolder:$(Join-Path -path $HPIAPath -ChildPath 'Downloads') /SPList:'$($SPListFile.FullName)' /ReportFolder:$(Join-Path -path $HPIAPath -ChildPath 'Reports')" -Wait -ErrorAction SilentlyContinue
    } else {
        Start-Process -FilePath $HPIABinary.FullName -ArgumentList "/Silent /Noninteractive /Debug /Operation:Analyze /Action:Install /Selection:All /Category:Drivers /SoftpaqDownloadFolder:$(Join-Path -path $HPIAPath -ChildPath 'Downloads') /ReportFolder:$(Join-Path -path $HPIAPath -ChildPath 'Reports')" -Wait -ErrorAction Stop
    }
}