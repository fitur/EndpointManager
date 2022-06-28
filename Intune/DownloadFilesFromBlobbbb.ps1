## Variables
$URL = "https://rgintunew10.blob.core.windows.net/branding/Branding/"
$FilePrefix = "NLTG_TeamsBG_"
$FileExtension = "jpg"
$DownloadPath = "$env:APPDATA\Microsoft\Teams\Backgrounds\Uploads"

## Create directory if it doesn't exist
if (!(Test-Path -Path $DownloadPath)) {
    New-Item -Path $DownloadPath -ItemType Directory -Force
}
## Query and download each file
for ($i = 1; $i -le 24; $i++) {
    $FileURL = ("{0}{1}{2}.{3}" -f $URL, $FilePrefix, ([string]$i).PadLeft(2,"0"), $FileExtension)
    Invoke-WebRequest -Uri $FileURL -OutFile (Join-Path -Path $DownloadPath -ChildPath (Split-Path -Path $FileURL -Leaf))
}