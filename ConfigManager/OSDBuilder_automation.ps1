## Variables
$OSDBuilderPath = "D:\OSDBuilder"
$ISOPath = "D:\OSDBuilder\ISO"
$CMOSPath = "\\ne\system\SCCM\OS\OS Images\MS Client"
$CMTSPrefix = "NLTG - Pilot"

## Install, import and initalize module
try {
    if (!(Get-ChildItem -Path "$env:ProgramFiles\WindowsPowerShell\Modules\OSDBuilder")) {

        ## Install
        Install-Module -Name OSDBuilder -Force
    }

    ## Import module
    Import-Module -Name OSDBuilder -ErrorAction Stop
    Import-Module ($env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop

    ## Update
    #OSDBuilder -Update

    ## Setup
    Initialize-OSDBuilder -SetHome $OSDBuilderPath
    Get-OSDBuilder -SetHome $OSDBuilderPath -Initialize -CreatePaths -Download OneDrive
}
catch [System.Exception] {
    $_.ErrorDetails.Message
}

## Unmount all currently mounted ISOs
Get-Volume | Where-Object {($_.DriveType -eq "CD-ROM") -and ($_.OperationalStatus -eq "OK")} | ForEach-Object {
    Get-DiskImage -DevicePath ($_.Path).Substring(0, ($_.Path.Length - 1)) | Where-Object {$_.ImagePath -like "$ISOPath*"} | Dismount-DiskImage -Verbose
}

## Import OS from ISO if not already present
foreach ($OSImage in (Get-ChildItem -Path $ISOPath -Filter "*.ISO" -Recurse -File)) {
    ## Variables
    $OSImage.FullName -match "(?<version>2\dH(1|2))" | Out-Null
    $OSVersion = $Matches.version
    $TaskName = ("Windows 10 Enterprise x64 {0}" -f $OSVersion)

    ## Find imported OS media
    if (!(Get-OSMedia -OSReleaseId $OSVersion -Newest x64)) {

        ## Mount OS media if not already mounted
        if ((Get-DiskImage -ImagePath $OSImage.FullName).Attached -ne $true) {
            Mount-DiskImage -ImagePath $OSImage.FullName
        }

        ## Import OS media
        Import-OSMedia -EditionID Enterprise -SkipGrid -Update -BuildNetFX

        ## Dismount OS media
        Dismount-DiskImage -ImagePath $OSImage.FullName

        ## Download OS media optional updates
        Save-OSDBuilderDownload -UpdateOS 'Windows 10' -UpdateBuild $OSVersion -UpdateArch x64 -UpdateGroup Optional -Download -WebClient
        Save-OSDBuilderDownload -ContentDownload 'OneDriveSetup Production'

        ## Create OS build task
        Get-OSMedia -OSReleaseId $OSVersion -Newest x64 | New-OSBuildTask -TaskName $TaskName -EnableNetFx3
    }
}

## Process each OS media import
foreach ($OSMedia in (Get-OSMedia -Revision OK)) {

    ## Variables
    $OSVersion = $OSMedia.ReleaseId
    $TaskName = ("Windows 10 Enterprise x64 {0}" -f $OSMedia.ReleaseId)

    ## Download OS image updates
    $OSMedia | Update-OSMedia -Download -Execute #-SkipComponentCleanup

    ## Cleanup superseeded updates
    Get-DownOSDBuilder -Superseded Remove

    ## Build OS image
    New-OSBuild -ByTaskName $TaskName -Download -Execute #-SkipComponentCleanup

    ## Export and import to CM
    try {
        ## Get OS build
        $OSBuild = Get-OSBuilds -OSReleaseId $OSVersion -Revision OK -Newest x64

        ## Get WIM file from OS build
        $WIMFile = Get-Item -Path ("{0}\OS\sources\install.wim" -f $OSBuild.FullName)

        ## Copy WIM file to CMOSPath and rename file to TaskName
        Move-Item -Path $WIMFile -Destination $CMOSPath -Force -Verbose
        $NewName = Rename-Item -Path (Get-Item -Path ("{0}\{1}" -f $CMOSPath, $WIMFile.Name)) -NewName "$(("{0} {1} {2} {3} {4}" -f $OSBuild.ImageName, $OSBuild.Arch, $OSBuild.ReleaseId, $OSBuild.UBR, (Get-Random -Minimum 1000 -Maximum 9999)) -replace " ","_").wim" -Force -PassThru

        ## Call CM environment
        Set-location -Path $SiteCode":" -ErrorAction Stop

        ## Import OS image into CM
        $CMOSImage = New-CMOperatingSystemImage -Name ("{0} {1} {2}" -f $OSBuild.ImageName, $OSBuild.Arch, $OSBuild.ReleaseId) -Version $OSBuild.UBR -Description $OSBuild.ModifiedTime -Path $NewName -ErrorAction Stop -Verbose
        $CMOSImage | Start-CMContentDistribution -DistributionPointGroupName (Get-CMDistributionPointGroup | Sort-Object MemberCount -Descending | Select-Object -First 1 -ExpandProperty Name) -ErrorAction Stop -Verbose
        $CMOSImage | Move-CMObject -FolderPath '.\OperatingSystemImage\MS Client' -Verbose

        ## Remove old OS images from CM
        $OldCMOsImages = Get-CMOperatingSystemImage -Name ("{0} {1} {2}" -f $OSBuild.ImageName, $OSBuild.Arch, $OSBuild.ReleaseId)
        if ($OldCMOsImages.Count -gt 3) {
            $OldCMOsImages | Where-Object {$_.SourceDate -le (Get-Date).AddMonths(-3)} | ForEach-Object {
                $_ | Remove-CMOperatingSystemImage -Force
                Set-Location -Path $env:SystemDrive -ErrorAction Stop
                $_.PkgSourcePath | Remove-Item -Force
            }
        }

        ## Edit task sequence
        #Get-CMTaskSequence -Name ("{0} - {1} - {2}" -f $CMTSPrefix, $OSBuild.OperatingSystem, $OSVersion) -Fast -ErrorAction Stop | Set-CMTaskSequenceStepApplyOperatingSystem -ImagePackage $CMOSImage -ImagePackageIndex 1

        ## Exit CM environment
        Set-Location -Path $env:SystemDrive -ErrorAction Stop
    }
    catch [System.Exception] {
        $_.ErrorDetails.Message
    }
}
