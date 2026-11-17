<#
.SYNOPSIS
    Detects whether the current user's Desktop folder contains any content.

.DESCRIPTION
    Resolves the real Desktop path (handles OneDrive Known Folder Move if enabled) and
    reports non-compliant if anything other than desktop.ini exists there.

    Exit 0 = compliant (Desktop is empty)
    Exit 1 = non-compliant (content found, Desktop path missing, or detection failed)

.LINK
    https://learn.microsoft.com/intune/device-management/tools/deploy-remediations

.LINK
    https://www.github.com/fitur

.NOTES
    Version:        1.0.1
    Creation Date:  2026-10-29
    Last Updated:   2026-11-17
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Part of remediation pair: Detect-DesktopContent.ps1 / Remediate-DesktopContent.ps1
    Intune Remediation settings:
        Run this script using the logged-on credentials = Yes
        Run script in 64-bit PowerShell                 = Yes
        Schedule                                        = Daily
    Runs in Windows PowerShell 5.1 (Intune Management Extension) - no PS7 syntax.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.

    Changelog
    1.0.1 - Corrected the paired script name and the exit code documented for a
            missing Desktop path. Header aligned with the repository standard.
#>

function Get-ShellFolder {
    param([string]$Name, [string]$DefaultPath)
    $shellKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    $path = $null
    if (Test-Path $shellKey) {
        $raw = (Get-ItemProperty -Path $shellKey -ErrorAction SilentlyContinue).$Name
        if ($raw) {
            $path = [System.Environment]::ExpandEnvironmentVariables($raw)
        }
    }
    if (-not $path) { $path = $DefaultPath }
    return $path
}

try {
    $desktopPath = Get-ShellFolder -Name "Desktop" -DefaultPath ([Environment]::GetFolderPath("Desktop"))

    if (-not (Test-Path $desktopPath)) {
        Write-Output "Desktop path could not be found: $desktopPath"
        exit 1
    }

    # desktop.ini is excluded - it is a system-generated configuration file, not user
    # content, and would otherwise always trigger remediation.
    $items = Get-ChildItem -Path $desktopPath -Force -ErrorAction Stop |
        Where-Object { $_.Name -ne 'desktop.ini' }

    if ($items) {
        Write-Output "Content found on desktop ($($items.Count) item(s)) - triggering remediation."
        exit 1
    } else {
        Write-Output "Desktop is empty - nothing to remediate."
        exit 0
    }
} catch {
    Write-Output "Detection failed: $_"
    exit 1
}