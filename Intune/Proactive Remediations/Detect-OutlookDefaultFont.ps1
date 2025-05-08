<#

.SYNOPSIS
    PowerShell script to detect the default font settings in Outlook.

.EXAMPLE
    .\Detect-OutlookDefaultFont.ps1

.DESCRIPTION
    This Powershell script checks the registry for the default font settings in Outlook.
    It verifies the values of the ReplyFontComplex and ComposeFontComplex registry keys
    against predefined values. If the values match, it outputs "Compliant" and exits with
    a success code (0). If the values do not match or if there is an error accessing the
    registry, it outputs "Not Compliant" and exits with a failure code (1).

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.LINK
    https://www.github.com/fitur

.NOTES

    Version:        1.0.0
    Creation Date:  2025-04-29
    Last Updated:   2025-04-29
    Author:         Peter Olausson
    Contact:        admin@fitur.se
#>

[CmdletBinding()]

Param (

)

$RegPath = 'HKCU:\SOFTWARE\Microsoft\Office\16.0\Common\mailsettings\'
$Name1 = "ReplyFontComplex"
$Name2 = "ComposeFontComplex"
$Value1 = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,73,70,61,6E,2E,50,65,72,73,6F,6E,61,6C,52,65,70,6C,79,53,74,79,6C,65,31,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,61,6D,65,3A,22,50,65,72,73,6F,6E,61,6C,20,52,65,70,6C,79,20,53,74,79,6C,65,31,22,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,74,79,70,65,3A,70,65,72,73,6F,6E,61,6C,2D,72,65,70,6C,79,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,75,6E,68,69,64,65,3A,6E,6F,3B,0D,0A,09,6D,73,6F,2D,61,6E,73,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,32,2E,30,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,41,72,69,61,6C,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,61,73,63,69,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,68,61,6E,73,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,63,6F,6C,6F,72,3A,77,69,6E,64,6F,77,74,65,78,74,3B,0D,0A,09,66,6F,6E,74,2D,77,65,69,67,68,74,3A,6E,6F,72,6D,61,6C,3B,0D,0A,09,66,6F,6E,74,2D,73,74,79,6C,65,3A,6E,6F,72,6D,61,6C,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"
$Value2 = "3C,68,74,6D,6C,3E,0D,0A,0D,0A,3C,68,65,61,64,3E,0D,0A,3C,73,74,79,6C,65,3E,0D,0A,0D,0A,20,2F,2A,20,53,74,79,6C,65,20,44,65,66,69,6E,69,74,69,6F,6E,73,20,2A,2F,0D,0A,20,73,70,61,6E,2E,50,65,72,73,6F,6E,61,6C,43,6F,6D,70,6F,73,65,53,74,79,6C,65,0D,0A,09,7B,6D,73,6F,2D,73,74,79,6C,65,2D,6E,61,6D,65,3A,22,50,65,72,73,6F,6E,61,6C,20,43,6F,6D,70,6F,73,65,20,53,74,79,6C,65,22,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,74,79,70,65,3A,70,65,72,73,6F,6E,61,6C,2D,63,6F,6D,70,6F,73,65,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,6E,6F,73,68,6F,77,3A,79,65,73,3B,0D,0A,09,6D,73,6F,2D,73,74,79,6C,65,2D,75,6E,68,69,64,65,3A,6E,6F,3B,0D,0A,09,6D,73,6F,2D,61,6E,73,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,30,2E,30,70,74,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,73,69,7A,65,3A,31,32,2E,30,70,74,3B,0D,0A,09,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,41,72,69,61,6C,22,2C,73,61,6E,73,2D,73,65,72,69,66,3B,0D,0A,09,6D,73,6F,2D,61,73,63,69,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,68,61,6E,73,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,41,72,69,61,6C,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,66,6F,6E,74,2D,66,61,6D,69,6C,79,3A,22,54,69,6D,65,73,20,4E,65,77,20,52,6F,6D,61,6E,22,3B,0D,0A,09,6D,73,6F,2D,62,69,64,69,2D,74,68,65,6D,65,2D,66,6F,6E,74,3A,6D,69,6E,6F,72,2D,62,69,64,69,3B,0D,0A,09,63,6F,6C,6F,72,3A,77,69,6E,64,6F,77,74,65,78,74,3B,0D,0A,09,66,6F,6E,74,2D,77,65,69,67,68,74,3A,6E,6F,72,6D,61,6C,3B,0D,0A,09,66,6F,6E,74,2D,73,74,79,6C,65,3A,6E,6F,72,6D,61,6C,3B,7D,0D,0A,2D,2D,3E,0D,0A,3C,2F,73,74,79,6C,65,3E,0D,0A,3C,2F,68,65,61,64,3E,0D,0A,0D,0A,3C,2F,68,74,6D,6C,3E,0D,0A"

try {

    $Registry1 = (Get-ItemProperty -Path $RegPath -Name $Name1 -ErrorAction Stop | Select-Object -ExpandProperty $Name1 | ForEach-Object { '{0:X2}' -f $_ }) -join ','
    $Registry2 = (Get-ItemProperty -Path $RegPath -Name $Name2 -ErrorAction Stop | Select-Object -ExpandProperty $Name2 | ForEach-Object { '{0:X2}' -f $_ }) -join ','
    $Registry3 = Get-ItemProperty -Path $RegPath -Name ThemeFont -ErrorAction Stop | Select-Object -ExpandProperty ThemeFont

    if ($Registry1 -eq $Value1 -and $Registry2 -eq $Value2 -and $Registry3 -eq 2) {
        
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