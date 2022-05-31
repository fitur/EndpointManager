$URI = "http://sccm07.katalog.local/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "5b48f57b-0d36-43dd-a40b-8133a11a7d8d"
$MAC = "04:0E:3C:9D:3F:FB"
$MAC3 = "04:0E:3C:9D:3F:FA"
$MAC1 = "04:0E:3C:9D:3F:FC"
$MACAddress = "C4:65:16:05:E6:87"

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