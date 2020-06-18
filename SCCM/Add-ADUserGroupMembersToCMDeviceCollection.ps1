$URI = "http://*/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "*"
$WS = New-WebServiceProxy -Uri $URI
$CollectionID = "*"
$ADGroup = "*"

Get-ADGroupMember -Identity $ADGroup | ForEach-Object {
    Write-Host "Found $($_.name)"

    $CMComputers = Get-CMUserDeviceAffinity -UserName "KATALOG\$($_.Name)" | Where-Object {($_.Sources -eq 4) -and ($_.Types -eq 1) -and ($_.UniqueUserName -match $_.Name)}
    Write-Host "$($_.name) has got $($CMComputers | Measure-Object | Select-Object -ExpandProperty Count) computer(s): $($CMComputers.ResourceName)"

    foreach ($CMComputer in $CMComputers) {
        $ws.AddCMComputerToCollection($SecretKey, $CMComputer.ResourceName, $CollectionID)
    }

    Remove-Variable CMComputer* -ErrorAction SilentlyContinue
    write-host "`n"
} 
