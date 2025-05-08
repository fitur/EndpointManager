<#

.SYNOPSIS
    PowerShell script to set the Windows wallpaper to the default Windows wallpaper.

.EXAMPLE
    .\Remediate-SetWallpaper.ps1

.DESCRIPTION
    This PowerShell script is deployed as a remediation script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.NOTES
    Version:        1.0.0
    Creation Date:  2025-04-29
    Last Updated:   2025-04-29
    Author:         Peter Olausson
    Organization:   Advania
    Contact:        peter.olausson@advania.com

#>

[CmdletBinding()]

Param (

)

Try {

$setwallpapersrc = @"
using System.Runtime.InteropServices;

public class Wallpaper
{
  public const int SetDesktopWallpaper = 20;
  public const int UpdateIniFile = 0x01;
  public const int SendWinIniChange = 0x02;
  [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
  private static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
  public static void SetWallpaper(string path)
  {
    SystemParametersInfo(SetDesktopWallpaper, 0, path, UpdateIniFile | SendWinIniChange);
  }
}
"@
    Add-Type -TypeDefinition $setwallpapersrc

    [Wallpaper]::SetWallpaper("C:\WINDOWS\web\wallpaper\Windows\img0.jpg")

}

Catch {

    $ErrorMessage = $_.Exception.Message
    Write-Warning $ErrorMessage
    Exit 1

}