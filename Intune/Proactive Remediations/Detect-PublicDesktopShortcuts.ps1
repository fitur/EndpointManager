<#

.SYNOPSIS
    PowerShell script detect if IPv6 is disabled in the registry.

.EXAMPLE
    .\Detect-PublicDesktopShortcuts.ps1

.DESCRIPTION
    This Powershell script detects if there are any shortcuts on the public desktop.
    
.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.0
    Creation Date:  2025-05-16
    Last Updated:   2025-05-16
    Author:         Peter Olausson
    Contact:        admin@fitur.se

#>

[CmdletBinding()]

Param (

)

# Get all shortcuts from the public desktop
$Files = Get-ChildItem -Path $env:PUBLIC\Desktop -Filter "*.lnk" -ErrorAction SilentlyContinue

try {
    
    if ($null -eq $Files) {

        Write-Host "No shortcuts found on public desktop. No remediation required."
        Exit 0

    }
    else {

        Write-Host "Shortcuts found on public desktop. Remediation required."
        Exit 1

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}