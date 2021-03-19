$RepoDir = "\\sccm07\sources\HPIA\Repository"
$Models = Import-Csv (Join-Path -Path ($RepoDir | Split-Path -Parent) -ChildPath "Models.csv")

# Get Windows verison number sub directories and run per object
Get-ChildItem -Path $RepoDir -Name "10.0.*" | ForEach-Object {
    switch ($_) {
        "10.0.19042" { $HPIAOSNumber = "2009" }
        "10.0.17763" { $HPIAOSNumber = "1809" }
    }

    # Step into directory
    Set-Location -Path (Join-Path -Path $RepoDir -ChildPath $_) -ErrorAction Stop

    # Initialize repo
    Initialize-Repository -ErrorAction Stop

    # Add repository filter, run sync and clean repo for each model
    foreach ($Model in ($Models | Sort-Object -Unique ProdCode)) {
        Write-Verbose -Verbose "Attempting to synchronize $($Model.Model) for OS-version $HPIAOSNumber."
        Add-RepositoryFilter -Platform $Model.ProdCode -Category Bios,Firmware,Driver,Software -Characteristic SSM -Os win10 -OsVer $HPIAOSNumber -ReleaseType Recommended -ErrorAction SilentlyContinue
        Invoke-RepositorySync -Quiet -ErrorAction SilentlyContinue
        Invoke-RepositoryCleanup -ErrorAction SilentlyContinue
    }
}
