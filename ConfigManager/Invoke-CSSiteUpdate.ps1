$Update = Get-CMSiteUpdate -Fast | Where-Object { ($_.State -ne "196612") -and ($_.state -ne "65538") -and ($_.DateReleased -le (Get-Date).AddDays(-31)) } | Select-Object Name,Description,FullVersion,DateReleased | Out-GridView -Title "Select Update" -OutputMode Single
Invoke-CMSiteUpdatePrerequisiteCheck -Name $Update.Name

Write-Host "Checking pre-reqs for $($Update.Name) ($($Update.FullVersion))." -ForegroundColor Green

$UpdateStatusCheckCount = 1
Do {
    $UpdateStatus = Get-CMSiteUpdate -Fast -Name $Update.Name
    Write-Host "$($UpdateStatus.LastUpdateTime) - $UpdateStatusCheckCount) Waiting 30 seconds for pre-req check to finish..."
    Wait-Event -Timeout 30
    $UpdateStatusCheckCount ++
} While ($UpdateStatus.State -eq "65538")

$UpdateSubStatus = Get-CMSiteUpdateInstallStatus -Name $Update.Name -Step Prerequisite -Complete
$FailedUpdateSubStatus = $UpdateSubStatus | Where-Object { ($_.Applicable -eq 1) -and ($_.IsComplete -eq 4) }

if ($null -eq $FailedUpdateSubStatus) {
    Install-CMSiteUpdate -Name $Update.Name -Force -Confirm
} else {
    Write-Host "Pre-req failed on $($FailedUpdateSubStatus.Count) occasions:" -ForegroundColor Red
    $FailedUpdateSubStatus | ForEach-Object {
        Write-Host " --- $($_.MessageTime) - $($_.SubStageName)"
    }
} 
