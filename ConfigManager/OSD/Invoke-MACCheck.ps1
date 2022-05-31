[CmdletBinding()]
param (
    [parameter(Mandatory = $true, HelpMessage = "URL to ConfigMgr webservice")]
    [ValidateNotNullOrEmpty()]
    $URI,
    [parameter(Mandatory = $true, HelpMessage = "ConfigMgr webservice secret key")]
    [ValidateNotNullOrEmpty()]
    $SecretKey,
    [parameter(Mandatory = $false, HelpMessage = "MAC address")]
    [ValidateNotNullOrEmpty()]
    $MACAddress = (Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $null -ne $_.IPAddress } | Select-Object -ExpandProperty MacAddress)
)
begin {
    # Load CM environment
    try {
        $TSProgressUI = New-Object -ComObject Microsoft.SMS.TsProgressUI -ErrorAction Continue
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to construct Microsoft.SMS.TSEnvironment object. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
    }

    # Construct new web service proxy
    try {
        $WebService = New-WebServiceProxy -Uri $URI -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to establish a connection to ConfigMgr WebService. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
    }
}
process {
    try {
        # If response returns 5 digit name, proceed
        if ($WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress) -match "\d{5}") {
            exit 0
        }
        # If MAC address doesn't exist in MDT DB
        elseif ([string]::IsNullOrEmpty($WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress))) {
            # Hide progress UI, show dialog and terminate TS
            $TSProgressUI.CloseProgressDialog()
            $TSProgressUI.ShowMessage("Kunde inte hitta MAC-adress i MDT-databasen. `nÄr datorn registrerad i IM? `n`nInstallationen avslutas och datorn stängs av.","Fel i task squence",0)
            Start-Process -FilePath wpeutil -ArgumentList 'shutdown' -WindowStyle Hidden
            #exit 1
        }
        # If multiple objects with same MAC address
        elseif (($WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress) | Measure-Object).Count -gt 1) {
            # Hide progress UI, show dialog and terminate TS
            $TSProgressUI.CloseProgressDialog()
            $TSProgressUI.ShowMessage("Hittade flera identiska MAC-adresser i MDT-databasen. `nKontakta Advania för rensning av MDT-objekt. `n`nInstallationen avslutas och datorn stängs av.","Fel i task squence",0)
            Start-Process -FilePath wpeutil -ArgumentList 'shutdown' -WindowStyle Hidden
            #exit 1
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to establish a connection to ConfigMgr WebService. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
    }
}