begin {
    try {
        # Load CM module
        Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
    }

    # Fetch variables
    $Domain = Get-WmiObject -Class Win32_ComputerSystem | Select-Object -ExpandProperty Domain
    $Server = "{0}.{1}" -f $SiteCode.SiteServer, $Domain
    $ConfigMgrwebServicePath = Invoke-Command -ComputerName $Server -ScriptBlock {Get-WebApplication | Where-Object {$_.applicationPool -match "ConfigMgrWebService"} | Select-Object -ExpandProperty path}
    $URI = "http://{0}{1}/{2}" -f $Server, $ConfigMgrwebServicePath, "ConfigMgr.asmx"
}
process {
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
} 
