 ## Load modules
try {
    Import-Module -Name ActiveDirectory -ErrorAction Stop
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
}
catch [System.Exception] {
    Write-Host "Could not load required modules. Exiting."
    throw
}

## Set location
try {
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
}
catch [System.Exception] {
    Write-Host "Could not load required modules. Exiting."
    throw
}


Get-WmiObject -Namespace root/SMS/site_$($SiteCode) -Class SMS_UserMachineRelationship -ComputerName $SiteCode.SiteServer  | Where-Object { ($_.ResourceName -match "PREFIX") -and ($_.IsActive -eq $true) -and ($_.Sources -match "4") -and ($_.Types -match 1) } | Sort-Object -Property ResourceName -Unique | ForEach-Object {
    Write-Host "Settting user $($_.UniqueUserName) as ManagedBy on AD device $($_.ResourceName)"
    Set-ADComputer -Identity $_.ResourceName -ManagedBy (Get-ADUser ($_.UniqueUserName | Split-Path -Leaf) -ErrorAction Stop | Select-Object -ExpandProperty DistinguishedName) -ErrorAction Stop -Verbose -WhatIf
} 
