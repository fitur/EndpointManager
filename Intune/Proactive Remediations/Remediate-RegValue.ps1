<#

.SYNOPSIS
    PowerShell script detect if IPv6 is disabled in the registry.

.EXAMPLE
    .\Remediate-RegValue.ps1

.DESCRIPTION
    This PowerShell script remediates a registry key with a specific value.
    If the value does not match, it indicates that remediation is required. The script will output a message indicating whether remediation is required.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2025-05-14
    Last Updated:   2025-05-14
    Author:         Peter Olausson
    Contact:        admin@fitur.se
#>

[CmdletBinding()]

Param (

)

# Set the registry parameters
$RegPath = "HKCU:\Software\Test"
$RegName = "ConnectionString"
$RegData = "Rb/cVDfW5FSwX9ipWDnxPT1xbAGkfj2Nr5lu5Qqc+NJ72YjQjlx2"
$RegType = "String"

# Check if the registry key exists
[string]$RegValue = Get-ItemPropertyValue $RegPath -Name $RegName -ErrorAction SilentlyContinue

try {
    
    if (-not $null -eq $RegValue) {

        # If the registry key exists, edit the value
        Write-Host "Setting $RegName property value to $($RegData.Substring(0,15))..."
        Set-ItemProperty -Path $RegPath -Name $RegName -Value $RegData -Force

    }
    else {

        # If the registry key does not exist, create it
        Write-Host "Unable to read $RegName. Creating key and setting property value $($RegData.Substring(0,15))..."

        # Checking if key exists
        if (-not (Test-Path $RegPath)) {

            # Create the registry path if it doesn't exist
            cmd /c reg add $($RegPath.Replace(':',''))

        }

        # Create the registry key and set the property value
        New-ItemProperty -Path $RegPath -Name $RegName -PropertyType $RegType -Value $RegData -Force 

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}