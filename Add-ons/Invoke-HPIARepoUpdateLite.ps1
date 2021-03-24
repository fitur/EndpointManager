$RepoDir = "\\sccm07\sources\HPIA\RepoTest"
$Models = Import-Csv (Join-Path -Path ($RepoDir | Split-Path -Parent) -ChildPath "Models.csv")
$OSBuilds = Import-Csv (Join-Path -Path ($RepoDir | Split-Path -Parent) -ChildPath "OSBuilds.csv")
$Blacklist = Import-Csv (Join-Path -Path ($RepoDir | Split-Path -Parent) -ChildPath "Blacklist.csv")

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
            Remove-RepositoryFilter -Platform $Model.ProdCode -Yes
        } else {
            Write-Verbose -Verbose "Attempting to add $($Model.Model) to repository filter for OS-version $($_.OSBuild)."
            Add-RepositoryFilter -Platform $Model.ProdCode -Category Bios,Firmware,Driver,Software -Characteristic SSM -Os win10 -OsVer $($_.OSBuild) -ReleaseType Recommended -ErrorAction SilentlyContinue
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
