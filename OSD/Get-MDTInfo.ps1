$URI = "http://lolol.local/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "138be014-268a-4a15-ae06-4f39271bfbb8"
$MAC = "04:0E:3C:9D:3F:FB"

$WebService = New-WebServiceProxy -Uri $URI

$Computer = $WebService.GetMDTComputerByMacAddress($SecretKey,$MAC)
if (($Computer | Measure-Object).Count -eq 1) {
    $Name = $WebService.GetMDTComputerNameByIdentity($SecretKey,$Computer)
    $Role = $WebService.GetMDTDetailedComputerRoleMembership($SecretKey,$Computer) | Where-Object {$_.RoleID -ne 2}
    $User = $WebService.GetADComputerAttributeValue($SecretKey,$Name,"ManagedBy")
    $Domain = ($WebService.GetADDomain($SecretKey)).DomainName.Split(".")[0]
}



if ($User -match "(?<name>[a-z]{3,6}[0-9]{3}){1}") {
    $Combination = "{0}\{1}" -f $Domain, $Matches.name
}
