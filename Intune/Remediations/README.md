# Intune Remediations

```
MU/TH/UR 6000 :: CORRECTIVE SUBROUTINES
REF EM-2179/R — CLEARANCE: GENERAL — STATUS: ONLINE
```

Detection and remediation pairs for [Intune Remediations](https://learn.microsoft.com/intune/device-management/tools/deploy-remediations).
The detection script names the fault; the remediation script excises it. Each pair lives
in its own folder and is uploaded to Intune as one script package.

## Pairs

| Folder | Corrects | Logged-on credentials | Notes |
| --- | --- | --- | --- |
| `DesktopContent/` | Moves Desktop content to a backup folder in Documents and denies further writes to the Desktop | Yes | Changes the Desktop ACL. Pilot first. |
| `DisableIPv6/` | `DisabledComponents = 0xFF` | No | Reboot required. Microsoft recommends `0x20` (prefer IPv4) over disabling. |
| `LAPSAdminUser/` | Creates the local `LAPSAdmin` account for Windows LAPS to manage | No | Redundant where Windows LAPS automatic account management is used. |
| `LenovoSecureBoot/` | Enables Secure Boot through the Lenovo BIOS WMI interface | No | Suspends BitLocker for one reboot. Skips devices with a BIOS supervisor password. |
| `OutlookConversationView/` | Turns Conversation view off once, as a default | Yes | One-time default via a marker value, not enforcement. Verify the registry value before rollout. |
| `OutlookDefaultFont/` | Compose, reply and plain-text font set to Arial 10 pt | Yes | Applies after Outlook restarts. |
| `OutlookFocusedInbox/` | Focused Inbox off in classic Outlook | Yes | Undocumented per-account registry format. Complements `Set-OrganizationConfig -FocusedInboxOn $false`. |
| `OutlookQuickAccessToolbar/` | `QuickAccessToolbarStyleExplorer = 16` in Outlook | Yes | Applies after Outlook restarts. |
| `PublicDesktopShortcuts/` | Removes every `.lnk` from the Public Desktop | No | |
| `RealtekGbEFamilyControllerSettings/` | Disables Green Ethernet / EEE on Realtek USB GbE adapters (docks) | No | Restarts the adapter. First version that actually writes the settings — pilot first. |
| `SavedGuestWiFi/` | Removes saved Wi-Fi profiles matching `Guest` | No | Profiles deployed by policy cannot be removed. |

`_Template/` is the starting point for a new pair. It is not deployable as shipped.

Every script states its own Intune settings in the `.NOTES` block. For all pairs above:
**Run script in 64-bit PowerShell = Yes**, **Enforce script signature check** per customer
policy, schedule daily unless the header says otherwise.

## Directives

- **Windows PowerShell 5.1.** The Intune Management Extension runs these with
  `powershell.exe`, not `pwsh`. No PowerShell 7 syntax (`??`, `?.`, ternary, `&&`).
- **One line out.** Intune reports only the last line of output, so every exit path writes
  exactly one `Write-Output` summary line — prefixed `Compliant`, `Non-compliant`,
  `Not applicable`, `Remediated` or `… failed` — and then an explicit `exit 0` or `exit 1`.
- **Exit 1 is the only trigger.** A detection script must `exit 1` for the remediation to
  run; anything else counts as compliant.
- **Fail loudly.** `$ErrorActionPreference = 'Stop'` and one `try`/`catch` around the body.
  Use `SilentlyContinue` only where a missing value *is* the result, and say so in a comment.
- **Keep pairs in step.** Variables shared by the two scripts (paths, patterns, desired
  values) must be identical in both files.
- **Site designators.** `DesktopContent` and `OutlookConversationView` write under an
  `Advania` registry key and log folder. Re-map them before using the scripts elsewhere —
  and do not change them on a tenant that already runs them, or every device re-triggers.
- **ASCII and UTF-8.** Intune requires UTF-8; keeping the files ASCII avoids Windows
  PowerShell 5.1 misreading BOM-less UTF-8.

## New pair

1. Copy `_Template/` to `<Name>/` and rename the files to `Detect-<Name>.ps1` and
   `Remediate-<Name>.ps1`.
2. Replace the placeholders and rewrite both help blocks for the real check, including the
   Intune settings.
3. Test both scripts locally as the right identity (SYSTEM via `psexec -s` for
   "Logged-on credentials = No") before uploading.
4. Add the pair to the table above.
