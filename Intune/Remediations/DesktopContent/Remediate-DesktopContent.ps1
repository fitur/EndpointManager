<#
.SYNOPSIS
    Remediation script for Intune Proactive Remediation: moves all Desktop content to a
    timestamped backup folder in Documents (preferring OneDrive Documents when available),
    then ensures a Deny ACE blocks the user from writing to the Desktop going forward.

.DESCRIPTION
    Runs in USER context, triggered when Detect-DesktopContent.ps1 reports non-compliant.

    1. Resolves Desktop path from HKCU Shell Folders (handles OneDrive KFM).
    2. Resolves a Documents target in this priority order:
         a) Documents shell folder, if already OneDrive-KFM-redirected
         b) A separate OneDrive account's Documents folder, if one exists
         c) Local Documents shell folder (fallback)
    3. Creates "<Documents>\Desktop Backup yyyy-MM-dd HHmm" and moves all Desktop content
       there.
    4. Adds a Deny ACE for the current user on the Desktop folder (idempotent - skips if an
       equivalent Deny rule already exists, since this runs daily).

    Exit 0 = remediation completed successfully
    Exit 1 = remediation failed (surfaced in Intune reporting)

.PARAMETER BackupPrefix
    Prefix for the backup folder name. Default: "Desktop Backup".

.PARAMETER LogFolder
    Folder where the local log file is written. Default: %LOCALAPPDATA%\Advania\Logs

.NOTES
    Advania Sverige AB
    Part of remediation pair: Detect-DesktopContent.ps1 / Remediate-DesktopBackupAndLock.ps1
    Test in pilot before broad rollout (one quarter, per standard governance principle).

    Known limitations:
    - Runs in user context, so it relies on the user already having permission to modify
      the ACL on their own Desktop folder (normally true, since the user is the owner).
    - Idempotency check compares FileSystemRights flags for an exact match; if the required
      deny rights are ever changed in this script, existing devices will get an additional
      ACE rather than an updated one until the old one is manually cleaned up.
    - This script runs as a plain script (no CmdletBinding/ShouldProcess) since Intune
      Remediations invoke it as a single, non-interactive unit via powershell.exe -File.
#>

param(
    [string]$BackupPrefix = "Desktop Backup",
    [string]$LogFolder = "$env:LOCALAPPDATA\Advania\Logs"
)

#region Logging
try {
    if (-not (Test-Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }
    $LogFile = Join-Path $LogFolder "DesktopBackupAndLock.log"
} catch {
    $LogFile = $null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    if ($LogFile) {
        try { Add-Content -Path $LogFile -Value $line -ErrorAction Stop } catch { }
    }
    Write-Output $line
}

Write-Log "===== Remediation started (user context: $env:USERDOMAIN\$env:USERNAME) ====="
#endregion

#region Resolve Desktop path (handles OneDrive KFM)
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

# Finds a Documents folder inside a separate OneDrive account (not a KFM-redirected
# Personal folder, but a regular "Documents" subfolder in a OneDrive-synced root).
function Get-OneDriveDocumentsPath {
    $accountsKey = "HKCU:\Software\Microsoft\OneDrive\Accounts"
    if (-not (Test-Path $accountsKey)) { return $null }

    $businessRoot = $null
    $personalRoot = $null

    Get-ChildItem -Path $accountsKey -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
        if ($props.UserFolder) {
            if ($_.PSChildName -like "Business*" -and -not $businessRoot) {
                $businessRoot = $props.UserFolder
            } elseif ($_.PSChildName -like "Personal*" -and -not $personalRoot) {
                $personalRoot = $props.UserFolder
            }
        }
    }

    # A business account takes priority over a personal OneDrive account if both exist.
    $root = if ($businessRoot) { $businessRoot } elseif ($personalRoot) { $personalRoot } else { $null }
    if (-not $root) { return $null }

    $docs = Join-Path $root "Documents"
    if (Test-Path $docs) { return $docs }
    return $null
}

try {
    $desktopPath = Get-ShellFolder -Name "Desktop" -DefaultPath ([Environment]::GetFolderPath("Desktop"))
    Write-Log "Desktop: $desktopPath"

    if (-not (Test-Path $desktopPath)) {
        Write-Log "Desktop path does not exist: $desktopPath" "ERROR"
        exit 1
    }

    $shellDocuments = Get-ShellFolder -Name "Personal" -DefaultPath ([Environment]::GetFolderPath("MyDocuments"))

    if ($shellDocuments -like "*OneDrive*") {
        # Documents is already KFM-redirected to OneDrive - use it directly.
        $documentsPath = $shellDocuments
        Write-Log "Documents is OneDrive-KFM-redirected, using: $documentsPath"
    } else {
        $oneDriveDocs = Get-OneDriveDocumentsPath
        if ($oneDriveDocs) {
            $documentsPath = $oneDriveDocs
            Write-Log "OneDrive Documents found, using: $documentsPath"
        } else {
            $documentsPath = $shellDocuments
            Write-Log "No OneDrive Documents found, using local Documents: $documentsPath"
        }
    }

    if (-not (Test-Path $documentsPath)) {
        Write-Log "Documents path does not exist: $documentsPath, creating it." "WARN"
        New-Item -Path $documentsPath -ItemType Directory -Force | Out-Null
    }
} catch {
    Write-Log "Could not resolve Desktop/Documents paths: $_" "ERROR"
    exit 1
}
#endregion

#region Create backup folder and move files (only if there is anything to move)
try {
    $itemsToMove = Get-ChildItem -Path $desktopPath -Force -ErrorAction Stop |
        Where-Object { $_.Name -ne 'desktop.ini' }

    if ($itemsToMove) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HHmm"
        $backupFolder = Join-Path $documentsPath "$BackupPrefix $timestamp"
        New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
        Write-Log "Backup folder: $backupFolder"

        $movedCount = 0
        $failedCount = 0
        foreach ($item in $itemsToMove) {
            try {
                Move-Item -Path $item.FullName -Destination $backupFolder -Force -ErrorAction Stop
                $movedCount++
            } catch {
                Write-Log "Could not move $($item.FullName): $_" "ERROR"
                $failedCount++
            }
        }
        Write-Log "Moved $movedCount item(s), $failedCount failed."

        if ($failedCount -gt 0 -and $movedCount -eq 0) {
            # Nothing was moved at all - do not attempt to set the ACL on a Desktop that
            # still has content, report failure instead so Intune flags the device.
            exit 1
        }
    } else {
        Write-Log "No content to move (may have already been cleared)."
    }
} catch {
    Write-Log "Error while moving Desktop content: $_" "ERROR"
    exit 1
}
#endregion

#region Set Deny ACE on the Desktop folder (idempotent - skipped if already present)
try {
    $currentUser = New-Object System.Security.Principal.NTAccount("$env:USERDOMAIN\$env:USERNAME")
    $denyRights = [System.Security.AccessControl.FileSystemRights] `
        "CreateFiles, AppendData, WriteData, WriteExtendedAttributes, WriteAttributes"

    $acl = Get-Acl -Path $desktopPath

    $alreadyPresent = $acl.Access | Where-Object {
        $_.IdentityReference.Value -eq $currentUser.Value -and
        $_.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Deny -and
        ($_.FileSystemRights -band $denyRights) -eq $denyRights
    }

    if ($alreadyPresent) {
        Write-Log "Deny ACE already present for $env:USERDOMAIN\$env:USERNAME - no action needed."
    } else {
        $inheritFlags = [System.Security.AccessControl.InheritanceFlags]"ContainerInherit, ObjectInherit"
        $propFlags    = [System.Security.AccessControl.PropagationFlags]::None

        $denyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $currentUser,
            $denyRights,
            $inheritFlags,
            $propFlags,
            [System.Security.AccessControl.AccessControlType]::Deny
        )

        $acl.AddAccessRule($denyRule)
        Set-Acl -Path $desktopPath -AclObject $acl
        Write-Log "Deny ACE (write) set for $env:USERDOMAIN\$env:USERNAME on $desktopPath"
    }
} catch {
    Write-Log "Could not set/check ACL on $desktopPath : $_" "ERROR"
    exit 1
}
#endregion

Write-Log "===== Remediation complete ====="
exit 0