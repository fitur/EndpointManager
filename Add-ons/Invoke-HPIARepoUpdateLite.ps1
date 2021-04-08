begin {
    $HPIADir = "\\dp4.edu.timra.se\HPIA$"
    $RepoDir = Join-Path -Path $HPIADir -ChildPath "Repository"
    $BinaryDir = Join-Path -Path $HPIADir -ChildPath "Binary"
    $ModuleDir = Join-Path -Path $HPIADir -ChildPath "Modules"
    $CVAPath = Join-Path -Path $HPIADir -ChildPath "CVA.txt"
    $Models = Import-Csv (Join-Path -Path $HPIADir -ChildPath "Models.csv")
    $OSBuilds = Import-Csv (Join-Path -Path $HPIADir -ChildPath "OSBuilds.csv")
    $Blacklist = Import-Csv (Join-Path -Path $HPIADir -ChildPath "Blacklist.csv")

    # Import HP modules
    if ($null -eq (Get-Command -Name Get-RepositoryInfo*)) {
        try {
            Import-Module $ModuleDir\HP.Sinks\HP.Sinks.psm1
            Import-Module $ModuleDir\HP.Utility\HP.Utility.psm1
            Import-Module $ModuleDir\HP.Firmware\HP.Firmware.psm1
            Import-Module $ModuleDir\HP.Softpaq\HP.Softpaq.psm1
            Import-Module $ModuleDir\HP.Private\HP.Private.psm1
            Import-Module $ModuleDir\HP.Repo\HP.Repo.psm1
            Import-Module $ModuleDir\HP.ClientManagement\HP.ClientManagement.psm1
        }
        catch [System.SystemException] {
            Write-Verbose -Verbose "Couldn't load HP script library modules"
        }
    }
}
process {
    # Step into directory
    Set-Location -Path $RepoDir -ErrorAction Stop

    # Initialize repo
    Initialize-Repository -Verbose -ErrorAction Stop
    Set-RepositoryConfiguration -Setting OnRemoteFileNotFound -Value LogAndContinue -Verbose
    Set-RepositoryConfiguration -Setting OfflineCacheMode -CacheValue Enable -Verbose

    # Get Windows verison number sub directories and run per object
    $OSBuilds | ForEach-Object {
        # Add repository filter, run sync and clean repo for each model
        foreach ($Model in ($Models | Sort-Object -Unique ProdCode | Where-Object {$_.Model -match "HP"})) {
            $TempBlacklist = $Blacklist | Where-Object {$_.ProdCode -eq $Model.ProdCode}
            if ($_.OSBuild -in $TempBlacklist.OS) {
                Write-Verbose -Verbose "$($Model.Model) blacklisted for this OS-version. Attempting to remove from repository filter for OS-version $($_.OSBuild)."
                Remove-RepositoryFilter -Platform $Model.ProdCode -OsVer $_.OSBuild -Yes
            } else {
                if ($_.OSBuild -in (Get-HPDeviceDetails -Platform $Model.ProdCode -OSList | Select-Object -ExpandProperty OperatingSystemRelease)) {
                    Write-Verbose -Verbose "Attempting to add $($Model.Model) to repository filter for OS-version $($_.OSBuild)."
                    Add-RepositoryFilter -Platform $Model.ProdCode -Category Bios,Firmware,Driver,Software -Characteristic SSM -Os win10 -OsVer $_.OSBuild -ReleaseType * -ErrorAction SilentlyContinue
                } else {
                    Write-Verbose -Verbose "$($Model.Model) is not available for this OS-version. Attempting to remove from repository filter for OS-version $($_.OSBuild)."
                    Remove-RepositoryFilter -Platform $Model.ProdCode -OsVer $_.OSBuild -Yes
                }
            }

            Remove-Variable TempBlacklist -ErrorAction SilentlyContinue
        }

        # Remove all unsupported OS builds
        Get-RepositoryInfo | Select-Object -ExpandProperty Filters | Where-Object {($_.operatingSystem).split(":")[1] -notin $OSBuilds.OSBuild} | ForEach-Object {
            Write-Verbose -Verbose "Removing obsolete OS build $(($_.operatingSystem).split(":")[1]) for platform $($_.platform)"
            Remove-RepositoryFilter -Platform $_.platform -Os win10 -OsVer ([int](($_.operatingSystem).split(":")[1])) -Yes
        }
    }

    # Run sync and cleanup
    Invoke-RepositorySync
    Invoke-RepositoryCleanup
} 
