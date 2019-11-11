$URI = "http://lolol.local/ConfigMgrWebService/ConfigMgr.asmx"
$SecretKey = "138be014-268a-4a15-ae06-4f39271bfbb8"

$WebService = New-WebServiceProxy -Uri $URI

$Computer = $WebService.GetMDTComputerByName($SecretKey,"WS07768")
if (($Computer | Measure-Object).Count -eq 1) {
    $Name = $Computer.ComputerName
    $Roles = $WebService.GetMDTDetailedComputerRoleMembership($SecretKey,$($Computer.ComputerIdentity))
    $User = $WebService.GetADComputerAttributeValue($SecretKey,"WS07768","ManagedBy")
    $Domain = ($WebService.GetADDomain($SecretKey)).DomainName.Split(".")[0]
}



if ($User -match "(?<name>[a-z]{3,6}[0-9]{3}){1}") {
    $Combination = "{0}\{1}" -f $Domain, $Matches.name
    Add-CMUserAffinityToDevice -UserName $Combination -DeviceName $Name
}
