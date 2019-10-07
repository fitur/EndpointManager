Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') 
$SiteCode = Get-PSDrive -PSProvider CMSITE 
Set-location $SiteCode":" 

$ShortSiteServer = $SiteCode.SiteServer.Split(".")[0]
$Drivers = Get-CMDriver
$FaultyDrivers = New-Object -TypeName System.Collections.ArrayList

foreach ($Driver in $Drivers) {
    if (![System.IO.Directory]::Exists($($Driver.ContentSourcePath))) {
        if ($Remove = $true) {
            $Driver | Remove-CMDriver -Verbose -Force
        } else {
            $FaultyDrivers.Add($Driver.CI_ID) | Out-Null
        }
    }
}
