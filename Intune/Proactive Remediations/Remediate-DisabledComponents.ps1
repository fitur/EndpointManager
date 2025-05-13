<#

.SYNOPSIS
    PowerShell script detect if IPv6 is disabled in the registry.

.EXAMPLE
    .\Remediate-DisabledComponents.ps1

.DESCRIPTION
    This PowerShell script remediates the DisabledComponents registry key to enable IPv6.
    It sets the value of the DisabledComponents key to 0xFF, which indicates that IPv6 is disabled.
    The script checks if the registry key exists and if it does, it updates the value.
    If the key does not exist, it creates the key with the specified value.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2025-05-09
    Last Updated:   2025-05-09
    Author:         Peter Olausson
    Contact:        admin@fitur.se
#>

[CmdletBinding()]

Param (

)

$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\"
[string[]]$RegValue = Get-ItemPropertyValue $RegPath -Name "DisabledComponents" -ErrorAction SilentlyContinue

try {
    
    if (-not $null -eq $RegValue) {

        Write-Host 'Setting QuickAccessToolbarStyleExplorer property value to 0xFF.'
        Set-ItemProperty -Path $RegPath -Name "DisabledComponents" -Value "0xFF" -Force

    }
    else {

        Write-Host "Unable to read QuickAccessToolbarStyleExplorer. Creating key and setting property value 0xFF."
        New-ItemProperty -Path $RegPath -Name "DisabledComponents" -PropertyType DWord -Value "0xFF" -Force 

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}