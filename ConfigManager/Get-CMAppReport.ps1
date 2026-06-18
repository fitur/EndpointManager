## Create app array
$CMApps = New-Object -TypeName System.Collections.ArrayList

## Get all CM applications
Get-CMApplication | ForEach-Object {
    ## Create app placeholder
    $TempCMAppInfo = [PSCustomObject]@{
        ApplicationLocalizedDisplayName = [string]$_.LocalizedDisplayName
        ApplicationPackageID = [string]$_.PackageID
        ApplicationNumberOfDevicesWithApp = [int]$_.NumberOfDevicesWithApp
        ApplicationNumberOfUsersWithApp = [int]$_.NumberOfUsersWithApp
        ApplicationNumberOfDevicesWithFailure = [int]$_.NumberOfDevicesWithFailure
        ApplicationNumberOfUsersWithFailure = [int]$_.NumberOfUsersWithFailure
        ApplicationIsDeployed = [bool]$_.IsDeployed
        ApplicationDateCreated = [datetime]$_.DateCreated
    }
    ## If deployed, get deployment info
    if ($_.IsDeployed -ne $false) {
        $TempCMDeploymentInfo = Get-CMDeployment -SoftwareName $_.LocalizedDisplayName | Select-Object -First 1
        $TempCMAppInfo | Add-Member -MemberType NoteProperty -Name DeploymentCollectionName -Value ([string]($TempCMDeploymentInfo | Select-Object -ExpandProperty CollectionName))
        $TempCMAppInfo | Add-Member -MemberType NoteProperty -Name DeploymentCollectionType -Value ([string]($TempCMDeploymentInfo | Select-Object -ExpandProperty CollectionType))
        $TempCMAppInfo | Add-Member -MemberType NoteProperty -Name DeploymentStartTime -Value ([string]($TempCMDeploymentInfo | Select-Object -ExpandProperty DeploymentTime))
        $TempCMAppInfo | Add-Member -MemberType NoteProperty -Name DeploymentEnabled -Value ([string]($TempCMDeploymentInfo | Select-Object -ExpandProperty Enabled))
        switch ($TempCMDeploymentInfo.DeploymentIntent) {
            1   {$TempCMAppInfo | Add-Member -MemberType NoteProperty -Name DeploymentIntent -Value ([string]"Required");break}
            2   {$TempCMAppInfo | Add-Member -MemberType NoteProperty -Name DeploymentIntent -Value ([string]"Available");break}
        }
    }

    ## Add to app array
    $CMApps.Add($TempCMAppInfo)
}
