<#

.SYNOPSIS
    PowerShell script to create a local user account with a random password and add it to the local administrators group.

.EXAMPLE
    .\Remediate-LAPSAdminUser.ps1

.DESCRIPTION
    This Powershell script creates a local user account named "LAPSAdmin" with a randomly generated password.
    The password is generated using the System.Web.Security.Membership class, ensuring it contains 4 special characters.
    The script then adds this user to the local administrators group. Run the script with administrative privileges.

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
    
    # Generate a temporary random password with 4 special characters (this will be replaced by LAPS)
    Add-Type -AssemblyName "System.Web"
    $Password = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(16, 4)) -AsPlainText -Force
    
    # Create local user and add user to the local administrator group
    New-LocalUser -Name $LAPSUser -AccountNeverExpires -Password $Password -PasswordNeverExpires
    Add-LocalGroupMember -SID "S-1-5-32-544" -Member $LAPSUser

}
catch {

    $ErrorMessage = $_.Exception.Message
    Write-Warning $ErrorMessage
    Exit 1

}
