Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
$SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop

foreach ($Package in (Get-WmiObject -Namespace root/sms/site_$($SiteCode.SiteCode) -Class SMS_PackageStatusDistPointsSummarizer -ComputerName $SiteCode.SiteServer | Where-Object {($_.State -eq 2) -or ($_.State -eq 3)})) {
    $DP = Get-WmiObject -Namespace root/sms/site_$($SiteCode.SiteCode) -Class SMS_DistributionPoint -ComputerName $SiteCode.SiteServer | Where-Object {($_.PackageID -eq $Package.PackageID) -and ($_.ServerNALPath -eq $Package.ServerNALPath)}
    $DP.RefreshNow = $true
    $DP.Put()
}
