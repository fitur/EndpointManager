#Please load CM module
$CollID = "PS10048D"
$LimCollID = "PS10045B"
$ExcCollID = "PS100481"
$Collection = Get-CMCollection -Id $CollID -Verbose
$LimCollection = Get-CMDevice -CollectionId $LimCollID -Fast -Verbose | Where-Object {$_.LastActiveTime -gt (Get-Date).AddDays(-7)}
$ExcCollection = Get-CMDevice -CollectionId $ExcCollID -Fast -Verbose
$LimCollection | Get-Random -Count 200 | ForEach-Object {
    Write-Host "Adding $($_.Name) to $($Collection.Name)"
    Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollID -ResourceId $_.ResourceID
} 
