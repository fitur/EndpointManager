begin {
    try {
        # Load CM module
        Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    }
}
process {
    $UNC = Get-CMCollection -Id "SMS000US"
    $Updates = Get-CMSoftwareUpdate -IsDeployed $true -IsExpired $false -IsSuperseded $false -Fast | Where-Object {$_.LocalizedCategoryInstanceNames -notcontains "Upgrades"}

    # Create schedule (saturday = 6)
    $i = 0
    do {
        $i++
        $Schedule = [System.DateTime]::Today.AddDays($i)
    } until ((Get-Date).AddDays($i).DayOfWeek.value__ -eq 6) #(saturday = 6)

    # Gather OSD-images from all task sequences in production
    Get-CMTaskSequenceDeployment -CollectionId $UNC.CollectionID -Summary | ForEach-Object -Begin {$OSDImage = New-Object -TypeName System.Collections.ArrayList} -Process {
        Get-CMTaskSequenceStepApplyOperatingSystem -TaskSequenceId $_.PackageID | Select-Object -ExpandProperty ImagePackageID | ForEach-Object -Begin {$Temp = New-Object -TypeName System.Collections.ArrayList} -Process {
            $Temp.Add($_)
        }

        # Process only unique
        $Temp | Select-Object -Unique | ForEach-Object {
            $TempOSDImage = Get-CMOperatingSystemImage -Id $_ -ErrorAction SilentlyContinue
            if (![string]::IsNullOrWhiteSpace($TempOSDImage)) {
                $OSDImage.Add($TempOSDImage)
            }
        }
    }

    $OSDImage | ForEach-Object {
        switch -Wildcard ($_.ImageOSVersion) {
            "10.0.19041.*" { $OSDImageOSVersion = "20H2" }
            "10.0.18362.*" { $OSDImageOSVersion = "1909" }
            "10.0.17762.*" { $OSDImageOSVersion = "1809" }
        }

        # Inject all updates into 
        New-CMOperatingSystemImageUpdateSchedule -Id $_.PackageID -ContinueOnError $false -RemoveSupersededUpdates $true -SoftwareUpdate ($Updates | Where-Object {$_.LocalizedDisplayName -match $OSDImageOSVersion}) -UpdateDistributionPoint $true -RunNow
    }
} 
