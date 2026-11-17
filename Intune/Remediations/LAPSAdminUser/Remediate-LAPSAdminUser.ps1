<#
.SYNOPSIS
    Creates the local LAPSAdmin account and adds it to the local Administrators group.

.EXAMPLE
    .\Remediate-LAPSAdminUser.ps1

.DESCRIPTION
    Creates a local user named LAPSAdmin with a random temporary password (Windows LAPS
    replaces it on its next rotation) and adds it to the local Administrators group,
    resolved by its well-known SID so the script works on localized Windows.

    Both steps are idempotent: an existing account is not recreated and existing group
    membership is not treated as an error.

    Exit 0 = account exists and is a member of Administrators
    Exit 1 = remediation failed

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.1.0
    Creation Date:  2025-05-07
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-LAPSAdminUser.ps1 / Remediate-LAPSAdminUser.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = No
        Run script in 64-bit PowerShell                 = Yes (required - the
            LocalAccounts module is not available in 32-bit PowerShell on 64-bit Windows)
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.
    System.Web is a .NET Framework assembly, so this script does not run in PowerShell 7.

    Known limitations:
    - Do not deploy together with a remediation that strips unknown members from the
      Administrators group (see Archive/Remediations/LocalAdministrators) - the two
      undo each other on every run.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.1.0 - Idempotent: skips account creation when the account exists and tolerates
            existing group membership. Previously a partly completed run (account
            created, group add failed) could never be repaired. Explicit exit 0 and a
            single summary line.
    1.0.0 - Initial published version.
#>

$ErrorActionPreference = 'Stop'

$LAPSUser          = 'LAPSAdmin'
$AdministratorsSid = 'S-1-5-32-544'

try {
    $UserCreated = $false

    $ExistingUser = Get-LocalUser -Name $LAPSUser -ErrorAction SilentlyContinue
    if (-not $ExistingUser) {
        # Temporary password only - Windows LAPS rotates it. 16 characters, 4 non-alphanumeric.
        Add-Type -AssemblyName 'System.Web'
        $Password = ConvertTo-SecureString ([System.Web.Security.Membership]::GeneratePassword(16, 4)) -AsPlainText -Force

        New-LocalUser -Name $LAPSUser -Password $Password -AccountNeverExpires -PasswordNeverExpires | Out-Null
        $UserCreated = $true
    }

    try {
        Add-LocalGroupMember -SID $AdministratorsSid -Member $LAPSUser
    } catch {
        # Already a member is the desired state, not a failure
        if ($_.FullyQualifiedErrorId -notlike 'MemberExists*') { throw }
    }

    $Action = if ($UserCreated) { 'created and added to Administrators' } else { 'already existed; Administrators membership ensured' }
    Write-Output "Remediated: local user '$LAPSUser' $Action."
    exit 0
} catch {
    Write-Output "Remediation failed: $($_.Exception.Message)"
    exit 1
}
