$TSApps = @()
Get-CMTaskSequenceStepInstallApplication -TaskSequenceId PS100157 | Where-Object {$_.Properties.AppInfo.DisplayName -notlike ""} | ForEach-Object {$TSApps += $_.Properties.AppInfo.DisplayName}
$TSSteps = Get-CMTaskSequenceStep -TaskSequenceId PS100157 | Where-Object { ($_.SmsProviderObjectPath -eq "SMS_TaskSequence_InstallSoftwareAction") -or ($_.SmsProviderObjectPath -eq "SMS_TaskSequence_InstallApplicationAction") } | Select-Object *
