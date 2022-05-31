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
        $TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment -ErrorAction Continue
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
    # If response returns between 2 and 5 digit ID, proceed
    if (($Computer = $WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress)) -match "\d{2,5}") {
        # Gather object attributes
        try {
            $Name = $WebService.GetMDTComputerNameByIdentity($SecretKey, $Computer)
            $Role = $WebService.GetADComputerAttributeValue($SecretKey, $Name, "type")
            $User = $WebService.GetADComputerAttributeValue($SecretKey, $Name, "ManagedBy")
            $Domain = ($WebService.GetADDomain($SecretKey)).DomainName.Split(".")[0]
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to fetch mandatory attribute. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
        }

        # If user attribute match regex, proceed
        if ($User -match "(?<name>[a-z]{3,6}[0-9]{3}){1}") {
            try {
                $TSEnvironment.Value("SMSTSUDAUsers") = ("{0}\{1}" -f $Domain, $Matches.name)
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to set TS environment variable (SMSTSUDAUsers). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
            }
        }
        
        # Set TS variable if role attribute exist
        if (![string]::IsNullOrEmpty($Role)) {
            try {
                switch ($Role) {
                    "Administrative" { $TSEnvironment.Value("Solnarole") = "Role_ADM" }
                    "Educational" { $TSEnvironment.Value("Solnarole") = "Role_EDU" }
                    "Public" { $TSEnvironment.Value("Solnarole") = "Role_Publik" }
                }
            }
            catch [System.Exception] {
                Write-Warning -Message "Unable to set TS environment variable (Solnarole). Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
            }
        }
        else {
            Write-Warning -Message "Unable to find an associated attribute (Solnarole). Terminating OS deployment."; exit 1
        }
    }
    else {
        Write-Warning -Message "Unable to find an associated MDT object."; exit 1
    }
}
