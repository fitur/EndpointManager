<#

.SYNOPSIS
    PowerShell script to check for the existence of the LAPSAdmin user on a local system.

.EXAMPLE
    .\Detect-LAPSAdminUser.ps1

.DESCRIPTION
    This Powershell script is used to check if the LAPSAdmin user exists on the local system.
    If the user exists, it outputs "Compliant" and exits with a status code of 0.
    If the user does not exist, it outputs "Not Compliant" and exits with a status code of 1.
    In case of an error, it outputs the error message and exits with a status code of 1.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2025-05-07
    Last Updated:   2025-05-07
    Author:         Peter Olausson
    Contact:        admin@fitur.se

#>

[CmdletBinding()]

Param (

)

# Specify local admin user name
$LAPSUser = "LAPSAdmin"

try {
    
    # Check if the LAPSAdmin user exists
    if ($null -ne (get-localuser $LAPSUser -ErrorAction Stop)) {
        
        Write-Host "Compliant"
        Exit 0

    } else {

        Write-Host "Not Compliant"
        Exit 1

    }

}
catch {
    
    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}