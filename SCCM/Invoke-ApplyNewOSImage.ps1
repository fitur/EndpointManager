$AUC = Get-CMCollection -Id SMS000US
$AUCDeployments = Get-CMDeployment -CollectionName $AUC.Name
Write-Host "Found $($AUCDeployments | Measure-Object | Select-Object -ExpandProperty Count) task sequence(s)"

foreach ($AUCDeployment in $AUCDeployments) {
    $TS = Get-CMTaskSequence -TaskSequencePackageId $AUCDeployment.PackageID
    $TSOSStep = $TS | Get-CMTaskSequenceStepApplyOperatingSystem
    $CurrentOSImage = Get-CMOperatingSystemImage -Id ($TSOSStep.ImagePackageID)
    $NewOSImage = Get-CMOperatingSystemImage | Where-Object { (([system.version]$_.ImageOSVersion).Build -eq ([system.version]$CurrentOSImage.ImageOSVersion).Build) -and (([system.version]$_.ImageOSVersion).Revision -gt ([system.version]$CurrentOSImage.ImageOSVersion).Revision) -and ($_.Name -notmatch "pilot") -and ($_.Name -notmatch "test") } | Sort-Object SourceDate -Descending | Select-Object -First 1
    if ($null -ne $NewOSImage) {
        Write-Host " ----- $($TS.Name): Swapping OS image $($CurrentOSImage.PackageID), version $($CurrentOSImage.ImageOSVersion) with $($NewOSImage.PackageID), version $($NewOSImage.ImageOSVersion)."
        Set-CMTaskSequenceStepApplyOperatingSystem -TaskSequenceId $TS.PackageID -ImagePackage $NewOSImage -ImagePackageIndex ([xml]$NewOSImage.ImageProperty).WIM.IMAGE.index
    } else {
        write-host " ----- $($TS.Name): Current OS image $($CurrentOSImage.PackageID), version $($CurrentOSImage.ImageOSVersion) is up to date. No changes made."
    }
}

Write-Host "Finished!" 
