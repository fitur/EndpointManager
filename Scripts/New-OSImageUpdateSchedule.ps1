#
# Press 'F5' to run this script. Running this script will load the ConfigurationManager
# module for Windows PowerShell and will connect to the site.
#
# This script was auto-generated at '2018-11-20 10:02:57'.

# Uncomment the line below if running in an environment where script signing is 
# required.
#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Site configuration
$SiteCode = "C01" # Site code 
$ProviderMachineName = "SESCCMSRV04.tobii.intra" # SMS Provider machine name

# Customizations
$initParams = @{}
#$initParams.Add("Verbose", $true) # Uncomment this line to enable verbose logging
#$initParams.Add("ErrorAction", "Stop") # Uncomment this line to stop the script on any errors

# Do not change anything below this line

# Import the ConfigurationManager.psd1 module 
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}

# Connect to the site's drive if it is not already present
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}

# Set the current location to be the site code.
Set-Location "$($SiteCode):\" @initParams


$Splat = @{
    "ErrorAction" = "Stop"
    "Verbose" = $true ## set to true if you need output
}

$i = 0
do {
    $i++
    $Schedule = [System.DateTime]::Today.AddDays($i)
} until ((Get-Date).AddDays($i).DayOfWeek.value__ -eq 6)

$SoftwareUpdates = Get-CMSoftwareUpdateGroup -Name ("ADR*{0}*" -f (Get-Date -UFormat "%Y-%m")) @Splat | ForEach-Object {
    Get-CMSoftwareUpdate -UpdateGroupId $_.CI_ID -Fast @Splat
}

Get-CMOperatingSystemImage | Sort-Object -Descending Version @Splat | ForEach-Object {
    $_ | New-CMOperatingSystemImageUpdateSchedule -SoftwareUpdate $SoftwareUpdates -CustomSchedule $Schedule -ContinueOnError $true -UpdateDistributionPoint $true @Splat
}
