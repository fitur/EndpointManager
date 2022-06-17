<#

.SYNOPSIS
    PowerShell script to detect any new user based AOVPN tunnel and simultaneously remove an old AllUserConnection-tunnel.

.EXAMPLE
    .\Detect-OldVPNTunnel.ps1

.DESCRIPTION
    This PowerShell script is deployed as a detection script using Proactive Remediations in Microsoft Endpoint Manager/Intune.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.NOTES
    Version:        1.0
    Creation Date:  June 2, 2022
    Last Updated:   June 17, 2022
    Author:         Peter Olausson
    Contact:        admin@fitur.se
    Web Site:       https://github.com/fitur

#>

[CmdletBinding()]
param (
)
## Variables
$Remediate = 0
$TunnelName = "NLTG VPN CA"
$OldTunnelName = "NLTG-ST-VPN"
Get-ChildItem $env:SystemDrive\Users | Where-Object {($_.Name -notmatch "public") -and ($_.Name -notmatch "defaultuser") -and ($_.LastAccessTime -gt (Get-Date).AddDays(-1))} | ForEach-Object {
    if (!(Get-LocalUser -Name $_.Name -ErrorAction SilentlyContinue)) {
        if ($PBK = Get-Item -Path ("{0}\AppData\Roaming\Microsoft\Network\Connections\Pbk\rasphone.pbk" -f $_.FullName) -ErrorAction SilentlyContinue) {
            if (Get-Content -Path $PBK.FullName -ErrorAction SilentlyContinue | Select-String -SimpleMatch "[$TunnelName]") {
                Write-Verbose "User tunnel present for user $($_.Name). Adding to remediate list." -Verbose
                $Remediate += 1
            }
            else {
                Write-Verbose "User tunnel not present for user $($_.Name). Skipping." -Verbose
            }
        }
        else {
            Write-Verbose "No PBK file present for user $($_.Name). Skipping." -Verbose
        }
    }
    else {
        # Skip if user is local
        Write-Verbose "User $($_.Name) is local. Skipping." -Verbose
    }
}
if ($Remediate -gt 0) {
    if (Get-VpnConnection -Name $OldTunnelName -AllUserConnection -ErrorAction SilentlyContinue) {
        Write-Verbose "Old VPN tunnel $OldTunnelName present. Remediation required." -Verbose
        exit 1
    } else {
        Write-Verbose "Old VPN tunnel $OldTunnelName not present. Exiting." -Verbose
        exit 0
    }
}
else {
    Write-Verbose "Nothing to remediate. Exiting." -Verbose
    exit 0
}