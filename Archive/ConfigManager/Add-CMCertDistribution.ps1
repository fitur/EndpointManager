$Programs = New-Object -TypeName System.Collections.ArrayList

Set-Location "$($SiteCode):"
#$CMPackage = Get-CMPackage -Id "P10002EC" -Fast
$CMPackage = New-CMPackage -Name "NLTG Retain 24 Certificate Distribution" -Path "\\<file-server-fqdn>\system\SCCM\Software\TCNE\Client Program\TCNE Import Certificate" -Version 1.1
$CMPackage | Start-CMContentDistribution -DistributionPointGroupName (Get-CMDistributionPointGroup | Sort-Object -Descending MemberCount | Select-Object -First 1 -ExpandProperty Name)

Set-Location $env:SystemDrive
Get-ChildItem -Path "\\<file-server-fqdn>\system\SCCM\Software\TCNE\Client Program\TCNE Import Certificate" -Filter *Administrator* | ForEach-Object {
    # PFX import passwords must NOT be hardcoded. Look them up at runtime from a
    # secure store (e.g. a credential manager, Key Vault, or an encrypted file
    # that is excluded from source control). The hashtable below is a placeholder.
    $PfxPasswords = $env:PFX_PASSWORDS_JSON | ConvertFrom-Json   # e.g. {"Spies":"...","Tjareborg":"...","Ving_NO":"...","Ving_SE":"..."}
    if ($_.Name -match "Spies") {
        $Password = $PfxPasswords.Spies
    } elseif ($_.Name -match "Tjäreborg") {
        $Password = $PfxPasswords.Tjareborg
    } elseif ($_.Name -match "Ving_NO") {
        $Password = $PfxPasswords.Ving_NO
    } elseif ($_.Name -match "Ving_SE") {
        $Password = $PfxPasswords.Ving_SE
    }
    Set-Location "$($SiteCode):"
    $CommandLine = $("certutil -importpfx -user -p {0} {1}" -f $Password, $_.Name)
    $ProgramName = $($_.Name -replace "_"," " -replace ".pfx","")
    $Program = New-CMProgram -PackageName $CMPackage.Name -CommandLine $CommandLine -StandardProgramName $ProgramName -ProgramRunType OnlyWhenUserIsLoggedOn -RunMode RunWithUserRights -RunType Hidden
    if ($Collection = Get-CMCollection -Name "TCNE*$($_.Name)") {
        New-CMPackageDeployment -PackageId $CMPackage.PackageID -ProgramName $Program.ProgramName -StandardProgram -CollectionId $Collection.CollectionID -ScheduleEvent AsSoonAsPossible -FastNetworkOption DownloadContentFromDistributionPointAndRunLocally -SlowNetworkOption DownloadContentFromDistributionPointAndLocally -DeployPurpose Available
    } else {
        $Collection = New-CMCollection -CollectionType User -Name ("TCNE Import Certificates {0}" -f $_.Name) -LimitingCollection (Get-CMCollection -Id "SMS00002")
        New-CMPackageDeployment -PackageId $CMPackage.PackageID -ProgramName $Program.ProgramName -StandardProgram -CollectionId $Collection.CollectionID -ScheduleEvent AsSoonAsPossible -FastNetworkOption DownloadContentFromDistributionPointAndRunLocally -SlowNetworkOption DownloadContentFromDistributionPointAndLocally -DeployPurpose Available
    }
}