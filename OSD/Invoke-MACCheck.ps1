[CmdletBinding()]
param (
    [parameter(Mandatory = $true, HelpMessage = "URL to ConfigMgr webservice")]
    [ValidateNotNullOrEmpty()]
    $URI,
    [parameter(Mandatory = $true, HelpMessage = "ConfigMgr webservice secret key")]
    [ValidateNotNullOrEmpty()]
    $SecretKey
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
    try {
        # If MAC address doesn't exist in MDT DB
        if ([string]::IsNullOrEmpty($WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress))) {
            # Crash TS
            exit 1
        }
        # If multiple objects with same MAC address
        elseif (($WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress) | Measure-Object).Count -gt 1) {
            exit 1
        }
        # If response returns 5 digit name, proceed
        elseif ($WebService.GetMDTComputerByMacAddress($SecretKey, $MACAddress) -match "\d{5}") {
            exit 0
        }
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to establish a connection to ConfigMgr WebService. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"; exit 1
    }
}