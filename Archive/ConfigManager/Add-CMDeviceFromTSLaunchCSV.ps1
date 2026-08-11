$CSVFile = "C:\Users\petola001\Documents\1809 2020-06-18.csv"
$CollectionName = "$(($CSVFile | Split-Path -Leaf).Split(".")[0]) - $(Get-Date -Format g)"

if ($null -eq ($Collection = Get-CMDeviceCollection -Name $CollectionName -ErrorAction SilentlyContinue)) {
    $Collection = New-CMDeviceCollection -Name $CollectionName -LimitingCollectionId SMS00001 -RefreshType None -ErrorAction Stop
}

Import-Csv -Path $CSVFile -Delimiter "," | Where-Object {$_.ContentAvailable -ne "Success"} | ForEach-Object -Begin {$Computers = New-Object -TypeName System.Collections.ArrayList} -Process {
    [void]$Computers.Add($_)
}

$Computers | ForEach-Object {
    Write-Host "Adding $($_.MachineName) to $($Collection.CollectionID)"
    Add-CMDeviceCollectionDirectMembershipRule -CollectionId $Collection.CollectionID -ResourceId (Get-CMDevice -Name $_.MachineName).ResourceId
    Write-Host "`n"
} 
