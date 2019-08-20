$TSApps = @()

Get-CMTaskSequenceStepInstallApplication -TaskSequenceId PS100157 | Where-Object {$_.Properties.AppInfo.DisplayName -notlike ""} | ForEach-Object {$TSApps += $_.Properties.AppInfo.DisplayName}
Get-CMTaskSequenceStepInstallSoftware -TaskSequenceId PS100157 | Where-Object {$_.PackageID -match $SiteCode} | ForEach-Object {$TSApps += (Get-CMPackage -Id $_.PackageID | Select-Object -ExpandProperty Name)}

$TSApps | Select-Object -Unique | Out-GridView
