# Replace with your own ConfigMgr WebService URL and secret key.
# Supply the secret key via an environment variable rather than hardcoding it.
$URI = "http://<configmgr-webservice-host>/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = $env:CMWEBSERVICE_SECRETKEY
$MAC = "00:00:00:00:00:00"
$MAC3 = "00:00:00:00:00:00"
$MAC1 = "00:00:00:00:00:00"
$MACAddress = "00:00:00:00:00:00"

$WebService = New-WebServiceProxy -Uri $URI -ErrorAction SilentlyContinue
$TSEnvironment = New-Object -ComObject Microsoft.SMS.TSEnvironment

$Computer = $WebService.GetMDTComputerByMacAddress($SecretKey,$MAC)
if (($Computer | Measure-Object).Count -eq 1) {
    $Name = $WebService.GetMDTComputerNameByIdentity($SecretKey,$Computer)
    $Role = $WebService.GetADComputerAttributeValue($SecretKey,$Name,"type")
    $User = $WebService.GetADComputerAttributeValue($SecretKey,$Name,"ManagedBy")
    $Domain = ($WebService.GetADDomain($SecretKey)).DomainName.Split(".")[0]
}


if ($User -match "(?<name>[a-z]{3,6}[0-9]{3}){1}") {
    $NameCombination = "{0}\{1}" -f $Domain, $Matches.name
    $TSEnvironment.Value("SMSTSUDAUsers") = $NameCombination
}

switch ($Role.RoleName) {
    "Administrative" { $TSEnvironment.Value("Solnarole") = "Role_ADM" }
    "Educational" { $TSEnvironment.Value("Solnarole") = "Role_EDU" }
    "Public" { $TSEnvironment.Value("Solnarole") = "Role_Publik" }
}