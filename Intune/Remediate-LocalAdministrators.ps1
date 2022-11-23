<#

.SYNOPSIS
    PowerShell script to detect unallowed users with administrative privileges.

.EXAMPLE
    .\Remediate-LocalAdministrators.ps1

.DESCRIPTION
    This PowerShell script is deployed as a remediation script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.NOTES
    Version:        1.0
    Creation Date:  November 23, 2022
    Last Updated:   November 23, 2022
    Author:         Peter Olausson
    Contact:        admin@fitur.se
    Web Site:       https://github.com/fitur

#>

[CmdletBinding()]
param (
)
## Variables
$AdminGroupObject = ([adsi]"WinNT://$env:COMPUTERNAME").psbase.children.find((([Security.Principal.SecurityIdentifier]'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value | Split-Path -Leaf))
$AdminUserObject = Get-CimInstance -ClassName Win32_UserAccount -Filter "LocalAccount = TRUE and SID like 'S-1-5-%-500'"

## Function
$AdminGroupObject.psbase.Invoke("Members") | ForEach-Object {
    $TempAdminUser = ($_.GetType().InvokeMember('ADSPath','GetProperty',$null,$_,$null) -split "//" | Select-Object -Last 1) -replace "/","\
    if (($TempAdminUser -notmatch $AdminUserObject.Name) -and ($TempAdminUser -notmatch "S-1-12-1-")) {
        Write-Host "Removing unallowed local administrator: $TempAdminUser"
        net localgroup $AdminGroupObject.Name $TempAdminUser /delete
        #$AdminGroup.remove("WinNT://$TempAdminUser")
    }
}