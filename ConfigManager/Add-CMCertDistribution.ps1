$Programs = New-Object -TypeName System.Collections.ArrayList

Set-Location "$($SiteCode):"
#$CMPackage = Get-CMPackage -Id "P10002EC" -Fast
$CMPackage = New-CMPackage -Name "NLTG Retain 24 Certificate Distribution" -Path "\\ne.mytravelgroup.net\system\SCCM\Software\TCNE\Client Program\TCNE Import Certificate" -Version 1.1
$CMPackage | Start-CMContentDistribution -DistributionPointGroupName (Get-CMDistributionPointGroup | Sort-Object -Descending MemberCount | Select-Object -First 1 -ExpandProperty Name)

Set-Location $env:SystemDrive
Get-ChildItem -Path "\\ne.mytravelgroup.net\system\SCCM\Software\TCNE\Client Program\TCNE Import Certificate" -Filter *Administrator* | ForEach-Object {
    if ($_.Name -match "Spies") {
        $Password = "Dnhkdhtvh"
    } elseif ($_.Name -match "Tjäreborg") {
        $Password = "Suo5bj7"
    } elseif ($_.Name -match "Ving_NO") {
        $Password = "Nbgk6C"
    } elseif ($_.Name -match "Ving_SE") {
        $Password = "Vg5nFrt"
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