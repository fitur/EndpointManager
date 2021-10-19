 ## Variables
$OSDBuilderPath = "D:\Scripts and Tools\OSDBuilder"
$ISOPath = "D:\Scripts and Tools\ISO"
$CMOSPath = "\\ne\system\SCCM\OS\OS Images\MS Client"

## Install, import and initalize module
try {
    if (!(Get-ChildItem -Path "$env:ProgramFiles\WindowsPowerShell\Modules\OSDBuilder")) {

        ## Install
        Install-Module -Name OSDBuilder -Force
    }

    ## Import module
    Import-Module -Name OSDBuilder
    Import-module ($env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1')

    ## Setup
    Initialize-OSDBuilder
    Get-OSDBuilder -SetHome $OSDBuilderPath -Initialize -CreatePaths -Download OneDrive
}
catch [System.Exception] {
    $_.ErrorDetails.Message
}

## Unmount all currently mounted ISOs
Get-Volume | Where-Object {($_.DriveType -eq "CD-ROM") -and ($_.OperationalStatus -eq "OK")} | ForEach-Object {
    Get-DiskImage -DevicePath ($_.Path).Substring(0, ($_.Path.Length - 1)) | Where-Object {$_.ImagePath -like "$ISOPath*"} | Dismount-DiskImage
}

## Process each ISO
Get-ChildItem -Path $ISOPath -Filter "*6.ISO" -Recurse -File | ForEach-Object {
    ## Variables
    $_.FullName -match "(?<version>2\dH(1|2))" | Out-Null
    $OSVersion = $Matches.version
    $TaskName = ("Windows 10 Enterprise x64 {0}" -f $OSVersion)
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop

    ## Find imported OS media
    if (!(Get-OSMedia -OSReleaseId $OSVersion)) {

        ## Mount OS media if not already mounted
        if ((Get-DiskImage -ImagePath $_.FullName).Attached -ne $true) {
            Mount-DiskImage -ImagePath $_.FullName
        }

        ## Import OS media
        Import-OSMedia -Update -BuildNetFX -EditionID Enterprise -SkipGrid

        ## Dismount OS media
        Dismount-DiskImage -ImagePath $_.FullName

        ## Update OS media
        #$OSMedia | Update-OSMedia -Download -Execute -SkipComponentCleanup # Performed in import
        Save-OSDBuilderDownload -UpdateOS 'Windows 10' -UpdateBuild $OSVersion -UpdateArch x64 -UpdateGroup Optional -Download

        ## Create OS build task
        Get-OSMedia -OSReleaseId $OSVersion -Newest | New-OSBuildTask -TaskName $TaskName -EnableNetFx3
    } else {

        ## Update OS media if already exist
        Get-OSMedia -OSReleaseId $OSVersion -Newest | Update-OSMedia -Download -Execute -SkipComponentCleanup
    }

    ## Build OS image
    New-OSBuild -ByTaskName $TaskName -Execute -SkipComponentCleanup -Download

    ## Export and import to CM
    try {
        ## Get OS build
        $OSBuild = Get-OSBuilds -OSReleaseId $OSVersion -Revision OK -Newest x64

        ## Get WIM file from OS build
        $WIMFile = Get-Item -Path ("{0}\OS\sources\install.wim" -f $OSBuild.FullName)

        ## Copy WIM file to CMOSPath and rename file to TaskName
        Copy-Item -Path $WIMFile -Destination $CMOSPath -Force
        $NewName = Rename-Item -Path (Get-Item -Path ("{0}\{1}" -f $CMOSPath, $WIMFile.Name)) -NewName "$(("{0} {1} {2} {3} {4}" -f $OSBuild.ImageName, $OSBuild.Arch, $OSBuild.ReleaseId, $OSBuild.UBR, (Get-Random -Minimum 1000 -Maximum 9999)) -replace " ","_").wim" -Force -PassThru

        ## Call CM environment
        Set-location -Path $SiteCode":" -ErrorAction Stop

        ## Import OS image into CM
        $CMOSImage = New-CMOperatingSystemImage -Name ("{0} {1} {2}" -f $OSBuild.ImageName, $OSBuild.Arch, $OSBuild.ReleaseId) -Version $OSBuild.UBR -Description $OSBuild.ModifiedTime -Path $NewName -ErrorAction Stop
        $CMOSImage | Start-CMContentDistribution -DistributionPointGroupName (Get-CMDistributionPointGroup | Sort-Object MemberCount -Descending | Select-Object -First 1 -ExpandProperty Name) -ErrorAction Stop

        ## Exit CM environment
        Set-Location -Path $env:SystemDrive -ErrorAction Stop
    }
    catch [System.Exception] {
        $_.ErrorDetails.Message
    }
}
 
