## Variables
$JSONDir = "\\ne.mytravelgroup.net\system\SCCM\Software\EvergreenJSON"
$EvergreenIndexFileName = "index.csv"

## Trust PowerShell Gallery
if (Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" -and $_.InstallationPolicy -ne "Trusted" }) {
    Install-PackageProvider -Name "NuGet" -MinimumVersion 2.8.5.208 -Force
    Set-PSRepository -Name "PSGallery" -InstallationPolicy "Trusted"
}

## Install or update Evergreen module
$EvergreenCurrent = Get-Module -Name "Evergreen" -ListAvailable | Sort-Object -Property Version -Descending | Select-Object -First 1
$EvergreenNewest = Find-Module -Name "Evergreen"
if (!$EvergreenCurrent) {
    Write-Host "-------------"
    Write-Host "Evergreen module not found. Installing."
    Install-Module -Name "Evergreen" -Force
}
elseif ([System.Version]$EvergreenNewest.Version -gt [System.Version]$EvergreenCurrent.Version) {
    Write-Host "-------------"
    Write-Host "Evergreen module out of date. Updating."
    Update-Module -Name "Evergreen" -Force
}
elseif (($EvergreenCurrent) -and ([System.Version]$EvergreenNewest.Version -eq [System.Version]$EvergreenCurrent.Version)) {
    Write-Host "-------------"
    Write-Host "Evergreen module up to date. Continuing."
}

## Import Evergreen module
Import-Module -Name "Evergreen" -Force

## Directory setup
$EvergreenTempDir = New-Item -Name "Evergreen" -Path (Join-Path -Path $env:SystemDrive -ChildPath "Temp") -ItemType Directory -Force
$EvergreenJSONDir = Get-Item -Path $JSONDir
$EvergreenCSV = Import-Csv -Path (Get-ChildItem -Path $EvergreenJSONDir -Filter $EvergreenIndexFileName).FullName

## Get applications list
Write-Host "-------------"
Write-Host "Gathering installed applications"
$InstalledApps = Get-CimInstance -ClassName Win32_Product

## Loop through applications
foreach ($TempEvergreenApp in $EvergreenCSV) {
    Write-Host "-------------"
    Write-Host "Evaluating application: $($TempEvergreenApp.Application)"
    if ($InstalledApps.Name -match $TempEvergreenApp.Application) {
        Write-Host "$($TempEvergreenApp.Application) is installed. Continuing" -ForegroundColor Green
        $JSONFile = Get-ChildItem -Path $EvergreenJSONDir -Filter $TempEvergreenApp.JSONFile
        [System.Version]$CurrentVersion = $InstalledApps | Where-Object {$_.Name -eq $TempEvergreenApp.Application} | Sort-Object -Property Version -Descending | Select-Object -First 1 -ExpandProperty Version
        [System.Version]$NewVersion = Get-Content -Raw -Path $JSONFile.FullName | ConvertFrom-Json
        if ($NewVersion -gt $CurrentVersion) {
            Write-Host "$($TempEvergreenApp.Application) installed version $CurrentVersion is older than $NewVersion and will be updated" -ForegroundColor Red
            ## RUN APPLICATION DOWNLOAD
        } else {
            Write-Host "$($TempEvergreenApp.Application) installed version $CurrentVersion is newer or equal to $NewVersion and will be ignored" -ForegroundColor Green
        }
    } else {
        Write-Host "$($TempEvergreenApp.Application) is not installed. Skipping" -ForegroundColor Red
    }
}
