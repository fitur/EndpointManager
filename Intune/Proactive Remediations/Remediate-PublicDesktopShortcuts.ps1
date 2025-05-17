<#

.SYNOPSIS
    PowerShell script detect if IPv6 is disabled in the registry.

.EXAMPLE
    .\Remediate-PublicDesktopShortcuts.ps1

.DESCRIPTION
    This PowerShell script removes all shortcuts from the public desktop.
    This is a remediation script that should be used in conjunction with a detection script.

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
    
    # Remove all shortcuts individually
    $Files | ForEach-Object {

        Write-Host "Removing shortcut: $($_.FullName)"
        Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue

    }

}

catch {

    $ErrorMessage = $_.Exception.Message
    Write-Host $ErrorMessage
    Exit 1

}