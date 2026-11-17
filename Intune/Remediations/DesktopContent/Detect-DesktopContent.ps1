<#
.SYNOPSIS
    Detection script for Intune Proactive Remediation: checks whether the current user's
    Desktop folder contains any content.

.DESCRIPTION
    Runs in USER context. Resolves the real Desktop path (handles OneDrive Known Folder
    Move if enabled) and reports non-compliant if anything other than desktop.ini exists
    there. A non-compliant result triggers Remediate-DesktopBackupAndLock.ps1.

    Exit 0 = compliant (Desktop is empty or missing, no remediation needed)
    Exit 1 = non-compliant (content found, or detection itself failed)

.NOTES
    Advania Sverige AB
    Part of remediation pair: Detect-DesktopContent.ps1 / Remediate-DesktopBackupAndLock.ps1
    Intune Remediation settings: "Run this script using the logged-on credentials" = Yes,
    "Enforce script signature check" per customer policy, frequency = Daily.

    Note: this script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
    Remediations invoke it as a single, non-interactive unit via powershell.exe -File.
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