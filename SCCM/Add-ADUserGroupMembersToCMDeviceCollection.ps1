$URI = "http://sccm07.katalog.local/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "5b48f57b-0d36-43dd-a40b-8133a11a7d8d"
$WS = New-WebServiceProxy -Uri $URI
$CollectionID = "PS100466"
$ADGroup = "SF"

Get-ADGroupMember -Identity $ADGroup | ForEach-Object {
    Write-Host "Found $($_.name)"

    $CMComputers = Get-CMUserDeviceAffinity -UserName "KATALOG\$($_.Name)" | Where-Object {(($_.Sources -eq 4) -or ($_.Sources -eq 7)) -and ($_.Types -eq 1) -and ($_.UniqueUserName -match $_.Name)}
    Write-Host "$($_.name) has got $($CMComputers | Measure-Object | Select-Object -ExpandProperty Count) computer(s): $($CMComputers.ResourceName)"

    foreach ($CMComputer in $CMComputers) {
        $ws.AddCMComputerToCollection($SecretKey, $CMComputer.ResourceName, $CollectionID)
    }

    Remove-Variable CMComputer* -ErrorAction SilentlyContinue
    write-host "`n"
} 
