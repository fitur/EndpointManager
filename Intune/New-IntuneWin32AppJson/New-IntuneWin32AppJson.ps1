#Requires -Version 7.4

<#
.SYNOPSIS
    Packages and uploads an Intune Win32 app from a zip-packaged PSADT application.

.DESCRIPTION
    The script accepts a path to a zip file, extracts it to a temporary directory
    alongside the zip file, reads ApplicationInformation.txt, and retrieves the
    intunewin and png files. A JSON file in Intune Graph API format (UTF-16 LE)
    is written to the extracted application directory, and the app is uploaded to
    Intune via the IntuneWin32App module using non-interactive client credentials.

    Supported detection rule formats in ApplicationInformation.txt
    (declared as DetectionMethod.(REG), DetectionMethod.(MSI) or DetectionMethod.(FILE)):
      Registry : HKEY_LOCAL_MACHINE\...\KeyPath\ValueName >= 1.0.0
                 Short hives HKLM, HKCU, HKCR, HKU and HKCC are also accepted.
      File     : %ProgramFiles%\App\file.exe >= 1.0.0
      MSI      : {ProductCode-GUID}

    If the PNG icon is missing or unreadable a blank 1x1 pixel PNG is used instead.

    Authentication is app-only, using either a certificate or a client secret. A
    certificate is preferred and takes precedence when both are available.

    Credentials can be supplied as parameters, via environment variables
    (INTUNE_TENANT_ID, INTUNE_CLIENT_ID, INTUNE_CLIENT_SECRET, INTUNE_CERT_THUMBPRINT,
    INTUNE_CERT_PATH, INTUNE_CERT_PASSWORD) or per customer through -CustomerConfigPath. Nothing in the script is
    tied to a specific organisation: the app owner comes from -Owner or INTUNE_APP_OWNER.

    NOTE: requires PowerShell 7.4+. Uses ternary operators, null-coalescing and
    ConvertFrom-Json -AsHashtable, none of which work on Windows PowerShell 5.1.

.PARAMETER AppPath
    Full or relative path to the zip file to process.

.PARAMETER TenantID
    Entra ID tenant ID. Falls back to $env:INTUNE_TENANT_ID.

.PARAMETER ClientID
    App registration client ID. Falls back to $env:INTUNE_CLIENT_ID.

.PARAMETER ClientSecret
    App registration client secret. Falls back to $env:INTUNE_CLIENT_SECRET.
    Ignored when a certificate is supplied.

.PARAMETER CertificateThumbprint
    Thumbprint of a certificate in the CurrentUser store - the login Keychain on macOS,
    the certificate store on Windows. Preferred over a client secret: the private key
    stays in the OS keystore. Falls back to $env:INTUNE_CERT_THUMBPRINT.

.PARAMETER CertificatePath
    Path to a PFX file, for environments without a usable certificate store such as a
    Linux-based Azure Function. Falls back to $env:INTUNE_CERT_PATH.

.PARAMETER CertificatePassword
    Password for the PFX file. Falls back to $env:INTUNE_CERT_PASSWORD.

.PARAMETER DescriptionsPath
    Location of IntuneAppDescriptions.json. Accepts an http(s) URL or a local file
    path. Falls back to $env:INTUNE_DESCRIPTIONS_PATH, then to the repository copy
    on GitHub.

    Each entry may be either a plain description string, or an object that also
    overrides the app name shown in Intune:

        "Chrome": "## Google Chrome ...",
        "7Zip":   { "displayName": "7-Zip", "description": "## 7-Zip ..." }

    With an override the app is named "<displayName> <Version>" (7-Zip 26.02);
    without one it is "<Vendor> <Name> <Version>" (IgorPavlov 7Zip 26.02).

.PARAMETER Architecture
    Architecture requirement sent to Intune. Defaults to x64.

.PARAMETER MinimumWindowsRelease
    Minimum supported Windows release sent to Intune. Defaults to W11_21H2, the
    earliest Windows 11 release. Note that omitting the requirement rule entirely
    makes the IntuneWin32App module fall back to Windows 10 20H2.

.PARAMETER AssignmentGroupId
    Object ID of the Entra group to assign the app to. Falls back to
    $env:INTUNE_ASSIGNMENT_GROUP_ID. Assignment is skipped entirely when neither is set;
    supplying any other assignment parameter without a group ID raises an error.

.PARAMETER AssignmentIntent
    How the app is published to the group:
      required  - enforced installation (the default)
      available - published to Company Portal for the user to install on demand
      uninstall - removes the app from the group
    Defaults to required, so passing only -AppPath with a group configured publishes
    the app as required, immediately.

.PARAMETER AssignmentNotification
    End user notification behaviour: showAll, showReboot or hideAll. Defaults to showAll.

.PARAMETER AvailableTime
    When the app becomes available. A future value requires -DeadlineTime as well,
    because the IntuneWin32App module rejects that combination.
    Omitting both this and -DeadlineTime publishes the app immediately.

.PARAMETER DeadlineTime
    Installation deadline. Must be later than -AvailableTime when both are given.

.PARAMETER Owner
    Owner recorded on the app in Intune. Falls back to $env:INTUNE_APP_OWNER, and is left
    empty when neither is set.

.PARAMETER CustomerConfigPath
    Path to a local JSON file holding credentials for several customers. When supplied, the
    customer's tenant ID, client ID, secret and optionally assignment group, owner and
    descriptions path are used instead of the environment variables. Explicitly passed
    parameters still win over the file.

.PARAMETER CustomerName
    Selects a customer from the file without prompting. Required for unattended runs.

.PARAMETER Quiet
    Suppresses the per-chunk upload progress from the IntuneWin32App module, which is
    otherwise shown. Use it when running the script from a pipeline or scheduled job.

.PARAMETER SupersedenceType
    Update (default) installs over the earlier version; Replace uninstalls it first.

.PARAMETER IntuneWin32AppVersion
    Pins the IntuneWin32App module to a specific version, so a new release cannot change
    behaviour unnoticed in production. Recommended for scheduled or unattended runs.

.PARAMETER PatchTuesday
    Schedules the assignment on the next Patch Tuesday - the second Tuesday of the month -
    available at 00:00 and with a deadline at 12:00 the same day. Cannot be combined with
    -AvailableTime or -DeadlineTime. If the current day is itself a Patch Tuesday, the
    following month is used.

.PARAMETER UseLocalTime
    $true (default) interprets the assignment timestamps in the device's local time.
    The module writes timestamps with a Z suffix without converting them to UTC, so
    setting this to $false shifts a locally entered time by the UTC offset.

.OUTPUTS
    PSCustomObject with DisplayName, AppId, JsonPath, DetectionType and DescriptionFound.

.EXAMPLE
    .\New-IntuneWin32AppJson.ps1 -AppPath "C:\AppTest\MyApp_1.0.zip"

.EXAMPLE
    # Validate parsing and JSON generation without touching Intune
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\MyApp_1.0.zip" -WhatIf

.EXAMPLE
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\MyApp_1.0.zip" -DescriptionsPath "C:\Scripts\IntuneAppDescriptions.json"

.EXAMPLE
    # Allow Windows 10 22H2 and 32-bit hardware for a legacy package
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\LegacyApp_2.0.zip" -Architecture x64x86 -MinimumWindowsRelease W10_22H2

.EXAMPLE
    # With $env:INTUNE_ASSIGNMENT_GROUP_ID set: publish as required, immediately
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip"

.EXAMPLE
    # Certificate from the login Keychain / certificate store instead of a secret
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip" -CertificateThumbprint "A1B2C3..."

.EXAMPLE
    # Pick a customer from the local credential file, prompting for which one
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip" -CustomerConfigPath ~/.config/endpointmanager/customers.json

.EXAMPLE
    # Same, unattended
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip" `
        -CustomerConfigPath ~/.config/endpointmanager/customers.json -CustomerName "Contoso"

.EXAMPLE
    # Publish to Company Portal for users to install themselves
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip" -AssignmentIntent available

.EXAMPLE
    # Required, scheduled on the next Patch Tuesday: available 00:00, deadline 12:00
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip" -PatchTuesday

.EXAMPLE
    # Required with an explicit window (device local time)
    .\New-IntuneWin32AppJson.ps1 -AppPath ".\App.zip" `
        -AssignmentGroupId "8f3c1e20-4d5a-4f1b-9c2e-7a6b5c4d3e2f" `
        -AvailableTime (Get-Date "2026-09-01 08:00") `
        -DeadlineTime  (Get-Date "2026-09-08 17:00")

.NOTES
    Version:        3.0.1
    Creation Date:  2026-05-07
    Last Updated:   2026-09-15
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Requires PowerShell 7.4+ and the IntuneWin32App module, which is installed
    automatically on first run. Graph permission: DeviceManagementApps.ReadWrite.All
    as an Application permission with admin consent.

    CHANGELOG

        3.0.1 - 2026-09-15
            Fixes from the first production run of 3.0.0. The upload check failed on every
            run: it selected committedContentVersion, which lives on the derived mobileLobApp
            type, and Graph rejects that on the mobileApps collection with 400 - so
            supersedence, assignment and retirement never ran. The check now reads the full
            app. Graph error bodies are reported in clear text; Invoke-RestMethod puts only a
            generic status line in the exception message and the reason in ErrorDetails, which
            is why that failure read "400 (Bad Request)" and nothing more. A failed check now
            says the app may well be intact and that a rerun is refused while it exists. The
            keep decision fails closed: a failed lookup used to count the version as
            unassigned, which could keep the wrong one and retire the version actually
            deployed; supersedence and retirement are now skipped instead. createdDateTime
            comes from the inventory rather than an extra request per candidate. Retirement
            also removes the kept version's supersedence link to the retired versions, which
            previously stayed until the next release and kept the newest retired version
            linked.

        3.0.0 - 2026-09-09
            Version lifecycle. The script now supersedes the previous version automatically,
            assigns in two rings and can retire earlier versions. The version kept is the
            highest one that actually has an assignment, not simply the highest version
            number - a half-finished earlier run can otherwise leave a higher version with
            no assignments and get the right app retired. Retirement is opt-in via
            -RetireSuperseded and only runs once the upload is verified and the assignment
            succeeded, because it can otherwise leave the tenant with no deployed version.
            The upload is now verified against the app's publishingState and
            committedContentVersion rather than against a returned app id: the module creates
            the app record before the content and returns nothing if the commit fails, which
            leaves an empty app behind in the tenant. The assignment is built against Graph
            directly instead of via the module, which always sends useLocalTime and
            deadlineDateTime and therefore cannot express a scheduled available assignment;
            the switch also removes a silent termination of the whole script, since the
            module's validation failures exit with break, which neither try/catch nor warning
            capture stops. Rerunning an already uploaded package is now refused instead of
            creating a duplicate. -Supersede is gone; supersedence is no longer optional.

        2.7.1 - 2026-08-25
            Assignment and supersedence failures are no longer reported as successes. Both
            module functions report Graph errors and validation failures with Write-Warning
            and then return normally, so the surrounding try/catch never fired - the script
            printed "Assigned to group ..." for an assignment Intune had rejected. Both
            calls now capture warnings and report accordingly. Scheduling combined with
            -AssignmentIntent available is also rejected up front: Intune does not accept
            deadline or local time settings on available assignments, and the module always
            includes useLocalTime when any time is supplied.

        2.7.0 - 2026-08-25
            Added certificate authentication as an alternative to the client secret, via
            -CertificateThumbprint (CurrentUser store, which is the login Keychain on
            macOS) or -CertificatePath for a PFX. Customers in the credential file can
            specify certificateThumbprint or certificatePath instead of a secret, and a
            certificate takes precedence so a leftover secret cannot shadow it. Both
            sources produce an X509Certificate2 for Connect-MSIntuneGraph -ClientCert,
            which is also what a later Key Vault source would produce.

        2.6.0 - 2026-08-24
            Fixes from an external code review of a colleague's fork. The UTF-16 BOM is
            now skipped rather than decoded, which previously left a U+FEFF that made the
            first field in ApplicationInformation.txt unmatchable - reported as "Missing
            required fields" on a perfectly valid file. The app id is read through
            PSObject.Properties instead of $_.id, which threw under StrictMode on any
            object lacking the property and surfaced as a failed upload after the app had
            already been created. Zips without a wrapping folder are now supported. Return
            codes are defined once instead of in two places, the app inventory query uses
            $select, Install-Module pins PSGallery, and -Quiet suppresses upload progress.

        2.5.0 - 2026-08-19
            Added -CustomerConfigPath and -CustomerName for working across several
            customer tenants from one local credential file. The logic is embedded in
            the script rather than a module, so it stays a single file. Selection happens
            before the credential parameters are consumed, values not defined for a
            customer are cleared rather than inherited from the environment, and
            explicitly passed parameters still take precedence over the file.

        2.4.0 - 2026-08-13
            Added optional supersedence via -Supersede and -SupersedenceType. Earlier
            versions of the same app are located by an exact "<base> <version>" name
            match against both naming conventions, with a strict version comparison so
            newer versions and similarly named products are never touched. All
            relationships are submitted in one call, because the module replaces the
            whole supersedence set on each write.

        2.3.0 - 2026-08-13
            Removed the hardcoded app owner. It now comes from -Owner or
            $env:INTUNE_APP_OWNER and is empty when neither is set. The value is also
            passed to Add-IntuneWin32App, which it previously was not - the owner
            appeared in the JSON artifact but never reached Intune.

        2.2.0 - 2026-08-12
            Hardening after an external code review. The JSON artifact is now copied
            next to the zip before cleanup, so the returned JsonPath no longer points
            at a deleted file. The return code patch and the group assignment each got
            their own try/catch: both run after the app exists in Intune, so failing
            them no longer reports an upload failure that invites a duplicate-creating
            rerun. Temp directories are unique per run for parallel execution. Encoding
            detection handles BOM-less UTF-16 and no longer picks Mac Roman on a tie.
            Added -IntuneWin32AppVersion for module pinning, a guard against a past
            deadline without an available time, retries on Graph calls, and filename
            sanitising for displayName overrides.

        2.1.0 - 2026-08-11
            Optional assignment to an Entra group via -AssignmentGroupId or
            $env:INTUNE_ASSIGNMENT_GROUP_ID, with -AssignmentIntent (required/available/
            uninstall) and an optional schedule. -PatchTuesday sets available 00:00 and
            deadline 12:00 on the next second Tuesday; without it the app publishes
            immediately. Assignment input is validated before extraction, including the
            module quirk where a future available time without a deadline is silently
            skipped.

        2.0.0 - 2026-08-11
            Rewritten for PowerShell 7.4; no longer runs on 5.1. Added -WhatIf, which
            validates and builds the JSON without authenticating or uploading. Fixed the
            requirement rule never being sent, which made Intune fall back to Windows 10
            20H2 and drop the disk space requirement entirely - now configurable via
            -Architecture and -MinimumWindowsRelease, defaulting to x64 and W11_21H2.
            Descriptions file entries may now override the app name via displayName, and
            name matching ignores case and punctuation so "7Zip" matches "7-Zip".

        1.2.0 - 2026-06-15
            Detection rules extended beyond registry to MSI product codes and file paths,
            with short hive names (HKLM, HKCU, ...) accepted. Text encoding is now detected
            automatically across UTF-8, UTF-16, Mac Roman and Windows-1252, so Swedish
            characters survive packages built on either macOS or Windows. macOS __MACOSX
            folders in the zip are ignored.

        1.1.0 - 2026-06-04
            App descriptions moved out of the script to an external JSON file, reachable
            by local path or URL, so they can be maintained without editing code. -AppPath
            now points at the zip file itself rather than a folder. Credentials and
            required ApplicationInformation.txt fields are validated up front, reporting
            everything missing at once.

        1.0.0 - 2026-05-07
            First working version: extracts the zip, parses ApplicationInformation.txt,
            builds the Intune JSON and uploads via the IntuneWin32App module. Return code
            1641 is patched to softReboot afterwards, since passing return codes to the
            module appends them to its defaults and produces duplicates.
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path -Path $_ -PathType Leaf)) {
            throw "AppPath '$_' does not exist or is not a file."
        }
        if ([System.IO.Path]::GetExtension($_) -ne ".zip") {
            throw "AppPath '$_' is not a .zip file."
        }
        $true
    })]
    [string]$AppPath,

    [Parameter()]
    [string]$TenantID = $env:INTUNE_TENANT_ID,

    [Parameter()]
    [string]$ClientID = $env:INTUNE_CLIENT_ID,

    [Parameter()]
    [string]$ClientSecret = $env:INTUNE_CLIENT_SECRET,

    # Certificate authentication, preferred over a client secret. Thumbprint looks the
    # certificate up in the current user's store - the login Keychain on macOS, the
    # certificate store on Windows. Use the path form where no store exists, such as a
    # Linux-based Azure Function.
    [Parameter()]
    [string]$CertificateThumbprint = $env:INTUNE_CERT_THUMBPRINT,

    [Parameter()]
    [string]$CertificatePath = $env:INTUNE_CERT_PATH,

    [Parameter()]
    [string]$CertificatePassword = $env:INTUNE_CERT_PASSWORD,

    [Parameter()]
    [string]$DescriptionsPath = ($env:INTUNE_DESCRIPTIONS_PATH ??
        "https://raw.githubusercontent.com/fitur/EndpointManager/refs/heads/master/Intune/New-IntuneWin32AppJson/IntuneAppDescriptions.json"),

    # ValidateSet values mirror New-IntuneWin32AppRequirementRule in the IntuneWin32App module
    [Parameter()]
    [ValidateSet("x64", "x86", "arm64", "x64x86", "AllWithARM64")]
    [string]$Architecture = "x64",

    [Parameter()]
    [ValidateSet("W10_1607", "W10_1703", "W10_1709", "W10_1803", "W10_1809", "W10_1903", "W10_1909",
                 "W10_2004", "W10_20H2", "W10_21H1", "W10_21H2", "W10_22H2", "W11_21H2", "W11_22H2")]
    [string]$MinimumWindowsRelease = "W11_21H2",

    # Assignment is optional: the step only runs when a group ID is supplied here or via
    # $env:INTUNE_ASSIGNMENT_GROUP_ID. Supplying any other assignment parameter without a
    # group ID is treated as a configuration error rather than silently skipped.
    [Parameter()]
    [string]$AssignmentGroupId = $env:INTUNE_ASSIGNMENT_GROUP_ID,

    [Parameter()]
    [ValidateSet("required", "available", "uninstall")]
    [string]$AssignmentIntent = "required",

    [Parameter()]
    [ValidateSet("showAll", "showReboot", "hideAll")]
    [string]$AssignmentNotification = "showAll",

    # Nullable so "not supplied" is distinguishable from DateTime.MinValue
    [Parameter()]
    [Nullable[datetime]]$AvailableTime,

    [Parameter()]
    [Nullable[datetime]]$DeadlineTime,

    # $true means the timestamps are interpreted in the device's local time.
    # The module stamps times with a Z suffix without converting to UTC, so leaving this
    # $false would shift a local time by the UTC offset.
    [Parameter()]
    [bool]$UseLocalTime = $true,

    # Schedules the assignment on the next Patch Tuesday: available 00:00, deadline 12:00.
    # Without it, and without explicit times, the app is published immediately.
    [Parameter()]
    [switch]$PatchTuesday,

    # Pin the IntuneWin32App module version so a new release cannot silently change behaviour
    # in production. Empty means "whatever is installed or latest".
    [Parameter()]
    [string]$IntuneWin32AppVersion,

    # Owner shown on the app in Intune. Left empty when neither this nor the environment
    # variable is set, which matches the module's own default.
    [Parameter()]
    [string]$Owner = $env:INTUNE_APP_OWNER,

    # Local JSON file holding per-customer credentials. When supplied, the customer is
    # selected (prompted for unless -CustomerName is given) and its values populate the
    # INTUNE_* environment variables before anything else runs.
    [Parameter()]
    [string]$CustomerConfigPath,

    [Parameter()]
    [string]$CustomerName,

    # Suppresses the module's per-chunk upload progress. On by default because a large
    # package uploads in many chunks and the progress is the only sign it is still working.
    [Parameter()]
    [switch]$Quiet,

    # Update installs over the old version; Replace uninstalls it first
    [Parameter()]
    [ValidateSet("Update", "Replace")]
    [string]$SupersedenceType = "Update",

    # Ring rollout: object ID of the pilot group. Requires -ProductionGroupId as well. When
    # both are resolved (here or from the customer file) the app is assigned in two rings
    # instead of to a single group. An explicit parameter still wins over the customer file.
    [Parameter()]
    [string]$PilotGroupId,

    # Ring rollout: object ID of the production group. Requires -PilotGroupId as well.
    [Parameter()]
    [string]$ProductionGroupId,

    # Hours from now to the production ring's start in the default (non-PatchTuesday) ring
    # schedule; the pilot ring publishes immediately.
    [Parameter()]
    [ValidateRange(1, 8760)]
    [int]$ProductionDelayHours = 24,

    # Hours from a ring's start to its deadline, for the production ring in both schedules.
    # The PatchTuesday pilot ring keeps its own fixed 12:00 deadline.
    [Parameter()]
    [ValidateRange(1, 8760)]
    [int]$DeadlineOffsetHours = 24,

    # Opt-in: after a verified upload and a fully successful assignment, retire the earlier
    # versions - clear their supersedence, remove their assignments and rename them "(TBD)".
    # Without it the script only reports which apps would be retired.
    [Parameter()]
    [switch]$RetireSuperseded
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve to absolute path so relative input works from any working directory
$AppPath = (Resolve-Path -Path $AppPath).Path

#region Customer selection

# Resolves credentials from a local multi-customer JSON file. Self-contained on purpose:
# the script stays a single file that can be copied to a machine on its own.
#
# The credential parameters default to the INTUNE_* environment variables, which are
# evaluated when the script is invoked, so the values have to be assigned here rather than
# by setting the environment.
if ($CustomerConfigPath) {

    if (-not (Test-Path -Path $CustomerConfigPath -PathType Leaf)) {
        throw "Customer config '$CustomerConfigPath' does not exist or is not a file."
    }
    $customerConfigResolved = (Resolve-Path -Path $CustomerConfigPath).Path

    # Warn when the file is readable by more than its owner. UnixMode is not populated on Windows.
    if (-not $IsWindows) {
        $configItem = Get-Item -Path $customerConfigResolved
        if ($configItem.PSObject.Properties.Name -contains "UnixMode" -and
            $configItem.UnixMode.Substring(4) -match '[rwx]') {
            Write-Warning "'$customerConfigResolved' is readable beyond its owner ($($configItem.UnixMode)). Run: chmod 600 '$customerConfigResolved'"
        }
    }

    try {
        $customerConfig = Get-Content -Path $customerConfigResolved -Raw -Encoding UTF8 |
            ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        throw "Could not parse '$customerConfigResolved' as JSON: $($PSItem.Exception.Message)"
    }

    if (-not $customerConfig.ContainsKey("customers")) {
        throw "'$customerConfigResolved' has no 'customers' array."
    }

    $customers = @($customerConfig["customers"] | Where-Object { $_ -and $_.ContainsKey("name") -and $_["name"] })
    if ($customers.Count -eq 0) {
        throw "'$customerConfigResolved' contains no usable customer entries."
    }

    $duplicateNames = @($customers | Group-Object { $_["name"] } | Where-Object { $_.Count -gt 1 })
    if ($duplicateNames.Count -gt 0) {
        throw "Duplicate customer names in '$customerConfigResolved': $(($duplicateNames.Name) -join ', ')"
    }

    # Select the customer: by name when given, otherwise ask
    if ($CustomerName) {
        $customer = $customers | Where-Object { $_["name"] -eq $CustomerName } | Select-Object -First 1
        if (-not $customer) {
            throw "Customer '$CustomerName' not found. Available: $((($customers | ForEach-Object { $_["name"] }) -join ', '))"
        }
    }
    else {
        $customerNames = $customers | ForEach-Object { $_["name"] }
        $customer      = $null

        # Native picker on macOS, console menu everywhere else and on cancel/failure
        if ($IsMacOS) {
            $quotedNames  = ($customerNames | ForEach-Object { '"' + ($_ -replace '"', '\"') + '"' }) -join ", "
            $chosenName   = & osascript -e ("choose from list {$quotedNames} with prompt ""Select customer tenant"" with title ""EndpointManager""") 2>$null
            if ($chosenName -eq "false") { throw "Customer selection cancelled." }
            if ($LASTEXITCODE -eq 0 -and $chosenName) {
                $customer = $customers | Where-Object { $_["name"] -eq $chosenName.Trim() } | Select-Object -First 1
            }
        }

        if (-not $customer) {
            Write-Host "`nAvailable customers:" -ForegroundColor Cyan
            for ($i = 0; $i -lt $customers.Count; $i++) {
                Write-Host ("  [{0}] {1}" -f ($i + 1), $customers[$i]["name"])
            }
            while (-not $customer) {
                $answer = Read-Host "`nSelect customer (1-$($customers.Count), or Q to quit)"
                if ($answer -match '^[Qq]') { throw "Customer selection cancelled." }
                $index = 0
                if ([int]::TryParse($answer, [ref]$index) -and $index -ge 1 -and $index -le $customers.Count) {
                    $customer = $customers[$index - 1]
                }
                else {
                    Write-Warning "Enter a number between 1 and $($customers.Count), or Q to quit."
                }
            }
        }
    }

    foreach ($requiredKey in "tenantId", "clientId") {
        if (-not ($customer.ContainsKey($requiredKey) -and $customer[$requiredKey])) {
            throw "Customer '$($customer["name"])' is missing '$requiredKey'."
        }
    }

    # Certificate takes precedence over a secret when the customer defines one
    $customerThumbprint = $customer.ContainsKey("certificateThumbprint") ? [string]$customer["certificateThumbprint"] : ""
    $customerCertPath   = $customer.ContainsKey("certificatePath")       ? [string]$customer["certificatePath"]       : ""

    if ($customerThumbprint -or $customerCertPath) {
        # Explicit parameters still win, as everywhere else
        if (-not $PSBoundParameters.ContainsKey("CertificateThumbprint")) { $CertificateThumbprint = $customerThumbprint }
        if (-not $PSBoundParameters.ContainsKey("CertificatePath"))       { $CertificatePath       = $customerCertPath }
        if (-not $PSBoundParameters.ContainsKey("CertificatePassword")) {
            $CertificatePassword = $customer.ContainsKey("certificatePassword") ? [string]$customer["certificatePassword"] : ""
        }
        # Make sure a secret left in the environment cannot shadow the certificate
        $ClientSecret = ""
    }
    else {

    # Secret comes either inline or from a SecretManagement vault
    $usesVault = ($customer.ContainsKey("secretVault") -and $customer["secretVault"]) -or
                 ($customer.ContainsKey("secretName")  -and $customer["secretName"])

    if ($usesVault) {
        if (-not (($customer.ContainsKey("secretVault") -and $customer["secretVault"]) -and
                  ($customer.ContainsKey("secretName")  -and $customer["secretName"]))) {
            throw "Customer '$($customer["name"])' must define both secretVault and secretName, or neither."
        }
        if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.SecretManagement)) {
            throw "Customer '$($customer["name"])' uses a secret vault, but Microsoft.PowerShell.SecretManagement is not installed."
        }
        Import-Module Microsoft.PowerShell.SecretManagement -ErrorAction Stop
        $ClientSecret = Get-Secret -Vault $customer["secretVault"] -Name $customer["secretName"] -AsPlainText -ErrorAction Stop
        if (-not $ClientSecret) {
            throw "Secret '$($customer["secretName"])' in vault '$($customer["secretVault"])' is empty."
        }
    }
    elseif ($customer.ContainsKey("clientSecret") -and $customer["clientSecret"]) {
        $ClientSecret = [string]$customer["clientSecret"]
    }
    else {
        throw "Customer '$($customer["name"])' has no certificate, no clientSecret and no secretVault/secretName."
    }

    }   # end of the secret branch

    $TenantID = [string]$customer["tenantId"]
    $ClientID = [string]$customer["clientId"]

    # The file is authoritative for the optional values too: a value the customer does not
    # define is cleared rather than left at whatever the environment held, so a group ID
    # from a previously selected customer cannot follow into this run.
    if (-not $PSBoundParameters.ContainsKey("AssignmentGroupId")) {
        $AssignmentGroupId = $customer.ContainsKey("assignmentGroupId") ? [string]$customer["assignmentGroupId"] : $null
    }
    # Ring groups follow the same rule as assignmentGroupId: cleared, not inherited, when the
    # customer does not define them, so another customer's pilot/production groups cannot leak in.
    if (-not $PSBoundParameters.ContainsKey("PilotGroupId")) {
        $PilotGroupId = $customer.ContainsKey("pilotGroupId") ? [string]$customer["pilotGroupId"] : $null
    }
    if (-not $PSBoundParameters.ContainsKey("ProductionGroupId")) {
        $ProductionGroupId = $customer.ContainsKey("productionGroupId") ? [string]$customer["productionGroupId"] : $null
    }
    if (-not $PSBoundParameters.ContainsKey("Owner")) {
        $Owner = $customer.ContainsKey("appOwner") ? [string]$customer["appOwner"] : $null
    }
    # DescriptionsPath has a working default, so only replace it when the customer sets one
    if ($customer.ContainsKey("descriptionsPath") -and $customer["descriptionsPath"] -and
        -not $PSBoundParameters.ContainsKey("DescriptionsPath")) {
        $DescriptionsPath = [string]$customer["descriptionsPath"]
    }

    Write-Host "Customer: $($customer["name"])  (tenant $TenantID)" -ForegroundColor Green
}

#endregion

# These mirror the lookup tables inside New-IntuneWin32AppRequirementRule so the generated
# JSON artifact records the same values that are actually sent to Intune.
# Return codes written to the JSON artifact and used to correct the module's defaults after
# upload. Defined once so the two can never drift apart.
$script:Win32AppReturnCodes = @(
    [ordered]@{ returnCode = 0;    type = "success" }
    [ordered]@{ returnCode = 1707; type = "success" }
    [ordered]@{ returnCode = 3010; type = "softReboot" }
    [ordered]@{ returnCode = 1641; type = "softReboot" }   # module default is hardReboot
    [ordered]@{ returnCode = 1618; type = "retry" }
)

# 1x1 transparent PNG, used when a package ships without an icon
$script:BlankPngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

$architectureMap = @{
    "x64" = "x64"; "x86" = "x86"; "arm64" = "arm64"
    "x64x86" = "x64,x86"; "AllWithARM64" = "x64,x86,arm64"
}
$windowsReleaseMap = @{
    "W10_1607" = "1607"; "W10_1703" = "1703"; "W10_1709" = "1709"; "W10_1803" = "1803"
    "W10_1809" = "1809"; "W10_1903" = "1903"; "W10_1909" = "1909"; "W10_2004" = "2004"
    "W10_20H2" = "2H20"; "W10_21H1" = "21H1"; "W10_21H2" = "Windows10_21H2"
    "W10_22H2" = "Windows10_22H2"; "W11_21H2" = "Windows11_21H2"; "W11_22H2" = "Windows11_22H2"
}

#region Functions

function Get-NormalizedKey {
    <#
    .SYNOPSIS
        Normalises an app name for fuzzy comparison by stripping every character
        that is not a letter or digit and lowercasing the result.
        This makes "7Zip", "7-Zip" and "7 Zip" all compare equal.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )
    ($Value -replace '[^\p{L}\p{Nd}]', '').ToLowerInvariant()
}

function Resolve-DescriptionEntry {
    <#
    .SYNOPSIS
        Normalises one entry from IntuneAppDescriptions.json into Description and DisplayName.

    .DESCRIPTION
        Two entry shapes are supported so existing files keep working:
          "Chrome": "## Google Chrome ..."                        -> description only
          "7Zip"  : { "displayName": "7-Zip",
                      "description": "## 7-Zip ..." }             -> description plus name override
    #>
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)][AllowNull()]$Entry
    )

    if ($Entry -is [System.Collections.IDictionary]) {
        return [pscustomobject]@{
            Description = $Entry.Contains("description") ? [string]$Entry["description"] : ""
            DisplayName = $Entry.Contains("displayName") ? [string]$Entry["displayName"] : $null
        }
    }

    [pscustomobject]@{ Description = [string]$Entry; DisplayName = $null }
}

function Get-AppDescription {
    <#
    .SYNOPSIS
        Looks up a Markdown description for an app in IntuneAppDescriptions.json,
        read from either an http(s) URL or a local file path.

    .DESCRIPTION
        Matching is attempted in three passes: exact name, normalised name
        (case/punctuation insensitive), then normalised substring with the longest
        key preferred so more specific entries win.

    .OUTPUTS
        PSCustomObject with Found (bool), Description (string) and DisplayName (string or $null).
        DisplayName is only populated when the matched entry supplies a name override.
    #>
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)][string]$AppName,
        [Parameter(Mandatory)][string]$FallbackName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Source
    )

    $notFound = [pscustomobject]@{ Found = $false; Description = $FallbackName; DisplayName = $null }

    if ([string]::IsNullOrWhiteSpace($Source)) {
        Write-Warning "DescriptionsPath not set - app treated as not found."
        return $notFound
    }

    try {
        if ($Source -match '^https?://') {
            # Raw hosts (GitHub, blob storage) usually serve text/plain, in which case
            # Invoke-RestMethod returns a plain string instead of parsing the JSON.
            # ConnectionTimeoutSeconds rather than the TimeoutSec alias; default is 100 s
            $response = Invoke-RestMethod -Uri $Source `
                -ConnectionTimeoutSeconds 30 -MaximumRetryCount 2 -RetryIntervalSec 3 -ErrorAction Stop
            $rawText  = $response -is [string] ? $response : ($response | ConvertTo-Json -Depth 20)
        }
        else {
            $rawText = Get-Content -Path (Resolve-Path -Path $Source).Path -Raw -Encoding UTF8 -ErrorAction Stop
        }

        $descriptions = $rawText | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not load app descriptions from '$Source': $($PSItem.Exception.Message) - app treated as not found."
        return $notFound
    }

    if ($descriptions.Count -eq 0) {
        Write-Warning "Descriptions file '$Source' contained no entries."
        return $notFound
    }

    $matchedKey = $null

    # Pass 1: exact match
    if ($descriptions.ContainsKey($AppName)) {
        $matchedKey = $AppName
    }

    # Pass 2: normalised exact match ("7Zip" -> "7-Zip")
    if (-not $matchedKey) {
        $target = Get-NormalizedKey -Value $AppName
        foreach ($key in $descriptions.Keys) {
            if ((Get-NormalizedKey -Value $key) -eq $target) { $matchedKey = $key; break }
        }
    }

    # Pass 3: normalised substring, longest key first so specific entries win
    # Guarded on length because a short name matches almost anything, and a wrong match here
    # also applies the wrong displayName override.
    if (-not $matchedKey -and $target.Length -ge 3) {
        foreach ($key in ($descriptions.Keys | Sort-Object -Property Length -Descending)) {
            $normKey = Get-NormalizedKey -Value $key
            if ($normKey.Length -ge 3 -and ($target.Contains($normKey) -or $normKey.Contains($target))) {
                Write-Verbose "Matched '$AppName' to descriptions entry '$key' by substring."
                $matchedKey = $key; break
            }
        }
    }

    if ($matchedKey) {
        $entry = Resolve-DescriptionEntry -Entry $descriptions[$matchedKey]
        return [pscustomobject]@{
            Found       = $true
            Description = [string]::IsNullOrWhiteSpace($entry.Description) ? $FallbackName : $entry.Description
            DisplayName = $entry.DisplayName
        }
    }

    Write-Warning "No description found for '$AppName' in descriptions file - app treated as not found."
    return $notFound
}

function Read-TextFileSmart {
    <#
    .SYNOPSIS
        Reads a text file and decodes it correctly regardless of source encoding.

    .DESCRIPTION
        Handles UTF-8/UTF-16 BOM and plain UTF-8. When the bytes are not valid UTF-8
        the file was produced by a legacy encoding: Mac Roman (macOS packaging) and
        Windows-1252 (Windows packaging) are both tried, and the decoding producing
        the most valid Swedish characters wins.

    .NOTES
        .NET Core does not ship code pages 1252 and 10000 by default, so the
        CodePagesEncodingProvider must be registered first.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # BOM detection
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    # The two BOM bytes are skipped explicitly. Decoding them instead yields a leading
    # U+FEFF, which makes the "(?m)^$Label" match in Get-AppInfoValue miss the very first
    # field in the file - a failure that looks impossible when the file is opened in an editor.
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)           # UTF-16 LE
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)  # UTF-16 BE
    }

    # UTF-16 without a BOM is technically valid UTF-8 (NUL bytes are legal), so it would pass
    # the strict test below and yield text with embedded NULs that every regex then misses.
    $nulIndex = [Array]::IndexOf($bytes, [byte]0)
    if ($nulIndex -ge 0 -and $nulIndex -lt 512) {
        return ($nulIndex % 2 -eq 1) ?
            [System.Text.Encoding]::Unicode.GetString($bytes) :
            [System.Text.Encoding]::BigEndianUnicode.GetString($bytes)
    }

    # Strict UTF-8 throws on invalid byte sequences, which is how we detect legacy encodings
    try {
        return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    }
    catch [System.Text.DecoderFallbackException] {
        try { [System.Text.Encoding]::RegisterProvider([System.Text.CodePagesEncodingProvider]::Instance) } catch { }

        # 1252 first so it wins ties: a file whose only non-ASCII characters fall outside the
        # scored set would otherwise become Mac Roman purely because it was tried first.
        $candidates = foreach ($codePage in 1252, 10000) {
            try { [System.Text.Encoding]::GetEncoding($codePage) } catch { }
        }
        $candidates = @($candidates)

        if ($candidates.Count -eq 0) {
            # Latin-1 maps every byte 1:1 and never throws
            return [System.Text.Encoding]::GetEncoding("ISO-8859-1").GetString($bytes)
        }

        # Wider than Swedish so other Latin diacritics do not all tie at zero
        $swedish   = [char[]]"åäöÅÄÖéèêëüúóíáàâîôçñ"
        $best      = $null
        $bestScore = -1
        foreach ($encoding in $candidates) {
            $text  = $encoding.GetString($bytes)
            # @() guards against Where-Object returning $null under StrictMode
            $score = @($text.ToCharArray() | Where-Object { $swedish -contains $_ }).Count
            if ($score -gt $bestScore) {
                $bestScore = $score
                $best      = $text
            }
        }
        return $best
    }
}

function Get-ClientCertificate {
    <#
    .SYNOPSIS
        Resolves the client certificate used for app-only authentication.

    .DESCRIPTION
        Two sources are supported, in this order:

          Thumbprint : looked up in the CurrentUser\My store. That store is the login
                       Keychain on macOS and the certificate store on Windows, so the key
                       never leaves the OS keystore. Preferred for interactive use.
          Path       : a PFX file, for environments with no usable store such as a
                       Linux-based Azure Function or a container.

        Returns $null when neither is supplied, which tells the caller to fall back to
        client secret authentication.

    .NOTES
        Connect-MSIntuneGraph takes an X509Certificate2 object rather than a thumbprint,
        so both sources converge on the same object. That is also what makes a later move
        to Key Vault a one-line addition: fetch the PFX bytes and construct the same object.
    #>
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param (
        [Parameter()][AllowEmptyString()][string]$Thumbprint,
        [Parameter()][AllowEmptyString()][string]$Path,
        [Parameter()][AllowEmptyString()][string]$Password
    )

    if ($Thumbprint -and $Path) {
        throw "Specify either a certificate thumbprint or a certificate path, not both."
    }

    if ($Thumbprint) {
        # Strip spaces and any invisible characters that survive a copy from the portal
        $normalized = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()

        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new("My", "CurrentUser")
        try {
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
            $found = $store.Certificates | Where-Object { $_.Thumbprint -eq $normalized }
        }
        finally {
            $store.Close()
        }

        $certificate = @($found) | Select-Object -First 1
        if (-not $certificate) {
            throw "No certificate with thumbprint '$normalized' in the CurrentUser store. Import the PFX first, or use -CertificatePath."
        }
        if (-not $certificate.HasPrivateKey) {
            throw "Certificate '$normalized' has no private key. Import the PFX, not just the .cer public part."
        }
        return $certificate
    }

    if ($Path) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "Certificate file '$Path' does not exist or is not a file."
        }
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -Path $Path).Path)
        $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]

        # EphemeralKeySet keeps the private key out of any on-disk keystore, but it is not
        # supported on macOS, where it throws. Fall back rather than fail there.
        try {
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $bytes, $Password, $flags::EphemeralKeySet)
        }
        catch [System.PlatformNotSupportedException] {
            Write-Verbose "EphemeralKeySet unsupported on this platform - loading with the default key set."
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $bytes, $Password, $flags::DefaultKeySet)
        }

        if (-not $certificate.HasPrivateKey) {
            throw "Certificate '$Path' has no private key. Export the PFX with the private key included."
        }
        return $certificate
    }

    return $null
}

function Get-Win32AppInventory {
    <#
    .SYNOPSIS
        Returns every Win32 app in the tenant as id/displayName/createdDateTime triples.

    .DESCRIPTION
        Uses the list endpoint and follows @odata.nextLink. Deliberately avoids
        Get-IntuneWin32App, which issues an extra request per app to fetch full details
        and triggers throttling on tenants with many apps - the list response already
        carries the only three fields needed here.
    #>
    [OutputType([pscustomobject[]])]
    param ()

    # $select keeps the payload small: only these three fields are used, and tenants with many
    # apps otherwise return the full app body for every entry. createdDateTime is inherited
    # from the mobileApp base class, unlike a derived-type property such as
    # committedContentVersion, which mobileApps (typed mobileApp) rejects with a 400.
    $uri  = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" +
            "?`$filter=isof('microsoft.graph.win32LobApp')&`$select=id,displayName,createdDateTime"
    $apps = [System.Collections.Generic.List[pscustomobject]]::new()

    while ($uri) {
        $response = Invoke-RestMethod -Uri $uri -Method Get `
            -Headers @{ Authorization = $Global:AuthenticationHeader.Authorization } `
            -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop

        foreach ($item in $response.value) { $apps.Add($item) }
        $uri = $response.PSObject.Properties.Name -contains "@odata.nextLink" ? $response.'@odata.nextLink' : $null
    }

    return ,$apps.ToArray()
}

function Select-SupersedableApp {
    <#
    .SYNOPSIS
        Picks the apps in the tenant that are earlier versions of the app just uploaded.

    .DESCRIPTION
        Matching is deliberately strict, because a false positive marks an unrelated app as
        superseded. A candidate qualifies only when its display name is exactly
        "<base> <version>" for one of the supplied name bases, the trailing version parses,
        and it is strictly lower than the new version. That rejects newer versions, other
        products sharing a prefix ("7-Zip Pro 1.0"), names without a version, and names
        where the base is merely contained ("My 7-Zip 1.0").

    .NOTES
        Two bases are normally supplied: the resolved display name and the
        "<Vendor> <Name>" fallback, so apps uploaded before a displayName override existed
        are still recognised.
    #>
    [OutputType([pscustomobject[]])]
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$NameBases,
        [Parameter(Mandatory)][string]$NewVersion,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ExcludeId,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AllApps
    )

    $newParsed = $null
    if (-not [version]::TryParse($NewVersion, [ref]$newParsed)) {
        Write-Warning "Version '$NewVersion' is not comparable - skipping supersedence to avoid superseding the wrong app."
        return ,@()
    }

    $patterns = foreach ($base in ($NameBases | Where-Object { $_ } | Select-Object -Unique)) {
        "^" + [regex]::Escape($base) + '\s+(\d+(?:\.\d+){0,3})$'
    }

    $matched = foreach ($app in $AllApps) {
        if ($app.id -eq $ExcludeId) { continue }
        foreach ($pattern in $patterns) {
            $match = [regex]::Match($app.displayName, $pattern)
            if (-not $match.Success) { continue }

            $oldParsed = $null
            if (-not [version]::TryParse($match.Groups[1].Value, [ref]$oldParsed)) {
                Write-Verbose "Skipping '$($app.displayName)': version not comparable."
                continue
            }
            if ($oldParsed -ge $newParsed) { continue }

            [pscustomobject]@{ Id = $app.id; DisplayName = $app.displayName; Version = $oldParsed }
            break
        }
    }

    # Comma operator: without it an empty result unrolls to $null and .Count fails under StrictMode
    return ,@($matched)
}

function Get-NextPatchTuesday {
    <#
    .SYNOPSIS
        Returns the next Patch Tuesday, i.e. the second Tuesday of a month, strictly
        after ReferenceDate. Returns a date with the time component at midnight.

    .NOTES
        When ReferenceDate is itself a Patch Tuesday the following month is returned,
        since "next" should not schedule a deployment for the same day.
    #>
    [OutputType([datetime])]
    param (
        [Parameter()][datetime]$ReferenceDate = (Get-Date)
    )

    $today = $ReferenceDate.Date
    foreach ($monthOffset in 0, 1) {
        $firstOfMonth = [datetime]::new($today.Year, $today.Month, 1).AddMonths($monthOffset)
        # Days from the 1st to the first Tuesday, then +7 for the second Tuesday
        $daysToTuesday = ([int][System.DayOfWeek]::Tuesday - [int]$firstOfMonth.DayOfWeek + 7) % 7
        $patchTuesday  = $firstOfMonth.AddDays($daysToTuesday + 7)
        if ($patchTuesday -gt $today) { return $patchTuesday }
    }
}

function Get-AppInfoValue {
    <#
    .SYNOPSIS
        Reads a value from ApplicationInformation.txt based on a label.
        Returns $null if the label is not present.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Label
    )
    if ($Content -match "(?m)^$Label[\s.]*:\s*(.+)$") {
        return $Matches[1].Trim()
    }
    return $null
}

function ConvertTo-MB {
    <#
    .SYNOPSIS
        Converts a disk space string ("500 MB", "2 GB") to an integer in MB.
        Returns $null when the string cannot be parsed.
    #>
    [OutputType([int])]
    param (
        [Parameter()][AllowEmptyString()][AllowNull()][string]$DiskSpaceString
    )
    if ($DiskSpaceString -match "(\d+(?:[.,]\d+)?)\s*(MB|GB|TB)") {
        $value = [double]($Matches[1] -replace ",", ".")
        $result = switch ($Matches[2]) {
            "MB" { [int]$value }
            "GB" { [int]($value * 1024) }
            "TB" { [int]($value * 1024 * 1024) }
        }
        return $result
    }
    if (-not [string]::IsNullOrWhiteSpace($DiskSpaceString)) {
        Write-Warning "Could not parse disk space '$DiskSpaceString' (expected e.g. '500 MB' or '2 GB') - no disk requirement will be set."
    }
    return $null
}

function Expand-AppPackage {
    <#
    .SYNOPSIS
        Extracts a zip file to an AppUnzip directory next to the zip file.
        An existing directory is cleared first. Returns the temp directory path.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][string]$ZipPath
    )
    $parentDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ZipPath))
    # Unique per run so parallel invocations (e.g. several Azure Function executions sharing
    # an instance filesystem) cannot delete each other's extraction mid-step
    $tempDir = Join-Path -Path $parentDir -ChildPath ("AppUnzip_{0}" -f [guid]::NewGuid().ToString("N").Substring(0, 8))

    # -WhatIf:$false so local preparation always runs; -WhatIf only gates the Intune upload
    New-Item -Path $tempDir -ItemType Directory -WhatIf:$false | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force -WhatIf:$false
    return $tempDir
}

function Get-PngBase64 {
    <#
    .SYNOPSIS
        Returns a PNG file as a base64 string, or a blank 1x1 transparent PNG
        when the file is missing or unreadable.
    #>
    [OutputType([string])]
    param (
        [Parameter()][AllowNull()][System.IO.FileInfo]$PngFile
    )

    if ($null -eq $PngFile) {
        Write-Warning "No PNG file found - using blank icon."
        return $script:BlankPngBase64
    }

    try {
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($PngFile.FullName))
    }
    catch {
        Write-Warning "Could not read PNG '$($PngFile.FullName)': $($PSItem.Exception.Message) - using blank icon."
        return $script:BlankPngBase64
    }
}

function ConvertFrom-DetectionRule {
    <#
    .SYNOPSIS
        Parses a detection rule string from ApplicationInformation.txt into
        Intune-compatible objects. Supports registry, file and MSI product code.

    .OUTPUTS
        Hashtable with two keys:
          DetectionRule : used in the "detectionRules" block (portal/UI)
          Rule          : used in the "rules" block (Graph API import)

    .NOTES
        Operator mapping:
          >=  greaterThanOrEqual   <=  lessThanOrEqual
          >   greaterThan          <   lessThan
          =   equal - treated as a version comparison when the value looks like x.y.z,
              otherwise as a string comparison (e.g. PSADT tags with value "Installed").

        Throws a descriptive error, including the raw value, when nothing matches.
    #>
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)][string]$DetectionString
    )

    $operatorMap = @{
        ">=" = "greaterThanOrEqual"
        "="  = "equal"
        "<=" = "lessThanOrEqual"
        ">"  = "greaterThan"
        "<"  = "lessThan"
    }

    # Normalise short hive abbreviations (HKLM\...) to full names (HKEY_LOCAL_MACHINE\...)
    $hiveMap = [ordered]@{
        "HKLM" = "HKEY_LOCAL_MACHINE"
        "HKCU" = "HKEY_CURRENT_USER"
        "HKCR" = "HKEY_CLASSES_ROOT"
        "HKU"  = "HKEY_USERS"
        "HKCC" = "HKEY_CURRENT_CONFIG"
    }
    foreach ($abbreviation in $hiveMap.Keys) {
        if ($DetectionString -match "^$abbreviation\\") {
            $DetectionString = $DetectionString -replace "^$abbreviation\\", "$($hiveMap[$abbreviation])\"
            break
        }
    }

    # --- Registry: HKEY_...\KeyPath\ValueName <op> value ---
    # Greedy first group splits on the LAST backslash, so spaces in both the key path
    # and the value name are handled ("...\Uninstall\FileZilla Client\DisplayVersion").
    if ($DetectionString -match "^(HKEY_.+)\\([^\\]+?)\s*(>=|=|<=|>|<)\s*(.+)$") {
        $keyPath   = $Matches[1]
        $valueName = $Matches[2].Trim()
        $operator  = $Matches[3]
        $detValue  = $Matches[4].Trim()

        $isVersion = ($operator -in ">=", "<=", ">", "<") -or
                     ($operator -eq "=" -and $detValue -match "^\d+(\.\d+){1,3}$")
        $typeValue = $isVersion ? "version" : "string"
        $mapped    = $operatorMap[$operator]

        return @{
            DetectionRule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppRegistryDetection"
                "check32BitOn64System" = $false
                "keyPath"              = $keyPath
                "valueName"            = $valueName
                "detectionType"        = $typeValue
                "operator"             = $mapped
                "detectionValue"       = $detValue
            }
            Rule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppRegistryRule"
                "ruleType"             = "detection"
                "check32BitOn64System" = $false
                "keyPath"              = $keyPath
                "valueName"            = $valueName
                "operationType"        = $typeValue
                "operator"             = $mapped
                "comparisonValue"      = $detValue
            }
        }
    }

    # --- File: path\to\file.exe <op> value ---
    if ($DetectionString -match "^(%[^%]+%\\[^<>=]+|[A-Za-z]:\\[^<>=]+)\s*(>=|=|<=|>|<)\s*(.+)$") {
        $filePath = $Matches[1].Trim()
        $operator = $Matches[2]
        $detValue = $Matches[3].Trim()

        $isVersion = ($operator -in ">=", "<=", ">", "<") -or
                     ($operator -eq "=" -and $detValue -match "^\d+(\.\d+){1,3}$")
        $typeValue = $isVersion ? "version" : "string"
        $mapped    = $operatorMap[$operator]

        $folder   = [System.IO.Path]::GetDirectoryName($filePath)
        $fileName = [System.IO.Path]::GetFileName($filePath)

        return @{
            DetectionRule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppFileSystemDetection"
                "check32BitOn64System" = $false
                "path"                 = $folder
                "fileOrFolderName"     = $fileName
                "detectionType"        = $typeValue
                "operator"             = $mapped
                "detectionValue"       = $detValue
            }
            Rule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppFileSystemRule"
                "ruleType"             = "detection"
                "check32BitOn64System" = $false
                "path"                 = $folder
                "fileOrFolderName"     = $fileName
                "operationType"        = $typeValue
                "operator"             = $mapped
                "comparisonValue"      = $detValue
            }
        }
    }

    # --- MSI product code: {GUID} ---
    if ($DetectionString -match "^\{[0-9A-Fa-f\-]{36}\}$") {
        $productCode = $DetectionString.Trim()

        return @{
            DetectionRule = [ordered]@{
                "@odata.type"            = "#microsoft.graph.win32LobAppProductCodeDetection"
                "productCode"            = $productCode
                "productVersionOperator" = "notConfigured"
                "productVersion"         = $null
            }
            Rule = [ordered]@{
                "@odata.type"            = "#microsoft.graph.win32LobAppProductCodeRule"
                "ruleType"               = "detection"
                "productCode"            = $productCode
                "productVersionOperator" = "notConfigured"
                "productVersion"         = $null
            }
        }
    }

    throw @"
Detection rule could not be parsed. Unsupported format or missing operator.
  Raw value: '$DetectionString'
  Supported formats:
    Registry : HKEY_LOCAL_MACHINE\...\KeyPath\ValueName >= 1.0   (HKLM/HKCU/HKCR/HKU/HKCC also accepted)
    File     : %ProgramFiles%\App\file.exe >= 1.0
    MSI      : {ProductCode-GUID}
"@
}

function New-IntuneDetectionRuleObject {
    <#
    .SYNOPSIS
        Builds an IntuneWin32App module detection rule object from a parsed rule.

    .DESCRIPTION
        The module exposes separate parameter sets per comparison type, each with its
        own operator and value parameter names, so the correct set is selected here
        based on the @odata.type and detectionType produced by ConvertFrom-DetectionRule.
    #>
    param (
        [Parameter(Mandatory)][hashtable]$ParsedRule
    )

    $dr = $ParsedRule.DetectionRule

    switch ($dr.'@odata.type') {

        "#microsoft.graph.win32LobAppRegistryDetection" {
            switch ($dr.detectionType) {
                "version" {
                    return New-IntuneWin32AppDetectionRuleRegistry -VersionComparison `
                        -KeyPath                   $dr.keyPath `
                        -ValueName                 $dr.valueName `
                        -Check32BitOn64System      $false `
                        -VersionComparisonOperator $dr.operator `
                        -VersionComparisonValue    $dr.detectionValue
                }
                "string" {
                    return New-IntuneWin32AppDetectionRuleRegistry -StringComparison `
                        -KeyPath                  $dr.keyPath `
                        -ValueName                $dr.valueName `
                        -Check32BitOn64System     $false `
                        -StringComparisonOperator $dr.operator `
                        -StringComparisonValue    $dr.detectionValue
                }
                default { throw "Unsupported registry detectionType: '$($dr.detectionType)'" }
            }
        }

        "#microsoft.graph.win32LobAppFileSystemDetection" {
            switch ($dr.detectionType) {
                "version" {
                    return New-IntuneWin32AppDetectionRuleFile -VersionComparison `
                        -Path                      $dr.path `
                        -FileOrFolder              $dr.fileOrFolderName `
                        -Check32BitOn64System      $false `
                        -VersionComparisonOperator $dr.operator `
                        -VersionComparisonValue    $dr.detectionValue
                }
                "string" {
                    return New-IntuneWin32AppDetectionRuleFile -StringComparison `
                        -Path                     $dr.path `
                        -FileOrFolder             $dr.fileOrFolderName `
                        -Check32BitOn64System     $false `
                        -StringComparisonOperator $dr.operator `
                        -StringComparisonValue    $dr.detectionValue
                }
                default { throw "Unsupported file detectionType: '$($dr.detectionType)'" }
            }
        }

        "#microsoft.graph.win32LobAppProductCodeDetection" {
            return New-IntuneWin32AppDetectionRuleMSI `
                -ProductCode            $dr.productCode `
                -ProductVersionOperator $dr.productVersionOperator
        }

        default { throw "Unsupported detection rule type: '$($dr.'@odata.type')'" }
    }
}

function ConvertTo-Win32AssignmentDate {
    <#
    .SYNOPSIS
        Formats a DateTime for an Intune assignment installTimeSettings value, matching the
        IntuneWin32App module.

    .DESCRIPTION
        The module stamps the local clock components with a literal Z suffix without
        converting to UTC, which is what -UseLocalTime $true is meant to preserve. The Z is
        concatenated rather than put in the format string, where it is not treated as a
        literal and would shift the result.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][datetime]$Value
    )
    return $Value.ToString("yyyy-MM-ddTHH:mm:ss.000") + "Z"
}

function Get-RingSchedule {
    <#
    .SYNOPSIS
        Computes pilot and production start/deadline times for a ring rollout.

    .DESCRIPTION
        Default schedule: the pilot ring publishes immediately (no install time settings) and
        the production ring starts ProductionDelayHours from now, with a deadline
        DeadlineOffsetHours after that start.

        PatchTuesday schedule: the pilot ring starts at the next Patch Tuesday 00:00 with the
        script's existing fixed 12:00 deadline, and the production ring starts seven days
        later at 00:00 with a deadline DeadlineOffsetHours after its start.

    .OUTPUTS
        PSCustomObject with PilotStart, PilotDeadline, ProductionStart and ProductionDeadline.
        PilotStart and PilotDeadline are $null in the default schedule.
    #>
    [OutputType([pscustomobject])]
    param (
        [Parameter()][switch]$PatchTuesday,
        [Parameter(Mandatory)][ValidateRange(1, 8760)][int]$ProductionDelayHours,
        [Parameter(Mandatory)][ValidateRange(1, 8760)][int]$DeadlineOffsetHours
    )

    if ($PatchTuesday) {
        $patch          = Get-NextPatchTuesday
        $productionStart = $patch.AddDays(7)
        return [pscustomobject]@{
            PilotStart         = $patch
            PilotDeadline      = $patch.AddHours(12)
            ProductionStart    = $productionStart
            ProductionDeadline = $productionStart.AddHours($DeadlineOffsetHours)
        }
    }

    $productionStart = (Get-Date).AddHours($ProductionDelayHours)
    return [pscustomobject]@{
        PilotStart         = $null
        PilotDeadline      = $null
        ProductionStart    = $productionStart
        ProductionDeadline = $productionStart.AddHours($DeadlineOffsetHours)
    }
}

function New-Win32AppAssignmentBody {
    <#
    .SYNOPSIS
        Builds the raw Graph body for a POST to mobileApps/{id}/assignments.

    .DESCRIPTION
        Replaces Add-IntuneWin32AppAssignmentGroup, which always sends the full
        installTimeSettings block including useLocalTime and deadlineDateTime and therefore
        cannot express a scheduled available assignment.

        installTimeSettings per intent:
          no schedule           null
          required, scheduled   useLocalTime plus whichever of startDateTime / deadlineDateTime
                                is supplied, mirroring the module's own four cases
          available, scheduled  startDateTime only; useLocalTime and deadlineDateTime are
                                rejected by Intune for available and are left out entirely,
                                not sent as null

        autoUpdateSettings is added only for an available assignment when this upload
        superseded an earlier version.
    #>
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param (
        [Parameter(Mandatory)][ValidateSet("required", "available", "uninstall")][string]$Intent,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$Notification,
        [Parameter(Mandatory)][bool]$UseLocalTime,
        [Parameter()][Nullable[datetime]]$AvailableTime,
        [Parameter()][Nullable[datetime]]$DeadlineTime,
        [Parameter()][switch]$EnableAutoUpdate
    )

    $settings = [ordered]@{
        "@odata.type"                  = "#microsoft.graph.win32LobAppAssignmentSettings"
        "notifications"                = $Notification
        "restartSettings"              = $null
        "deliveryOptimizationPriority" = "notConfigured"
        "installTimeSettings"          = $null
    }

    if ($Intent -eq "available") {
        # Available honours a start time only; deadline and useLocalTime are rejected by Intune
        if ($AvailableTime) {
            $settings["installTimeSettings"] = [ordered]@{
                "startDateTime" = ConvertTo-Win32AssignmentDate -Value $AvailableTime
            }
        }
    }
    elseif ($AvailableTime -and $DeadlineTime) {
        $settings["installTimeSettings"] = [ordered]@{
            "useLocalTime"     = $UseLocalTime
            "startDateTime"    = ConvertTo-Win32AssignmentDate -Value $AvailableTime
            "deadlineDateTime" = ConvertTo-Win32AssignmentDate -Value $DeadlineTime
        }
    }
    elseif ($AvailableTime) {
        # Mirrors the module: a start time without a deadline still carries a null deadline key
        $settings["installTimeSettings"] = [ordered]@{
            "useLocalTime"     = $UseLocalTime
            "startDateTime"    = ConvertTo-Win32AssignmentDate -Value $AvailableTime
            "deadlineDateTime" = $null
        }
    }
    elseif ($DeadlineTime) {
        $settings["installTimeSettings"] = [ordered]@{
            "useLocalTime"     = $UseLocalTime
            "startDateTime"    = $null
            "deadlineDateTime" = ConvertTo-Win32AssignmentDate -Value $DeadlineTime
        }
    }

    if ($EnableAutoUpdate -and $Intent -eq "available") {
        $settings["autoUpdateSettings"] = [ordered]@{
            "@odata.type"                   = "#microsoft.graph.win32LobAppAutoUpdateSettings"
            "autoUpdateSupersededAppsState" = "enabled"
        }
    }

    return [ordered]@{
        "@odata.type" = "#microsoft.graph.mobileAppAssignment"
        "intent"      = $Intent
        "source"      = "direct"
        "target"      = [ordered]@{
            "@odata.type"                                = "#microsoft.graph.groupAssignmentTarget"
            "deviceAndAppManagementAssignmentFilterId"   = $null
            "deviceAndAppManagementAssignmentFilterType" = "none"
            "groupId"                                    = $GroupId
        }
        "settings"    = $settings
    }
}

function Get-GraphErrorMessage {
    <#
    .SYNOPSIS
        Returns the most useful text from a failed Graph request.

    .DESCRIPTION
        Invoke-RestMethod puts only a generic status line in the exception message
        ("Response status code does not indicate success: 400 (Bad Request).") and the reason
        Graph gave in ErrorDetails. A Graph-shaped JSON body is reduced to
        "<code>: <message> (request-id <id>)"; any other body is returned as is; without a
        body the exception message is returned.
    #>
    [OutputType([string])]
    param (
        [Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $details = $ErrorRecord.ErrorDetails
    if (-not ($details -and $details.Message)) {
        return $ErrorRecord.Exception.Message
    }

    try {
        $body      = $details.Message | ConvertFrom-Json -ErrorAction Stop
        $errorProp = $body.PSObject.Properties["error"]
        if ($errorProp -and $errorProp.Value) {
            $graphError = $errorProp.Value
            $code       = $graphError.PSObject.Properties["code"]    ? [string]$graphError.code    : ""
            $message    = $graphError.PSObject.Properties["message"] ? [string]$graphError.message : ""
            $requestId  = ""
            $innerProp  = $graphError.PSObject.Properties["innerError"]
            if ($innerProp -and $innerProp.Value -and $innerProp.Value.PSObject.Properties["request-id"]) {
                $requestId = [string]$innerProp.Value.'request-id'
            }
            # ${code} and not $code: a colon straight after a variable name is parsed as a
            # scope qualifier and the string no longer parses
            $text = $code ? "${code}: $message" : $message
            if ($requestId) { $text += " (request-id $requestId)" }
            if ($text) { return $text }
        }
    }
    catch {
        Write-Verbose "Graph error body is not JSON; returning it unparsed."
    }
    return $details.Message
}

function Invoke-Win32AppAssignment {
    <#
    .SYNOPSIS
        POSTs one assignment to Graph, reporting success as a boolean and warning - never
        throwing - on failure, because the app already exists in Intune by this point.

    .DESCRIPTION
        For an available assignment that requested auto-update of superseded apps, the created
        assignment is read back: the property name differs between Graph beta and v1.0 and a
        wrong name is accepted and ignored silently, so reading it back is the only way to
        know it took.

    .OUTPUTS
        [bool] - $true when the assignment was created, $false when the POST failed. An
        auto-update setting that did not stick produces a warning but still returns $true,
        since the assignment itself was created.
    #>
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter()][AllowEmptyString()][string]$RingLabel = "",
        [Parameter(Mandatory)][ValidateSet("required", "available", "uninstall")][string]$Intent,
        [Parameter(Mandatory)][string]$Notification,
        [Parameter(Mandatory)][bool]$UseLocalTime,
        [Parameter()][Nullable[datetime]]$AvailableTime,
        [Parameter()][Nullable[datetime]]$DeadlineTime,
        [Parameter()][switch]$EnableAutoUpdate
    )

    $where   = $RingLabel ? " ($RingLabel ring)" : ""
    $headers = @{ Authorization = $Global:AuthenticationHeader.Authorization; "Content-Type" = "application/json" }

    $body = New-Win32AppAssignmentBody -Intent $Intent -GroupId $GroupId -Notification $Notification `
        -UseLocalTime $UseLocalTime -AvailableTime $AvailableTime -DeadlineTime $DeadlineTime `
        -EnableAutoUpdate:$EnableAutoUpdate

    try {
        $response = Invoke-RestMethod -Method Post `
            -Uri  "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/assignments" `
            -Headers $headers -Body ($body | ConvertTo-Json -Depth 20) `
            -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop
    }
    catch {
        # The raw REST path surfaces a real exception where the module only warned; make sure
        # the Graph message in clear text reaches the operator.
        $graphMessage = Get-GraphErrorMessage -ErrorRecord $PSItem
        Write-Warning "Assignment to group $GroupId$where failed: $graphMessage"
        Write-Warning "Assign the app to $GroupId manually in the Intune portal."
        return $false
    }

    $availableText = $AvailableTime ? (ConvertTo-Win32AssignmentDate -Value $AvailableTime) : "immediately"
    $deadlineText  = $DeadlineTime  ? (ConvertTo-Win32AssignmentDate -Value $DeadlineTime)  : "none"
    Write-Host "Assigned to group $GroupId$where as '$Intent'.  Available: $availableText   Deadline: $deadlineText" -ForegroundColor Green

    if (-not ($EnableAutoUpdate -and $Intent -eq "available")) {
        return $true
    }

    # Verify the auto-update setting actually took
    $assignmentId    = ($response -and $response.PSObject.Properties["id"]) ? [string]$response.id : ""
    $autoUpdateState = ""
    if ($assignmentId) {
        try {
            $check = Invoke-RestMethod -Method Get `
                -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$AppId/assignments/$assignmentId" `
                -Headers @{ Authorization = $Global:AuthenticationHeader.Authorization } `
                -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop

            $settingsProp = $check.PSObject.Properties["settings"]
            if ($settingsProp -and $settingsProp.Value) {
                $autoProp = $settingsProp.Value.PSObject.Properties["autoUpdateSettings"]
                if ($autoProp -and $autoProp.Value) {
                    $stateProp = $autoProp.Value.PSObject.Properties["autoUpdateSupersededAppsState"]
                    if ($stateProp) { $autoUpdateState = [string]$stateProp.Value }
                }
            }
        }
        catch {
            Write-Warning "Could not read assignment $assignmentId back to verify auto-update: $(Get-GraphErrorMessage -ErrorRecord $PSItem)"
        }
    }

    if ($autoUpdateState -eq "enabled") {
        Write-Host "  Auto-update of superseded apps: enabled (verified)." -ForegroundColor Green
    }
    else {
        Write-Warning "Auto-update of superseded apps was requested but is not set on the assignment. Graph beta expects 'autoUpdateSupersededAppsState', Graph v1.0 expects 'autoUpdateSupersededApps'; if the schema changed the script is sending the wrong name. Turn on 'Automatically update' for this assignment manually in the Intune portal."
    }
    return $true
}

function Select-SupersedenceTarget {
    <#
    .SYNOPSIS
        Picks the single earlier-version app to keep and supersede against.

    .DESCRIPTION
        The kept app is the highest version that still has at least one assignment. A
        half-finished earlier run can leave a higher version with no assignments, and keeping
        that one would supersede - and later retire - the version that is actually deployed.
        Ties on version are broken by createdDateTime. When no candidate has any assignment
        the highest version is kept and a warning is written, because the choice was made
        without assignment evidence.

        The decision fails closed: when the assignments of any candidate cannot be read, $null
        is returned and supersedence and retirement are skipped for the run. Counting an
        unreadable candidate as unassigned could keep the wrong version and retire the one
        actually deployed.

    .NOTES
        createdDateTime comes from the inventory; only the assignment count is fetched per
        candidate.
    #>
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Candidate,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Inventory
    )

    $authHeader = @{ Authorization = $Global:AuthenticationHeader.Authorization }

    $createdById = @{}
    foreach ($inventoryApp in $Inventory) {
        $idProp      = $inventoryApp.PSObject.Properties["id"]
        $createdProp = $inventoryApp.PSObject.Properties["createdDateTime"]
        if ($idProp -and $createdProp -and $createdProp.Value) {
            $createdById[[string]$idProp.Value] = [datetime]$createdProp.Value
        }
    }

    $failedLookups = 0
    $enriched = foreach ($item in $Candidate) {
        $assignmentCount = 0
        try {
            $assignmentResponse = Invoke-RestMethod -Method Get `
                -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($item.Id)/assignments" `
                -Headers $authHeader -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop
            if ($assignmentResponse.PSObject.Properties["value"]) {
                $assignmentCount = @($assignmentResponse.value).Count
            }
        }
        catch {
            $failedLookups++
            Write-Warning "Could not read the assignments of '$($item.DisplayName)' ($($item.Id)): $(Get-GraphErrorMessage -ErrorRecord $PSItem)"
            continue
        }

        $itemId = [string]$item.Id
        [pscustomobject]@{
            Id              = $item.Id
            DisplayName     = $item.DisplayName
            Version         = $item.Version
            AssignmentCount = $assignmentCount
            CreatedDateTime = $createdById.ContainsKey($itemId) ? $createdById[$itemId] : [datetime]::MinValue
        }
    }

    if ($failedLookups -gt 0) {
        Write-Warning "The keep decision needs the assignment state of every earlier version, and $failedLookups lookup(s) failed. Supersedence and retirement are skipped for this run so the deployed version cannot be retired by mistake."
        return $null
    }

    $enriched = @($enriched)
    if ($enriched.Count -eq 0) { return $null }

    $withAssignment = @($enriched | Where-Object { $_.AssignmentCount -gt 0 })
    if ($withAssignment.Count -gt 0) {
        return $withAssignment | Sort-Object -Property Version, CreatedDateTime -Descending | Select-Object -First 1
    }

    $fallback = $enriched | Sort-Object -Property Version, CreatedDateTime -Descending | Select-Object -First 1
    Write-Warning "None of the earlier versions has an assignment; keeping '$($fallback.DisplayName)' (highest version) without assignment evidence."
    return $fallback
}

function Remove-KeptAppSupersedence {
    <#
    .SYNOPSIS
        Removes the kept version's supersedence relations that point at versions being retired.

    .DESCRIPTION
        Relations are stored on the superseding app, so clearing a retired app's own relations
        does not reach the kept app's relation to it. Left in place, the most recently retired
        version stays superseded by the kept one until that one is itself retired at the next
        release.

        Only child supersedence relations whose target is being retired are removed. Any other
        supersedence on the kept app - a manually configured replacement of an unrelated
        product, say - is resubmitted unchanged, and the module preserves dependencies.

    .OUTPUTS
        [bool] - $true when nothing needed changing or the change went through.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)][string]$KeptAppId,
        [Parameter(Mandatory)][string[]]$RetiredAppId
    )

    try {
        $response = Invoke-RestMethod -Method Get `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$KeptAppId/relationships" `
            -Headers @{ Authorization = $Global:AuthenticationHeader.Authorization } `
            -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not read the relationships of kept app ${KeptAppId}: $(Get-GraphErrorMessage -ErrorRecord $PSItem)"
        return $false
    }

    # The whole supersedence set is replaced on write, so a partial page must never be the
    # basis of one. A supersedence graph caps at 11 nodes, so paging should not occur; the
    # guard keeps a surprise from turning into lost relations.
    if ($response.PSObject.Properties["@odata.nextLink"]) {
        Write-Warning "The relationships of kept app $KeptAppId came back paged; not rewriting them from a partial list."
        return $false
    }

    $valueProp = $response.PSObject.Properties["value"]
    $entries   = $valueProp ? @($valueProp.Value) : @()
    $targetIdOf = { param($entry) $prop = $entry.PSObject.Properties["targetId"]; $prop ? [string]$prop.Value : "" }

    # Only the kept app's own supersedences. Entries with targetType 'parent' are apps that
    # supersede the kept app - the new upload among them - and are stored on those apps.
    $ownSupersedence = @($entries | Where-Object {
        $typeProp       = $_.PSObject.Properties["@odata.type"]
        $targetTypeProp = $_.PSObject.Properties["targetType"]
        $typeProp -and $typeProp.Value -eq "#microsoft.graph.mobileAppSupersedence" -and
            $targetTypeProp -and $targetTypeProp.Value -eq "child"
    })

    $toRetired = @($ownSupersedence | Where-Object { (& $targetIdOf $_) -in $RetiredAppId })
    if ($toRetired.Count -eq 0) {
        Write-Verbose "Kept app $KeptAppId has no supersedence pointing at the versions being retired."
        return $true
    }

    $remaining = @($ownSupersedence | Where-Object { (& $targetIdOf $_) -notin $RetiredAppId })

    # Never guess a supersedence type: a wrong one would silently turn an update into an
    # uninstall-first replacement, or the reverse
    $untyped = @($remaining | Where-Object {
        $prop = $_.PSObject.Properties["supersedenceType"]
        -not ($prop -and $prop.Value)
    })
    if ($untyped.Count -gt 0) {
        Write-Warning "A supersedence relation on kept app $KeptAppId has no supersedenceType; not rewriting the set."
        return $false
    }

    $rebuilt = @(foreach ($entry in $remaining) {
        [ordered]@{
            "@odata.type"      = "#microsoft.graph.mobileAppSupersedence"
            "supersedenceType" = [string]$entry.PSObject.Properties["supersedenceType"].Value
            "targetId"         = & $targetIdOf $entry
        }
    })

    if (-not $PSCmdlet.ShouldProcess($KeptAppId, "Remove supersedence to retired versions")) {
        return $true
    }

    # foreach ($x in 1) absorbs the module's `break` on a Begin-block validation failure;
    # -WarningVariable captures both that and Graph errors
    $writeWarnings = $null
    foreach ($breakGuard in 1) {
        if ($rebuilt.Count -gt 0) {
            Add-IntuneWin32AppSupersedence -ID $KeptAppId -Supersedence $rebuilt -WarningVariable writeWarnings | Out-Null
        }
        else {
            Remove-IntuneWin32AppSupersedence -ID $KeptAppId -WarningVariable writeWarnings | Out-Null
        }
    }
    return -not $writeWarnings
}

#endregion Functions

#region Step 1 - Validate credentials and assignment input

# Fail before doing any work if credentials are missing
$missingCredentials = @()
if (-not $TenantID) { $missingCredentials += "TenantID (or env:INTUNE_TENANT_ID)" }
if (-not $ClientID) { $missingCredentials += "ClientID (or env:INTUNE_CLIENT_ID)" }
# Either a certificate or a secret, not necessarily both
if (-not $ClientSecret -and -not $CertificateThumbprint -and -not $CertificatePath) {
    $missingCredentials += "ClientSecret, CertificateThumbprint or CertificatePath"
}

if ($missingCredentials.Count -gt 0) {
    throw "Missing required authentication credentials: $($missingCredentials -join ', ')"
}

# Assignment input is validated up front so a misconfiguration fails before extraction (§7.2)

# GUID check for every supplied group id, same pattern as the original AssignmentGroupId check
foreach ($groupIdField in @(
        @{ Name = "AssignmentGroupId"; Value = $AssignmentGroupId }
        @{ Name = "PilotGroupId";      Value = $PilotGroupId }
        @{ Name = "ProductionGroupId"; Value = $ProductionGroupId }
    )) {
    if ($groupIdField.Value) {
        $parsedGuid = [guid]::Empty
        if (-not [guid]::TryParse($groupIdField.Value, [ref]$parsedGuid)) {
            throw "$($groupIdField.Name) '$($groupIdField.Value)' is not a valid GUID. Use the Entra group's object ID, not its display name."
        }
    }
}

# Ring rollout is active only when both ring groups are resolved (parameter or customer file)
$ringMode        = [bool]$PilotGroupId -and [bool]$ProductionGroupId
$singleGroupMode = [bool]$AssignmentGroupId

# A single ring group is a misconfiguration, not a silent downgrade to single-group assignment
if ([bool]$PilotGroupId -ne [bool]$ProductionGroupId) {
    $missingRingGroup = $PilotGroupId ? "ProductionGroupId" : "PilotGroupId"
    throw "Ring rollout needs both PilotGroupId and ProductionGroupId; $missingRingGroup is missing. Set both, or use -AssignmentGroupId for a single-group assignment."
}

if ($ringMode -and $singleGroupMode) {
    throw "Ring rollout (PilotGroupId/ProductionGroupId) and single-group assignment (-AssignmentGroupId or env:INTUNE_ASSIGNMENT_GROUP_ID) cannot both be configured. Use one or the other."
}
if ($ringMode -and $AssignmentIntent -eq "uninstall") {
    throw "Ring rollout cannot be combined with -AssignmentIntent uninstall; the ring schedule and supersedence both assume an installation."
}
if ($ringMode -and ($AvailableTime -or $DeadlineTime)) {
    throw "Ring rollout derives its own schedule; -AvailableTime and -DeadlineTime belong to single-group mode."
}
if ($RetireSuperseded -and -not $ringMode -and -not $singleGroupMode) {
    throw "-RetireSuperseded needs an active assignment (a ring rollout or -AssignmentGroupId); retirement can never meet its preconditions without one."
}

# Schedule parameters without any group is a configuration error, not a silent skip
$assignmentParameters = @("AssignmentIntent", "AssignmentNotification", "AvailableTime", "DeadlineTime", "UseLocalTime", "PatchTuesday")
$assignmentRequested  = @($assignmentParameters | Where-Object { $PSBoundParameters.ContainsKey($_) }).Count -gt 0

if ($assignmentRequested -and -not $singleGroupMode -and -not $ringMode) {
    throw "Assignment parameters were supplied but no group was specified. Provide -AssignmentGroupId, set env:INTUNE_ASSIGNMENT_GROUP_ID, or configure PilotGroupId and ProductionGroupId."
}

if ($singleGroupMode) {
    # -PatchTuesday derives both times, so it cannot be combined with explicit ones
    if ($PatchTuesday) {
        if ($AvailableTime -or $DeadlineTime) {
            throw "-PatchTuesday cannot be combined with -AvailableTime or -DeadlineTime. Use either the switch or explicit times."
        }
        $nextPatchTuesday = Get-NextPatchTuesday
        $AvailableTime    = $nextPatchTuesday                # 00:00 on the day
        $DeadlineTime     = $nextPatchTuesday.AddHours(12)   # 12:00 on the day
        Write-Verbose "-PatchTuesday: scheduling on $($nextPatchTuesday.ToString('yyyy-MM-dd')), available 00:00, deadline 12:00."
    }

    # Parity with 2.7.1 on the required/uninstall path: these mirrored module quirks where a
    # future available time without a deadline, or a past deadline alone, was silently skipped.
    # The available path had its own up-front rejection removed in 3.0.0 (the raw REST body
    # sends startDateTime only for available, which Intune accepts), so these no longer apply
    # to it. AddDays(-1) mirrors the module's own idea of "future".
    if ($AssignmentIntent -ne "available") {
        if ($AvailableTime -and -not $DeadlineTime -and $AvailableTime -gt (Get-Date).AddDays(-1)) {
            throw "-AvailableTime is in the future but no -DeadlineTime was supplied. Supply both for a required rollout, or use -AssignmentIntent available."
        }
        if ($AvailableTime -and $DeadlineTime -and $DeadlineTime -le $AvailableTime) {
            throw "-DeadlineTime ($DeadlineTime) must be later than -AvailableTime ($AvailableTime)."
        }
        if ($DeadlineTime -and -not $AvailableTime -and $DeadlineTime -lt (Get-Date)) {
            throw "-DeadlineTime ($DeadlineTime) is in the past. Supply a future deadline, or add -AvailableTime."
        }
    }
}

#endregion

#region Step 2 - Extract zip

Write-Host "`n=== Step 2: Extraction ===" -ForegroundColor Cyan

try {
    $tempDir = Expand-AppPackage -ZipPath $AppPath
    Write-Host "Extracted to: $tempDir"
}
catch {
    throw "Error during extraction: $($PSItem.Exception.Message)"
}

#endregion

#region Step 3 - Locate extracted directory and files

Write-Host "`n=== Step 3: Files ===" -ForegroundColor Cyan

try {
    # Skip macOS metadata folders (__MACOSX) and prefer the directory that actually
    # contains ApplicationInformation.txt
    $candidateDirs = @(Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -ne "__MACOSX" })
    $unzippedDir   = $candidateDirs |
        Where-Object { Test-Path -Path (Join-Path $_.FullName "ApplicationInformation.txt") } |
        Select-Object -First 1

    # Zips built without a wrapping folder put the files straight in the root
    if (-not $unzippedDir -and (Test-Path -Path (Join-Path $tempDir "ApplicationInformation.txt"))) {
        $unzippedDir = Get-Item -Path $tempDir
    }

    $unzippedDir ??= ($candidateDirs | Select-Object -First 1)
    if (-not $unzippedDir) {
        throw "No application directory found in $tempDir"
    }
    Write-Host "Extracted directory: $($unzippedDir.FullName)"

    $appInfoFile   = Get-ChildItem -Path $unzippedDir.FullName -Filter "ApplicationInformation.txt" | Select-Object -First 1
    $intunewinFile = Get-ChildItem -Path $unzippedDir.FullName -Filter "*.intunewin" | Select-Object -First 1
    $pngFile       = Get-ChildItem -Path $unzippedDir.FullName -Filter "*.png" | Select-Object -First 1

    if (-not $appInfoFile)   { throw "ApplicationInformation.txt not found in $($unzippedDir.FullName)" }
    if (-not $intunewinFile) { throw "No .intunewin file found in $($unzippedDir.FullName)" }

    Write-Host "ApplicationInformation : $($appInfoFile.Name)"
    Write-Host "Intunewin file         : $($intunewinFile.Name)"
    if ($pngFile) { Write-Host "PNG file               : $($pngFile.Name)" }
    else          { Write-Warning "No PNG file found - a blank icon will be used." }
}
catch {
    throw "Error while reading files: $($PSItem.Exception.Message)"
}

#endregion

#region Step 4 - Read and parse ApplicationInformation.txt

Write-Host "`n=== Step 4: ApplicationInformation.txt ===" -ForegroundColor Cyan

try {
    $appInfo = Read-TextFileSmart -Path $appInfoFile.FullName

    $vendor       = Get-AppInfoValue -Content $appInfo -Label "Application - Vendor"
    $appName      = Get-AppInfoValue -Content $appInfo -Label "Application - Name"
    $appVersion   = Get-AppInfoValue -Content $appInfo -Label "Application - Version"
    $installCmd   = Get-AppInfoValue -Content $appInfo -Label "Install command"
    $uninstallCmd = Get-AppInfoValue -Content $appInfo -Label "Uninstall command"
    $diskSpace    = Get-AppInfoValue -Content $appInfo -Label "Estimated Disk Space"

    # Detection method may be declared as REG, MSI or FILE - use whichever is present
    $detectionMethod = $null
    foreach ($detectionLabel in "REG", "MSI", "FILE") {
        $detectionMethod = Get-AppInfoValue -Content $appInfo -Label "DetectionMethod\.\($detectionLabel\)"
        if ($detectionMethod) { break }
    }

    $missingFields = @()
    if (-not $vendor)          { $missingFields += "Application - Vendor" }
    if (-not $appName)         { $missingFields += "Application - Name" }
    if (-not $appVersion)      { $missingFields += "Application - Version" }
    if (-not $installCmd)      { $missingFields += "Install command" }
    if (-not $uninstallCmd)    { $missingFields += "Uninstall command" }
    if (-not $detectionMethod) { $missingFields += "DetectionMethod.(REG/MSI/FILE)" }

    if ($missingFields.Count -gt 0) {
        throw "Missing required fields in ApplicationInformation.txt: $($missingFields -join ', ')"
    }

    Write-Host "Vendor   : $vendor"
    Write-Host "Name     : $appName"
    Write-Host "Version  : $appVersion"
    Write-Host "Install  : $installCmd"
    Write-Host "Uninstall: $uninstallCmd"
    Write-Host "Detection: $detectionMethod"
    Write-Host "Disk     : $($diskSpace ?? '(not specified)')"
}
catch {
    throw "Error while parsing ApplicationInformation.txt: $($PSItem.Exception.Message)"
}

#endregion

#region Step 5 - Build and export JSON

Write-Host "`n=== Step 5: Build JSON ===" -ForegroundColor Cyan

try {
    $today       = Get-Date -Format "yyyy-MM-dd"
    $todayUtc    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ")
    $diskSpaceMB = ConvertTo-MB -DiskSpaceString $diskSpace
    $pngBase64   = Get-PngBase64 -PngFile $pngFile

    # Default name is "<Vendor> <Name> <Version>"; a displayName in the descriptions file
    # replaces the vendor/name part, e.g. "IgorPavlov 7Zip 26.02" -> "7-Zip 26.02"
    $defaultDisplayName = "$vendor $appName $appVersion"
    $descResult         = Get-AppDescription -AppName $appName -FallbackName $defaultDisplayName -Source $DescriptionsPath
    $appDescription     = $descResult.Description
    $displayName        = $descResult.DisplayName ? "$($descResult.DisplayName) $appVersion" : $defaultDisplayName
    # notes: "Base Application <date>" when the app is known in IntuneAppDescriptions.json, otherwise just the date
    $appNotes       = $descResult.Found ? "Base Application $today" : $today

    $parsed = ConvertFrom-DetectionRule -DetectionString $detectionMethod

    $detectionOdataType = $parsed.DetectionRule.'@odata.type' -replace '#microsoft\.graph\.win32LobApp', ''
    # Registry/file rules expose detectionType, MSI rules expose productVersionOperator
    $detectionSubType = if ($parsed.DetectionRule.Contains("detectionType")) {
        $parsed.DetectionRule.detectionType
    }
    elseif ($parsed.DetectionRule.Contains("productVersionOperator")) {
        $parsed.DetectionRule.productVersionOperator
    }
    else { "n/a" }

    Write-Host "Detection type : $detectionOdataType"
    Write-Host "Detection dtype: $detectionSubType"
    Write-Host "Description    : $($descResult.Found ? 'found in descriptions file' : 'not found - using display name')"
    Write-Host "Display name   : $displayName$($descResult.DisplayName ? " (overridden from descriptions file)" : '')"
    Write-Host "Requirements   : $Architecture / $MinimumWindowsRelease / $($diskSpaceMB ? "$diskSpaceMB MB disk" : 'no disk requirement')"

    $appJson = [ordered]@{
        "@odata.context"          = "https://graph.microsoft.com/beta/`$metadata#deviceAppManagement/mobileApps(categories(),assignments())/`$entity"
        "@odata.type"             = "#microsoft.graph.win32LobApp"
        "id"                      = [System.Guid]::NewGuid().ToString()
        "displayName"             = $displayName
        "description"             = $appDescription
        "publisher"               = $vendor
        "createdDateTime"         = $todayUtc
        "lastModifiedDateTime"    = $todayUtc
        "isFeatured"              = $false
        "privacyInformationUrl"   = $null
        "informationUrl"          = $null
        "owner"                   = $Owner
        "developer"               = ""
        "notes"                   = $appNotes
        "uploadState"             = 1
        "publishingState"         = "published"
        "isAssigned"              = $true
        "roleScopeTagIds"         = @("0")
        "dependentAppCount"       = 0
        "supersedingAppCount"     = 0
        "supersededAppCount"      = 0
        "committedContentVersion" = "1"
        "fileName"                = $intunewinFile.Name
        "size"                    = $intunewinFile.Length
        "installCommandLine"      = $installCmd
        "uninstallCommandLine"    = $uninstallCmd
        "applicableArchitectures" = "none"
        "allowedArchitectures"    = $architectureMap[$Architecture]
        "minimumFreeDiskSpaceInMB"       = $diskSpaceMB
        "minimumMemoryInMB"              = $null
        "minimumNumberOfProcessors"      = $null
        "minimumCpuSpeedInMHz"           = $null
        "msiInformation"                 = $null
        "setupFilePath"                  = "${appName}_${appVersion}.txt"
        "minimumSupportedWindowsRelease" = $windowsReleaseMap[$MinimumWindowsRelease]
        "displayVersion"          = $appVersion
        "allowAvailableUninstall" = $true
        "activeInstallScript"     = $null
        "activeUninstallScript"   = $null
        "largeIcon"               = [ordered]@{
            "type"  = "image/png"
            "value" = $pngBase64
        }
        "minimumSupportedOperatingSystem" = [ordered]@{
            "v8_0"     = $false
            "v8_1"     = $false
            "v10_0"    = $false
            "v10_1607" = $false
            "v10_1703" = $false
            "v10_1709" = $false
            "v10_1803" = $false
            "v10_1809" = $false
            "v10_1903" = $false
            "v10_1909" = $false
            "v10_2004" = $false
            "v10_2H20" = $false
            "v10_21H1" = $false
        }
        "detectionRules"    = @($parsed.DetectionRule)
        "requirementRules"  = @()
        "rules"             = @($parsed.Rule)
        "installExperience" = [ordered]@{
            "runAsAccount"          = "system"
            "maxRunTimeInMinutes"   = 60
            "deviceRestartBehavior" = "basedOnReturnCode"
        }
        "returnCodes" = $script:Win32AppReturnCodes
        "categories"  = @()
        "assignments" = @()
    }

    # UTF-16 LE matches the Intune Graph API export format
    # displayName can come from the descriptions file and may contain characters that are
    # illegal in a filename on either macOS or Windows
    $safeFileName = ($displayName -replace '[\\/:*?"<>|]', '_') + ".json"
    $outputPath   = Join-Path -Path $unzippedDir.FullName -ChildPath $safeFileName
    [System.IO.File]::WriteAllText($outputPath, ($appJson | ConvertTo-Json -Depth 20), [System.Text.Encoding]::Unicode)
    Write-Host "JSON saved to: $outputPath" -ForegroundColor Green
}
catch {
    throw "Error while generating JSON: $($PSItem.Exception.Message)"
}

#endregion

#region Step 6 - Upload to Intune

Write-Host "`n=== Step 6: Upload to Intune ===" -ForegroundColor Cyan

$appId        = $null
$appInventory = @()

# ShouldProcess returns $false under -WhatIf, which skips authentication as well as the upload
if (-not $PSCmdlet.ShouldProcess($displayName, "Upload Win32 app to Intune")) {
    Write-Host "WhatIf: skipping Graph authentication and Intune upload." -ForegroundColor Yellow
}
else {
    try {
        $moduleSplat = @{ Name = "IntuneWin32App" }
        if ($IntuneWin32AppVersion) { $moduleSplat["RequiredVersion"] = $IntuneWin32AppVersion }

        if (-not (Get-Module -ListAvailable @moduleSplat)) {
            Write-Host "Installing IntuneWin32App module$($IntuneWin32AppVersion ? " $IntuneWin32AppVersion" : '')..."
            # -Repository PSGallery so a higher-priority registered source cannot supply the module
            Install-Module @moduleSplat -Repository PSGallery -Scope CurrentUser -Force
        }
        Import-Module @moduleSplat

        $clientCertificate = Get-ClientCertificate -Thumbprint $CertificateThumbprint `
                                                   -Path       $CertificatePath `
                                                   -Password   $CertificatePassword

        if ($clientCertificate) {
            Connect-MSIntuneGraph -TenantID $TenantID -ClientID $ClientID -ClientCert $clientCertificate | Out-Null
            Write-Host "Authenticated to Microsoft Graph using certificate $($clientCertificate.Thumbprint)"
        }
        else {
            Connect-MSIntuneGraph -TenantID $TenantID -ClientID $ClientID -ClientSecret $ClientSecret | Out-Null
            Write-Host "Authenticated to Microsoft Graph using client secret"
        }
    }
    catch {
        throw "Authentication failed: $($PSItem.Exception.Message)"
    }

    # Inventory once, before the upload, and reuse it for the duplicate check here and for
    # supersedence in Step 8. It is not queried again later.
    try {
        $appInventory = Get-Win32AppInventory
    }
    catch {
        throw "Could not read the existing Win32 app inventory from Intune: $(Get-GraphErrorMessage -ErrorRecord $PSItem)"
    }

    # Refuse to upload the same package twice. Before 3.0.0 this created a second app in Intune;
    # with Step 10 now able to retire earlier versions, a rerun could retire a working one. The
    # check sits before the upload, so it throws without leaving anything behind. -WhatIf never
    # reaches here because ShouldProcess short-circuits authentication.
    $candidateNames   = @($displayName, $defaultDisplayName) | Select-Object -Unique
    $existingDuplicate = $null
    foreach ($inventoryApp in $appInventory) {
        if (-not $inventoryApp.PSObject.Properties["displayName"]) { continue }
        foreach ($candidateName in $candidateNames) {
            if ([string]::Equals($candidateName, [string]$inventoryApp.displayName, [System.StringComparison]::OrdinalIgnoreCase)) {
                $existingDuplicate = $inventoryApp
                break
            }
        }
        if ($existingDuplicate) { break }
    }
    if ($existingDuplicate) {
        $existingId = $existingDuplicate.PSObject.Properties["id"] ? $existingDuplicate.id : "unknown"
        throw "An app named '$($existingDuplicate.displayName)' already exists in the tenant (id $existingId). The script refuses to upload the same package twice. Remove or rename the existing app, or raise the version in ApplicationInformation.txt."
    }

    try {
        # New-IntuneWin32AppIcon needs a real file path, so a blank PNG is written to disk when needed
        $iconPath = if ($pngFile) {
            $pngFile.FullName
        }
        else {
            $blankPngPath = Join-Path -Path $tempDir -ChildPath "blank.png"
            [System.IO.File]::WriteAllBytes($blankPngPath, [System.Convert]::FromBase64String($script:BlankPngBase64))
            $blankPngPath
        }

        # Without an explicit requirement rule the module falls back to hardcoded defaults
        # ("x64,x86" and minimum release "2H20" = Windows 10 20H2) and silently drops
        # minimumFreeDiskSpaceInMB, so it must always be supplied.
        $requirementSplat = @{
            Architecture                   = $Architecture
            MinimumSupportedWindowsRelease = $MinimumWindowsRelease
        }
        # ValidateNotNullOrEmpty on the module parameter rejects 0/null, so only add when set
        if ($diskSpaceMB) {
            $requirementSplat["MinimumFreeDiskSpaceInMB"] = $diskSpaceMB
        }
        $requirementRule = New-IntuneWin32AppRequirementRule @requirementSplat

        # -ReturnCode is deliberately omitted: the module always adds its own default set
        # (0/1707 success, 3010 softReboot, 1641 hardReboot, 1618 retry) and appends anything
        # passed in without deduplicating, which produced duplicate entries. 1641 is corrected
        # to softReboot with a PATCH below instead.
        $win32App = Add-IntuneWin32App `
            -FilePath             $intunewinFile.FullName `
            -DisplayName          $displayName `
            -Description          $appDescription `
            -Publisher            $vendor `
            -Owner                $Owner `
            -AppVersion           $appVersion `
            -Notes                $appNotes `
            -InstallCommandLine   $installCmd `
            -UninstallCommandLine $uninstallCmd `
            -InstallExperience    "system" `
            -RestartBehavior      "basedOnReturnCode" `
            -DetectionRule        (New-IntuneDetectionRuleObject -ParsedRule $parsed) `
            -RequirementRule      $requirementRule `
            -Icon                 (New-IntuneWin32AppIcon -FilePath $iconPath) `
            -Verbose:(-not $Quiet)

        # The module emits several pipeline objects, including status strings;
        # pick the one carrying the app id
        # PSObject.Properties rather than $_.id: StrictMode throws PropertyNotFoundException
        # on an object without the property, which would surface as an upload failure even
        # though the app already exists - and a rerun would then create a duplicate.
        $appObject = @($win32App) | Where-Object { $_ -isnot [string] -and $_.PSObject.Properties["id"] } | Select-Object -First 1
        $appId     = ${appObject}?.id

        if (-not $appId) {
            Write-Warning "App was uploaded but no ID was returned - skipping the return code patch, upload verification, supersedence, assignment and retirement. Verify in the Intune portal."
        }
        else {
            Write-Host "App uploaded successfully. Intune App ID: $appId" -ForegroundColor Green

            # Replace the full return code set so 1641 becomes softReboot instead of hardReboot
            $patchBody = @{
                "@odata.type" = "#microsoft.graph.win32LobApp"
                returnCodes   = $script:Win32AppReturnCodes
            } | ConvertTo-Json -Depth 5

            # Separate try/catch: the app already exists in Intune at this point, so a failed
            # patch must not be reported as an upload failure - a rerun would create a duplicate.
            try {
                # Reuse the authentication header established by Connect-MSIntuneGraph
                Invoke-RestMethod `
                    -Uri               "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId" `
                    -Method            Patch `
                    -Headers           @{ Authorization = $Global:AuthenticationHeader.Authorization; "Content-Type" = "application/json" } `
                    -Body              $patchBody `
                    -MaximumRetryCount 3 `
                    -RetryIntervalSec  5 | Out-Null

                Write-Host "Return code 1641 patched to softReboot." -ForegroundColor Green
            }
            catch {
                Write-Warning "App $appId was uploaded, but patching return code 1641 failed: $(Get-GraphErrorMessage -ErrorRecord $PSItem)"
                Write-Warning "Set return code 1641 to softReboot manually in the Intune portal. Do not rerun the script - that would create a duplicate app."
            }
        }
    }
    catch {
        throw "Upload failed: $($PSItem.Exception.Message)"
    }
}

#endregion

#region Step 7 - Verify the upload actually committed

# Default false so a skipped or failed verification blocks Steps 8-10
$uploadVerified = $false

if ($appId) {
    Write-Host "`n=== Step 7: Verify upload ===" -ForegroundColor Cyan
    try {
        # Our own GET, not the module's return object: verifying the module's claim with the
        # module's own claim proves nothing. The module creates the app record before the
        # content upload, so an app id is not evidence the app has committed content.
        # No $select: committedContentVersion lives on the derived mobileLobApp type and the
        # mobileApps collection is typed mobileApp, so selecting it fails with 400 on every app.
        # The unselected GET returns the full win32LobApp, derived properties included.
        $verifyResponse = Invoke-RestMethod -Method Get `
            -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId" `
            -Headers @{ Authorization = $Global:AuthenticationHeader.Authorization } `
            -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop

        $stateProp     = $verifyResponse.PSObject.Properties["publishingState"]
        $contentProp   = $verifyResponse.PSObject.Properties["committedContentVersion"]
        $publishState  = $stateProp   ? [string]$stateProp.Value   : ""
        $contentVersion = $contentProp ? [string]$contentProp.Value : ""

        if ($publishState -eq "published" -and $contentVersion -and $contentVersion -ne "0") {
            $uploadVerified = $true
            Write-Host "Upload verified: publishingState '$publishState', committedContentVersion '$contentVersion'." -ForegroundColor Green
        }
        else {
            Write-Warning "App $appId exists in Intune but has no committed content (publishingState '$publishState', committedContentVersion '$contentVersion'). Remove it manually in the Intune portal. Supersedence, assignment and retirement are skipped."
        }
    }
    catch {
        # Fail closed as before, but say what state the app is in: it was the check that failed,
        # not necessarily the upload, and the duplicate guard in Step 6 refuses a rerun while an
        # app with this name exists.
        Write-Warning "Could not verify the upload of app ${appId}: $(Get-GraphErrorMessage -ErrorRecord $PSItem). Supersedence, assignment and retirement are skipped."
        Write-Warning "The app exists in Intune and may well be intact. A rerun is refused while it exists: either delete app $appId in the Intune portal and rerun, or configure its supersedence and assignment manually."
    }
}

#endregion

#region Step 8 - Supersede the previous version

$supersedenceConfigured = $false
$keptApp                = $null
$supersedeCandidates    = @()

if ($appId -and $uploadVerified) {
    Write-Host "`n=== Step 8: Supersedence ===" -ForegroundColor Cyan
    try {
        # Both naming conventions: the resolved name and the "<Vendor> <Name>" fallback, so
        # apps uploaded before a displayName override existed are still found. The regex and
        # the strict version comparison in Select-SupersedableApp are unchanged.
        $nameBases = @($descResult.DisplayName, "$vendor $appName") | Where-Object { $_ }

        $supersedeCandidates = Select-SupersedableApp -NameBases $nameBases -NewVersion $appVersion `
                                                      -ExcludeId $appId -AllApps $appInventory

        if ($supersedeCandidates.Count -eq 0) {
            Write-Host "No earlier versions found."
        }
        else {
            $keptApp = Select-SupersedenceTarget -Candidate $supersedeCandidates -Inventory $appInventory
            if (-not $keptApp) {
                Write-Warning "Could not determine which earlier version to keep; skipping supersedence."
            }
            else {
                # Build the supersedence object inline. New-IntuneWin32AppSupersedence issues a
                # Graph GET per app just to return three static fields, and computes the token
                # lifetime with .Minutes instead of .TotalMinutes - a 60-61 minute token then
                # reads as expired and triggers a break that exits the whole script.
                $supersedenceSet = @(
                    [ordered]@{
                        "@odata.type"      = "#microsoft.graph.mobileAppSupersedence"
                        "supersedenceType" = $SupersedenceType.ToLower()
                        "targetId"         = $keptApp.Id
                    }
                )

                # foreach ($x in 1) absorbs the module's `break` on a Begin-block validation
                # failure, which try/catch does not catch and which otherwise exits the script
                # silently with exit code 0. -WarningVariable still captures the module warnings.
                $supersedenceWarnings = $null
                foreach ($breakGuard in 1) {
                    Add-IntuneWin32AppSupersedence -ID $appId -Supersedence $supersedenceSet `
                        -WarningVariable supersedenceWarnings | Out-Null
                }

                if ($supersedenceWarnings) {
                    Write-Warning "App $appId was uploaded, but supersedence against '$($keptApp.DisplayName)' was not configured (see the warning above)."
                    Write-Warning "Set supersedence manually in the Intune portal."
                }
                else {
                    $supersedenceConfigured = $true
                    Write-Host "Superseding '$($keptApp.DisplayName)' ($($keptApp.Id)) using '$SupersedenceType'." -ForegroundColor Green
                }
            }
        }
    }
    catch {
        Write-Warning "App $appId was uploaded, but configuring supersedence failed: $($PSItem.Exception.Message)"
        Write-Warning "Set supersedence manually in the Intune portal."
    }
}
elseif ($WhatIfPreference) {
    Write-Host "`nWhatIf: would supersede the previous version using '$SupersedenceType'." -ForegroundColor Yellow
}

#endregion

#region Step 9 - Assign to an Entra group

# $assignedGroupId is kept for backward compatibility and set only in single-group mode
$assignedGroupId          = $null
$pilotGroupAssigned       = $null
$productionGroupAssigned  = $null
$assignmentFullySucceeded = $false

if (($singleGroupMode -or $ringMode) -and $appId -and $uploadVerified) {
    Write-Host "`n=== Step 9: Assignment ===" -ForegroundColor Cyan

    # Auto-update of superseded apps only applies to an available assignment, and only when
    # this upload actually superseded something.
    $enableAutoUpdate = ($AssignmentIntent -eq "available") -and $supersedenceConfigured

    if ($ringMode) {
        $ringSchedule = Get-RingSchedule -PatchTuesday:$PatchTuesday `
            -ProductionDelayHours $ProductionDelayHours -DeadlineOffsetHours $DeadlineOffsetHours

        # Pilot first; production only if the pilot assignment lands
        $pilotOk = Invoke-Win32AppAssignment -AppId $appId -GroupId $PilotGroupId -RingLabel "pilot" `
            -Intent $AssignmentIntent -Notification $AssignmentNotification -UseLocalTime $UseLocalTime `
            -AvailableTime $ringSchedule.PilotStart -DeadlineTime $ringSchedule.PilotDeadline `
            -EnableAutoUpdate:$enableAutoUpdate
        if ($pilotOk) {
            $pilotGroupAssigned = $PilotGroupId
            $productionOk = Invoke-Win32AppAssignment -AppId $appId -GroupId $ProductionGroupId -RingLabel "production" `
                -Intent $AssignmentIntent -Notification $AssignmentNotification -UseLocalTime $UseLocalTime `
                -AvailableTime $ringSchedule.ProductionStart -DeadlineTime $ringSchedule.ProductionDeadline `
                -EnableAutoUpdate:$enableAutoUpdate
            if ($productionOk) {
                $productionGroupAssigned  = $ProductionGroupId
                $assignmentFullySucceeded = $true
            }
        }
        if (-not $assignmentFullySucceeded) {
            Write-Warning "App $appId was uploaded, but the ring rollout did not complete. Retirement (Step 10) is skipped."
        }
    }
    else {
        # Single-group mode: same schedule semantics as 2.7.1, the body just built locally now
        $singleOk = Invoke-Win32AppAssignment -AppId $appId -GroupId $AssignmentGroupId `
            -Intent $AssignmentIntent -Notification $AssignmentNotification -UseLocalTime $UseLocalTime `
            -AvailableTime $AvailableTime -DeadlineTime $DeadlineTime -EnableAutoUpdate:$enableAutoUpdate
        if ($singleOk) {
            $assignedGroupId          = $AssignmentGroupId
            $assignmentFullySucceeded = $true
        }
        else {
            Write-Warning "App $appId was uploaded, but the group assignment did not complete."
        }
    }
}
elseif (($singleGroupMode -or $ringMode) -and $WhatIfPreference) {
    if ($ringMode) {
        $whatIfRingSource = $PatchTuesday ? " [-PatchTuesday]" : ""
        Write-Host "`nWhatIf: would assign in two rings - pilot $PilotGroupId, then production $ProductionGroupId - as '$AssignmentIntent'$whatIfRingSource." -ForegroundColor Yellow
    }
    else {
        $whatIfAvailable = $AvailableTime ? "available $($AvailableTime.ToString('yyyy-MM-dd HH:mm'))" : "available immediately"
        $whatIfDeadline  = $DeadlineTime  ? "deadline $($DeadlineTime.ToString('yyyy-MM-dd HH:mm'))"   : "no deadline"
        $whatIfSource    = $PatchTuesday ? " [-PatchTuesday]" : ""
        Write-Host "`nWhatIf: would assign to group $AssignmentGroupId as '$AssignmentIntent' ($whatIfAvailable, $whatIfDeadline)$whatIfSource." -ForegroundColor Yellow
    }
}

#endregion

#region Step 10 - Retire superseded versions

$retiredApps = @()

if ($appId -and $supersedeCandidates.Count -gt 0 -and $keptApp) {
    $retireSet = @($supersedeCandidates | Where-Object { $_.Id -ne $keptApp.Id })

    if (-not $RetireSuperseded) {
        if ($retireSet.Count -gt 0) {
            Write-Host "`n=== Step 10: Retirement (preview) ===" -ForegroundColor Cyan
            Write-Host "These earlier versions would be retired with -RetireSuperseded:"
            foreach ($retireApp in $retireSet) { Write-Host "  $($retireApp.DisplayName)  ($($retireApp.Id))" }
        }
    }
    elseif (-not ($uploadVerified -and $supersedenceConfigured -and $assignmentFullySucceeded)) {
        Write-Warning "-RetireSuperseded was set, but retirement is skipped: the upload, supersedence and assignment did not all succeed. Retiring now could leave the tenant with no deployed version."
    }
    elseif ($retireSet.Count -eq 0) {
        Write-Host "`n=== Step 10: Retirement ===" -ForegroundColor Cyan
        Write-Host "No earlier versions to retire beyond the one kept."
    }
    else {
        Write-Host "`n=== Step 10: Retirement ===" -ForegroundColor Cyan
        $retireFailureCount = 0

        # The kept app's relations point at the versions being retired, and relations live on the
        # superseding app, so the per-app clean-up below cannot reach them. A failure here does not
        # stop the per-app retirement: the leftover link clears itself when the kept app is
        # retired at the next release.
        $keptRelationsOk = Remove-KeptAppSupersedence -KeptAppId $keptApp.Id -RetiredAppId @($retireSet.Id)
        if (-not $keptRelationsOk) {
            Write-Warning "'$($keptApp.DisplayName)' still supersedes the versions being retired. They stay linked to it until it is retired itself, and cannot be deleted before then if Intune blocks deleting superseded apps."
        }

        foreach ($retireApp in $retireSet) {
            $retireAppFailed = $false

            # Order is fixed per app: relations, then assignments, then the rename - the kept
            # app's own relation to each retired app was handled above, before this loop. If the
            # rename ran before the un-assignment and the un-assignment then failed, the app would
            # be invisible to future runs (the "(TBD)" suffix drops it from the name match) and
            # stay assigned forever. This order's worst case is an app that still has its real
            # name and is picked up on the next run.

            # 1. Clear supersedence relations (dependencies are preserved), wrapped against break
            $removeSupersedenceWarnings = $null
            foreach ($breakGuard in 1) {
                Remove-IntuneWin32AppSupersedence -ID $retireApp.Id `
                    -WarningVariable removeSupersedenceWarnings | Out-Null
            }
            if ($removeSupersedenceWarnings) { $retireAppFailed = $true }

            # 2. Remove all assignments, wrapped against break
            $removeAssignmentWarnings = $null
            foreach ($breakGuard in 1) {
                Remove-IntuneWin32AppAssignment -ID $retireApp.Id `
                    -WarningVariable removeAssignmentWarnings | Out-Null
            }
            if ($removeAssignmentWarnings) { $retireAppFailed = $true }

            # 3. Rename to "... (TBD)" via raw PATCH; skip when already suffixed so it is idempotent
            if ($retireApp.DisplayName -notmatch ' \(TBD\)$') {
                try {
                    $renameBody = @{
                        "@odata.type" = "#microsoft.graph.win32LobApp"
                        "displayName" = "$($retireApp.DisplayName) (TBD)"
                    } | ConvertTo-Json -Depth 20
                    Invoke-RestMethod -Method Patch `
                        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($retireApp.Id)" `
                        -Headers @{ Authorization = $Global:AuthenticationHeader.Authorization; "Content-Type" = "application/json" } `
                        -Body $renameBody -MaximumRetryCount 3 -RetryIntervalSec 5 -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Warning "Renaming '$($retireApp.DisplayName)' ($($retireApp.Id)) to '(TBD)' failed: $(Get-GraphErrorMessage -ErrorRecord $PSItem)"
                    $retireAppFailed = $true
                }
            }

            if ($retireAppFailed) {
                $retireFailureCount++
                Write-Warning "Retirement of '$($retireApp.DisplayName)' ($($retireApp.Id)) did not fully complete; continuing with the next app."
            }
            else {
                $retiredApps += [pscustomobject]@{ DisplayName = $retireApp.DisplayName; Id = $retireApp.Id }
                Write-Host "  Retired: $($retireApp.DisplayName)  ($($retireApp.Id))" -ForegroundColor Green
            }
        }

        if ($retireFailureCount -gt 0) {
            Write-Warning "$retireFailureCount of $($retireSet.Count) earlier version(s) did not retire cleanly. Check them in the Intune portal."
        }
    }
}
elseif ($RetireSuperseded -and $supersedeCandidates.Count -gt 0 -and -not $keptApp) {
    Write-Warning "-RetireSuperseded was set, but retirement is skipped: no earlier version could be chosen to keep (see Step 8)."
}
elseif ($RetireSuperseded -and $WhatIfPreference) {
    Write-Host "`nWhatIf: would retire earlier versions after a verified upload and a fully successful assignment." -ForegroundColor Yellow
}

#endregion

#region Cleanup

# Only runs when every step above succeeded - on failure the directory is left for troubleshooting
if ($WhatIfPreference) {
    Write-Host "`nWhatIf: leaving $tempDir in place so the generated JSON can be inspected." -ForegroundColor Yellow
}
elseif (Test-Path -Path $tempDir) {
    # The JSON lives inside the temp directory, so preserve it next to the zip before
    # cleanup - otherwise the JsonPath returned to the caller points at a deleted file
    try {
        $preservedPath = Join-Path -Path ([System.IO.Path]::GetDirectoryName($AppPath)) -ChildPath $safeFileName
        Copy-Item -Path $outputPath -Destination $preservedPath -Force
        $outputPath = $preservedPath
        Write-Host "`nJSON kept at: $outputPath" -ForegroundColor DarkGray
    }
    catch {
        Write-Warning "Could not preserve the JSON artifact before cleanup: $($PSItem.Exception.Message)"
    }

    Remove-Item -Path $tempDir -Recurse -Force
    Write-Host "Cleaned up: $tempDir" -ForegroundColor DarkGray
}

#endregion

# Structured result so the script can be consumed by other tooling
[pscustomobject]@{
    DisplayName       = $displayName
    AppId             = $appId
    JsonPath          = $outputPath
    DetectionType     = $detectionOdataType
    DescriptionFound  = $descResult.Found
    AssignedGroupId   = $assignedGroupId
    PilotGroupId      = $pilotGroupAssigned
    ProductionGroupId = $productionGroupAssigned
    SupersededApp     = $keptApp ? ([pscustomobject]@{ DisplayName = $keptApp.DisplayName; Id = $keptApp.Id }) : $null
    RetiredApps       = $retiredApps
    UploadVerified    = $uploadVerified
}