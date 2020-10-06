 $IPUTS = Get-CMTaskSequence -TaskSequencePackageId PS100223
$IPUPCTS = Get-CMTaskSequence -TaskSequencePackageId PS1002EB

$CollectionPrefix = "Windows 10 - 1809 - Batch"
$DPGName = "All DPs"
$TSLaunchSourcePath = "\\sccm07\sources\OSD\Scripts and Tools\TSLaunch\TSLaunch - 1809 - Source"
$TSLaunchDestinationPrefix = "\\sccm07\sources\OSD\Scripts and Tools\TSLaunch\TSLaunch - 1809"


foreach ($Collection in (Get-CMCollection -Name "$CollectionPrefix*")) {
    if ($null -eq (Get-CMDeployment -CollectionName $Collection.Name | Where-Object {$_.SoftwareName -match $IPUTS.Name})) {
        Write-Host "Working with $($Collection.Name)"
        $Date = $Collection.Comment
        $TSDep = New-CMTaskSequenceDeployment -TaskSequencePackageId $IPUTS.PackageID -AvailableDateTime (Get-Date $Date) -Schedule (New-CMSchedule -Nonrecurring -Start (Get-Date $Date).AddYears(10).Date) -DeployPurpose Required -RerunBehavior AlwaysRerunProgram -ShowTaskSequenceProgress $false -Availability Clients -RunFromSoftwareCenter $false -SystemRestart $true -SoftwareInstallation $true -DeploymentOption DownloadAllContentLocallyBeforeStartingTaskSequence -CollectionId $Collection.CollectionID -InternetOption $true -UseMeteredNetwork $true -AllowSharedContent $true -AllowFallback $true -ErrorAction Stop
        $TSPCDep = New-CMTaskSequenceDeployment -TaskSequencePackageId $IPUPCTS.PackageID -AvailableDateTime (Get-Date $Date).AddMinutes(-30) -Schedule (New-CMSchedule -Nonrecurring -Start (Get-Date $Date).AddMinutes(-30)) -DeployPurpose Required -RerunBehavior AlwaysRerunProgram -ShowTaskSequenceProgress $false -Availability Clients -RunFromSoftwareCenter $true -SystemRestart $true -SoftwareInstallation $true -DeploymentOption DownloadContentLocallyWhenNeededByRunningTaskSequence -CollectionId $Collection.CollectionID -InternetOption $true -UseMeteredNetwork $true -AllowSharedContent $true -AllowFallback $true -ErrorAction Stop

        $TSLaunchContentPath = "$TSLaunchDestinationPrefix - Batch $(($Collection.Name).Substring($Collection.Name.Length-1,1))"
        $TSLaunchConfigPath = "{0}\{1}" -f $TSLaunchContentPath, "TSLaunch.exe.config"

        $Path = (Get-Location).Path
        Set-Location $env:SystemDrive
        Copy-Item -Path $TSLaunchSourcePath -Destination $TSLaunchContentPath -Recurse
        New-Item -Name "$(($Collection.Name).Substring($Collection.Name.Length-1,1)).txt" -ItemType File -Path $TSLaunchContentPath -Force
        Set-Location $Path

        $ConfigXML = New-Object -TypeName XML
        $ConfigXML.Load($TSLaunchConfigPath)
        $ConfigXML.configuration.appSettings.add[0].value = $TSDep.AdvertisementID
        $ConfigXML.configuration.appSettings.add[1].value = $IPUTS | Get-CMTaskSequenceStepUpgradeOperatingSystem | Where-Object {$_.ScanOnly -eq $false} | Select-Object -ExpandProperty InstallPackageID
        $ConfigXML.Save($TSLaunchConfigPath)
        
        $Package = New-CMPackage -Name ("TSLaunch - {0}" -f $Collection.Name) -Manufacturer "Advania" -Path $TSLaunchContentPath -ErrorAction Stop
        Start-CMContentDistribution -PackageId $Package.PackageID -DistributionPointGroupName $DPGName -ErrorAction Stop
        Move-CMObject -InputObject $Package -FolderPath "Package\OS Servicing\TSLaunch" -ErrorAction Stop
        $Program = New-CMProgram -PackageId $Package.PackageID -StandardProgramName "TSLaunch" -CommandLine "TSLaunch.exe" -ProgramRunType WhetherOrNotUserIsLoggedOn -RunType Hidden -RunMode RunWithAdministrativeRight -ErrorAction Stop
        $ProgramDep = New-CMPackageDeployment -PackageId $Package.PackageID -ProgramName TSLaunch -StandardProgram -CollectionId $Collection.CollectionID -DeployPurpose Required -RerunBehavior AlwaysRerunProgram -AvailableDateTime (Get-Date $Date) -Schedule (New-CMSchedule -Nonrecurring -Start (Get-Date $Date)) -SoftwareInstallation $true -SystemRestart $true -AllowSharedContent $true -AllowFallback $true -SlowNetworkOption DownloadContentFromDistributionPointAndLocally -FastNetworkOption DownloadContentFromDistributionPointAndRunLocally -UseMeteredNetwork $true -ErrorAction Stop
    }
} 
