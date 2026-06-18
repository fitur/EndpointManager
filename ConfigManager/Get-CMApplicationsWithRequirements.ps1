$Array = New-Object -TypeName System.Collections.ArrayList

foreach ($Application in (($Applications = Get-CMApplication) | ConvertTo-CMApplication)) {
    $Application.DeploymentTypes | Where-Object { $_.Requirements -ne $null } | ForEach-Object {
        [void]$Array.Add(
            [PSCustomObject]@{
                Application    = $Application.Title
                DeploymentType = $_.Title
                Requirement    = $_.Requirements
            }
        )
    }
}

$Array | Out-GridView
