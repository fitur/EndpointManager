$TaskSequencePrefix = "Pilot"
$OSImages = Get-CMTaskSequence -Fast | Where-Object {($_.Name -match $TaskSequencePrefix) -and ($_.Name -match "Windows") -and ($_.TsEnabled -eq $true) -and ($_.BootImageID)} | Get-CMTaskSequenceStepApplyOperatingSystem

$OSImages | ForEach-Object {
    $TempCMOSImage = Get-CMOperatingSystemImage -Id $_.ImagePackageID

    # Temporarily move out of CM
    Set-Location $env:SystemDrive
    $OSImageISO = Get-Item $TempCMOSImage.PkgSourcePath
    $OSImageISOBackupFullPath = Join-Path -Path $OSImageISO.Directory.FullName -ChildPath ("{0}-{1}.wim" -f ($OSImageISO.BaseName), (Get-Date -Format yyyyMMdd))
    Copy-Item -Path $OSImageISO.FullName -Destination $OSImageISOBackupFullPath -Force
    Set-Location $SiteCode":"

    $NewCMOsImage = New-CMOperatingSystemImage -Name ("{0} - {1}" -f $TempCMOSImage.Name, (Get-Date -Format yyyyMMdd)) -Path $OSImageISOBackupFullPath -Version $TempCMOSImage.ImageOSVersion -Description "Backup - $(Get-Date -Format yyyyMMdd)"
    $NewCMOsImage | Start-CMContentDistribution -DistributionPointGroupName (Get-CMDistributionPointGroup | Sort-Object MemberCount -Descending | Select-Object -First 1).Name
    $SoftwareUpdates = Get-CMSoftwareUpdate -IsSuperseded $false -IsExpired $false -Fast | Where-Object {($_.LocalizedDisplayName -match $TempCMOSImage.Version) -and ($_.DateRevised -ge (Get-Date).AddDays(-31))}
    $TempCMOSImage | New-CMOperatingSystemImageUpdateSchedule -ContinueOnError $true -RemoveSupersededUpdates $true -SoftwareUpdate $SoftwareUpdates -RunNow
}
