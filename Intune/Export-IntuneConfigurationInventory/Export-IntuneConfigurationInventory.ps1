<#
.SYNOPSIS
    Exports an inventory of Intune policies/configurations to a per-run folder containing a
    CSV, a manifest and one JSON file per policy, via Microsoft Graph REST.

.DESCRIPTION
    Reads policies from Microsoft Graph using the client credentials flow (no Graph SDK).

    Output layout:

        <OutputDirectory>/
            <TenantName>/
                <yyyy-MM-dd HH-mm>/
                    IntuneConfigurationInventory_<Tenant>_<yyyy-MM-dd_HHmm>.csv
                    _manifest_<yyyy-MM-dd_HHmm>.json
                    _auditevents_<yyyy-MM-dd_HHmm>.json   (only with -IncludeAuditActor)
                    <Policy-Area>/
                        <Name>_<Id>_<yyyy-MM-dd_HHmm>.json
                <Tenant>_<yyyy-MM-dd_HHmm>.zip        (only with -CompressOutput)

    Folder and file names use LOCAL time so a run is easy to identify while browsing.
    The manifest records the same instant in UTC, in local time and with the UTC offset,
    so nothing is ambiguous. Note that a scheduled run on a UTC host (Azure Functions)
    will name its folder in UTC.

    The CSV holds one row per policy with metadata, assignments, a SHA256 hash of the
    configuration and the path to its JSON file, relative to the run folder. The
    configuration itself lives in the sidecar file: embedding it inline produced single
    cells of 284 000 characters, far past Excel's 32 767 limit and past the default field
    limit of most CSV readers.

    Both the JSON files and the hash are built from a canonicalised object (keys sorted
    with ordinal comparison, array order preserved). Graph does not guarantee property
    order, so without this every run would look like a change. JSON is written indented
    so per-policy diffs are readable line by line.

    The manifest records every area with its status and object count, which lets a
    diffing agent tell "this area was empty" from "we could not read this area" - the
    difference between no change and an apparent mass deletion.

    File names are reduced to ASCII. macOS stores names decomposed (NFD) while Linux
    compares byte-exact, so a Swedish character in a path would make every entry in the
    CSV unresolvable once the folder is copied to another platform.

    -CompressOutput adds a zip of the run folder for handover. The folder itself remains
    the source of truth: diffing two runs from zips would mean unpacking both first.

.NOTES
    REQUIRED MICROSOFT GRAPH *APPLICATION* PERMISSIONS (admin consent required):
        DeviceManagementConfiguration.Read.All  - Settings Catalog, templates (deviceConfigurations),
                                                  ADMX, compliance policies, Endpoint Security intents,
                                                  Windows update profiles
        DeviceManagementScripts.Read.All        - Remediation scripts (deviceHealthScripts),
                                                  PowerShell platform scripts, macOS shell scripts.
                                                  Enforced separately from Configuration.Read.All -
                                                  those areas return 403 without it.
        DeviceManagementApps.Read.All           - App protection / app configuration policies
        DeviceManagementServiceConfig.Read.All  - Autopilot profiles, enrollment configurations,
                                                  assignment filters
        Group.Read.All                          - Resolve group object IDs to display names
        Policy.Read.All                         - ONLY needed when -IncludeConditionalAccess is used

    OPTIONAL:
        Organization.Read.All                   - Tenant display name for the root folder.
                                                  Without it the folder falls back to the tenant GUID.

    A ReadWrite variant satisfies its Read counterpart; Graph emits only one of the two claims.

    Known empty columns: Endpoint Security intents do not expose createdDateTime, so that
    column is always blank for that area. Not a defect.

    Error semantics: Intune names the missing scope on 403 ("Application must have one of the
    following scopes: ..."). A 401 with a generic Forbidden and no scope name is not a permission
    problem - check that the tenant has an active Intune licence.

    DATA SENSITIVITY: the output contains the tenant's complete security configuration,
    including script bodies, baselines and any credential-bearing profiles. Nothing in this
    script protects the artefacts - the folder and the zip are unencrypted and inherit the
    permissions of -OutputDirectory. Do not point -OutputDirectory at a synchronised folder
    (OneDrive, Dropbox) unless that is a deliberate decision, and treat the zip as customer
    confidential material when handing it over.

    Execution policy: signed or RemoteSigned/Bypass. No elevation required.
    Secrets: read from environment variables by default. Prefer SecretManagement or a
    certificate credential over a client secret for anything long-lived.

    Certificate authentication (-CertificateThumbprint or -CertificatePath) is preferred over
    a client secret and takes precedence whenever a certificate is resolved. On macOS, the
    CurrentUser\My store used for thumbprint lookup is Keychain-backed, and signing triggers a
    Keychain access dialog from Security.framework - not suppressed by pwsh -NonInteractive,
    reproduced on a production machine. Thumbprint lookup is therefore for interactive use
    only; -CertificatePath is what unattended runs and Azure Functions need, since neither has
    a Keychain to prompt against. A PFX is itself a credential, unlike a thumbprint, and does
    not belong in a synchronised folder (OneDrive, Dropbox) or in version control.

    Version:        1.10.0
    Creation Date:  2026-07-30
    Last Updated:   2026-08-27
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    CHANGELOG

        1.10.0 - 2026-08-27
            Added -IncludeAuditActor. With the switch, the export reads Intune audit events
            for the window since the previous run (deviceManagement/auditEvents, v1.0) and
            writes a projected _auditevents_<stamp>.json sidecar; the comparison then attaches
            an auditActors list to every added or modified policy in the change set. Needs no
            new Entra permission - the audit log sits behind DeviceManagementApps.Read.All,
            which the app already has. Without the switch no auditEvents call is made.

            What the field does NOT tell you. It answers "a person or an automation", not
            "which technician". In the 2026-08-27 measurement, of 25 Patch events - "someone
            edited an existing policy" - exactly one carried a named person; the rest were the
            tenant's own service principals. Reads (Get, Search) are filtered out, as are
            events whose resources never match a policy the change set already flagged.

            The actor is modelled as three states, never null: person (a userPrincipalName was
            present), app (only an applicationDisplayName), unknown (no actor at all). The
            field is a list, not a LastModifiedBy - several events can hit one policy in a
            window, and assignment changes ride along on the parent policy's resource.

            Privacy: actor.ipAddress, actor.userId, actor.userPermissions and
            resources[].modifiedProperties are dropped before anything is written to disk.

            The change set and the audit log are two signals, not one truth with an
            explanation: service-side drift (the excluded usedLicenseCount / releaseDateTime)
            leaves no audit trail, and an audit event can exist with no hash change. A 30-day
            window is not necessarily representative of a month with real portal edits.

        1.9.0 - 2026-08-27
            Merged Compare-IntuneConfigurationInventory.ps1 into this script as the
            Comparison region: the change-set taxonomy, its nine helpers and its main
            routine, the last now Invoke-InventoryComparison. -CompareWithPrevious calls
            the function directly instead of shelling out to a neighbouring file, and
            -ComparePath is gone.

            The comparison was kept separate on the expectation that it would be re-run
            standalone - after a taxonomy change, or against an older pair of runs - without
            paying for another Graph export. That did not happen: nothing invokes it
            standalone, and the documentation agent consumes the change-set JSON rather than
            the script. -CompareWithPrevious was the only entry point, so the second file
            only ever cost a path resolution that could fail after a finished export.

            Lost in the merge: pointing the comparison at a root above the per-customer
            folders to diff every customer in one pass. If that is needed again, the right
            shape is a thin wrapper that calls this script per customer, not a return of the
            multi-tenant block. The old script remains in git history.

        1.8.0 - 2026-08-26
            Added certificate authentication as an alternative to a client secret, via
            -CertificateThumbprint (looked up in the CurrentUser store - the login Keychain
            on macOS) or -CertificatePath for a PFX file, with fallback to
            INTUNE_CERT_THUMBPRINT / INTUNE_CERT_PATH / INTUNE_CERT_PASSWORD. A certificate
            wins over a secret whenever one is resolved, so a secret left in the environment
            cannot silently shadow it.

            Unlike New-IntuneWin32AppJson.ps1, which hands the certificate to
            Connect-MSIntuneGraph and lets the module sign the token request, this script has
            no module and talks to Graph over raw REST, so it builds the client_assertion JWT
            itself (RS256, x5t = base64url of the certificate's SHA1 hash). Get-ClientCertificate
            is deliberately identical to the copy in New-IntuneWin32AppJson.ps1 - never change
            one without the other.

            The resolved certificate object is intentionally never disposed: the private key
            is needed to re-sign a new assertion for every token renewal over the life of the
            run, not just the first one.

            CertificatePassword is now a SecureString. BREAKING: -CertificatePassword 'text'
            on the command line no longer works; use the environment variable, or
            -CertificatePassword (Read-Host -AsSecureString).

            An explicit -CertificatePath or -CertificateThumbprint on the command line now
            clears the other source when the selected customer's file defines it, instead of
            leaving both set and tripping the "not both" guard. Previously the only way to
            override a customer's certificate source from the command line was to also pass
            the customer's own source explicitly.

            usedLicenseCount and releaseDateTime are now excluded from the configuration and
            therefore from the hash: both were observed to drift on their own on unchanged
            apps in production. NOTE: excluding them changes the hash of every VPP app that
            has either field, so the next run after upgrading reports a one-time wave of
            "modified" on those apps. The run after that is the one that shows whether the
            noise is actually gone.

        1.7.0 - 2026-08-20
            Added applications as a nineteenth area: deviceAppManagement/mobileApps with
            assignments expanded. One area for every app type rather than one per type -
            PolicyType carries the odata type, so the platform split downstream files Win32,
            iOS, Android and macOS apps onto their own pages automatically.

            Assignments now also capture intent (required/available/uninstall) in a new
            AssignmentIntent column. Policies have no intent; for an app it is half the
            information, and moving one from required to available is a real change that the
            configuration hash alone would not show.

            The version column falls back from 'version' to 'displayVersion' to
            'versionNumber' - Win32 apps use the second and store apps the third, so without
            it the column was empty for exactly the apps that matter most.

            largeIcon is stripped alongside assignments before hashing. It is a base64 PNG
            worth tens of kilobytes per Win32 app, and a re-encode by Intune would register
            as a configuration change that never happened.

            Supersedence relationships are fetched only when supersedingAppCount or
            supersededAppCount is above zero, which is a handful of apps rather than one
            request per app.

            installSummary is deliberately NOT part of the configuration or the hash:
            installedDeviceCount changes on every device check-in, so including it would
            report every app as modified on every run. -IncludeAppInstallStatus writes it to
            a separate AppInstallStatus CSV that is neither hashed nor diffed.

            NOTE: the new area and the new column both require a fresh baseline. The first
            comparison after upgrading will report every application as added.

        1.6.0 - 2026-08-20
            Added multi-customer credential handling via -CustomerConfigPath and
            -CustomerName. Credentials come from a local JSON file instead of the
            environment; the customer is picked with a native macOS dialog or a numbered
            console menu when no name is given. Secrets are read inline or through
            Microsoft.PowerShell.SecretManagement.

            An optional value the selected customer does not define is CLEARED rather than
            left at whatever the environment or a previous selection held. TenantName is
            this script's dangerous one: it names the output folder, so inheriting it would
            write one customer's complete security configuration into another customer's
            directory. Cleared, it falls back to the name read from Graph, which is always
            correct for the tenant actually being exported. The same applies to
            OutputDirectory and IncludeConditionalAccess; JsonDepth has a working default
            and is therefore only ever replaced, never cleared.

            The block runs before the credential preflight, which would otherwise throw on
            the empty environment variables that are expected when a customer file is used.

        1.5.0 - 2026-08-05
            Hardening after an external code review, plus optional orchestration.
            Credentials are now validated in an explicit preflight: [ValidateNotNullOrEmpty()]
            never runs on default values, so an unset INTUNE_* variable used to surface as a
            request against "login.microsoftonline.com//oauth2/...". ClientId is checked
            against a GUID pattern and TenantId against GUID or domain. Passing -ClientSecret
            on the command line now warns about history and transcripts. Assignment filters
            are no longer fetched twice - the area is first in the definition list and doubles
            as the filter-name cache. A literal "value": null from Graph no longer produces a
            phantom row. Fixed a latent collision where two runs in the same minute got
            separate folders but an identical file stamp, silently overwriting the first run's
            zip; seconds are now appended to both stamps. Added -CompareWithPrevious, which
            runs the comparison script after a successful export without merging the two.

        1.4.0 - 2026-07-31
            Added -CompressOutput, producing a zip of the run folder for handover. The folder
            remains the source of truth: diffing two runs from archives would mean unpacking
            both first. Uses [System.IO.Compression.ZipFile] rather than Compress-Archive,
            which is markedly faster on many small files.

        1.3.0 - 2026-07-31
            Restructured the output into <Tenant>/<yyyy-MM-dd HH-mm>/ so a run is easy to
            identify while browsing. File names are now reduced to ASCII: macOS stores names
            decomposed (NFD) while Linux compares byte-exact, so a Swedish character in a path
            made every entry in the CSV unresolvable as soon as the folder was copied to
            another platform. Tenant display name is read from Graph when Organization.Read.All
            is granted, otherwise the tenant GUID is used.

        1.2.0 - 2026-07-30
            Configuration moved out of the CSV into one JSON file per policy, with a manifest
            recording every area's status and object count. Inline JSON had produced single
            cells of 284 000 characters - past Excel's 32 767 limit and past the default field
            limit of most CSV readers. The manifest is what lets a diffing consumer tell "this
            area was empty" from "we could not read this area", the difference between no
            change and an apparent mass deletion.

        1.1.0 - 2026-07-30
            Correctness work driven by real runs rather than code reading. Object keys are now
            canonicalised with ordinal sorting before serialisation: Graph guarantees no
            property order, and 172 of 175 records had unsorted keys, so every run looked like
            a change. JSON depth raised from 10 to 20 after measuring Settings Catalog trees at
            depth 12 - 24 records were being truncated silently. 401 and 403 are now separate
            exception types: 401 is global and aborts, 403 is scoped to one area and skips it,
            where previously a single missing scope discarded an otherwise complete export.
            An empty Graph "value" array no longer unrolls to $null and inserts the raw
            response envelope as a phantom row.

        1.0.0 - 2026-07-30
            First working version: 18 policy areas read over Graph REST with client
            credentials, no SDK. Pagination via @odata.nextLink, 429 handling that respects
            Retry-After with exponential backoff, group and assignment-filter name resolution,
            and a CSV with fixed column order and deterministic row order.

.EXAMPLE
    $env:INTUNE_TENANT_ID     = '00000000-0000-0000-0000-000000000000'
    $env:INTUNE_CLIENT_ID     = '00000000-0000-0000-0000-000000000000'
    $env:INTUNE_CLIENT_SECRET = 'your-secret'
    .\Export-IntuneConfigurationInventory.ps1 -Verbose

.EXAMPLE
    # Folder plus a single zip to hand over to a downstream agent.
    .\Export-IntuneConfigurationInventory.ps1 -CompressOutput -Verbose

.EXAMPLE
    # Export and diff against the previous run in one command. The change set lands in the
    # new run folder as _changeset_vs_<previous>.json, or _changeset_baseline.json on a
    # first run.
    .\Export-IntuneConfigurationInventory.ps1 -CompareWithPrevious -Verbose

.EXAMPLE
    # Pick a customer from a local credential file - prompts when -CustomerName is omitted
    .\Export-IntuneConfigurationInventory.ps1 -CustomerConfigPath ~/.intune/customers.json -Verbose

.EXAMPLE
    # Unattended run against one named customer
    .\Export-IntuneConfigurationInventory.ps1 -CustomerConfigPath ~/.intune/customers.json `
        -CustomerName 'Contoso' -CompareWithPrevious

.EXAMPLE
    # Permission check only - decodes the token, reports tenant, roles and affected areas.
    .\Export-IntuneConfigurationInventory.ps1 -TestPermissionOnly -Verbose

.EXAMPLE
    # Certificate from the CurrentUser store (login Keychain on macOS) - no secret involved.
    $env:INTUNE_CERT_THUMBPRINT = '0123456789ABCDEF0123456789ABCDEF01234567'
    .\Export-IntuneConfigurationInventory.ps1 -Verbose

.EXAMPLE
    # PFX on disk - the form for Azure Functions and other environments with no usable
    # certificate store. CertificatePassword is a SecureString, so it is never passed as a
    # plain string on the command line: leave it to the INTUNE_CERT_PASSWORD fallback, or
    # build one with (Read-Host -AsSecureString) if the parameter is needed explicitly.
    $env:INTUNE_CERT_PATH     = '/home/site/wwwroot/intune.pfx'
    $env:INTUNE_CERT_PASSWORD = 'your-pfx-password'
    .\Export-IntuneConfigurationInventory.ps1 -CompressOutput
#>

#Requires -Version 7.4

[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Plaintext originates outside the script; conversion is the containment point.')]
param(
    [string]$TenantId = $env:INTUNE_TENANT_ID,

    [string]$ClientId = $env:INTUNE_CLIENT_ID,

    [string]$ClientSecret = $env:INTUNE_CLIENT_SECRET,

    # Certificate authentication, preferred over a client secret. Thumbprint looks the
    # certificate up in the current user's store - the login Keychain on macOS, the
    # certificate store on Windows - so the private key never leaves the OS keystore.
    # Use the path form where no store exists, such as a Linux-based Azure Function.
    [string]$CertificateThumbprint = $env:INTUNE_CERT_THUMBPRINT,

    [string]$CertificatePath = $env:INTUNE_CERT_PATH,

    # SecureString rather than string: X509Certificate2 has a SecureString overload, so the
    # plaintext never has to be materialised, and PSScriptAnalyzer stops flagging the
    # parameter. The environment variable is still plaintext - it is converted here rather
    # than carried any further.
    [securestring]$CertificatePassword = $(
        if (-not [string]::IsNullOrEmpty($env:INTUNE_CERT_PASSWORD)) {
            ConvertTo-SecureString -String $env:INTUNE_CERT_PASSWORD -AsPlainText -Force
        }
    ),

    # Root under which the per-tenant folder is created. Defaults to the script folder.
    [string]$OutputDirectory,

    # Overrides the tenant name looked up from Graph. Useful when the organisation
    # display name is unhelpful but the folder should say something else.
    [string]$TenantName,

    # Comma keeps the CSV parseable even though group lists inside cells are semicolon-separated.
    [ValidateSet(',', ';', "`t")]
    [string]$Delimiter = ',',

    # Default 20, not 10: measured Settings Catalog settingInstance trees reach depth 12,
    # and ConvertTo-Json truncates silently past the limit.
    [ValidateRange(2, 100)]
    [int]$JsonDepth = 20,

    # Also produce a single .zip of the run folder - one artefact to hand over instead of
    # 174 loose files. The folder remains the source of truth for diffing.
    [switch]$CompressOutput,

    # Produce a change set against the previous run once the export finishes, in the same
    # command. Runs Invoke-InventoryComparison over this tenant's run folders; a failure
    # there is warned about, never fatal, since the export on disk is already complete.
    [switch]$CompareWithPrevious,

    # Settings Catalog / Endpoint Security settings need one extra call per policy. Skip for a fast run.
    [switch]$SkipDetailedSettings,

    # Collect per-app installation counts into a separate CSV. Deliberately not part of the
    # inventory: install counts change every time a device checks in, so folding them into
    # ConfigurationHash would report every app as changed on every run.
    [switch]$IncludeAppInstallStatus,

    # Fetch Intune audit events for the window since the previous run and attach the actor
    # (person or automation) to added/modified policies in the change set. Without the switch
    # no auditEvents call is made at all - not "fetch and filter out". Needs no new Entra
    # permission: the audit log sits behind DeviceManagementApps.Read.All, which the app
    # already has. actor.ipAddress / userId / userPermissions are never written to disk.
    [switch]$IncludeAuditActor,

    [switch]$IncludeConditionalAccess,

    # Local JSON file holding per-customer credentials. When supplied, the customer is
    # selected (prompted for unless -CustomerName is given) and its values are used
    # instead of the environment variables.
    [string]$CustomerConfigPath,

    [string]$CustomerName,

    # Decode the token, report tenant, roles and affected areas, exit.
    [switch]$TestPermissionOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Customer selection

# Resolves credentials from a local multi-customer JSON file. Self-contained on purpose:
# the script stays a single file that can be copied to a machine on its own.
#
# The credential parameters default to the INTUNE_* environment variables, which are
# evaluated when the script is invoked, so the values have to be assigned here rather than
# by setting the environment. This must also run BEFORE the credential preflight below,
# which throws on an empty TenantId - with a customer file the environment is legitimately
# empty until this block has populated the variables.
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

    # Secret comes either inline or from a SecretManagement vault
    $usesVault = ($customer.ContainsKey("secretVault") -and $customer["secretVault"]) -or
                 ($customer.ContainsKey("secretName")  -and $customer["secretName"])

    # Certificate takes precedence over a secret when the customer defines one
    $customerThumbprint = $customer.ContainsKey("certificateThumbprint") ? [string]$customer["certificateThumbprint"] : ""
    $customerCertPath   = $customer.ContainsKey("certificatePath")       ? [string]$customer["certificatePath"]       : ""

    if ($customerThumbprint -or $customerCertPath) {
        if (-not $PSBoundParameters.ContainsKey("CertificateThumbprint")) { $CertificateThumbprint = $customerThumbprint }
        if (-not $PSBoundParameters.ContainsKey("CertificatePath"))       { $CertificatePath       = $customerCertPath }

        # Rule 3 of the credential pattern taken to its conclusion: an explicit parameter
        # wins, which means it also has to clear the competing source. Without this, a
        # customer thumbprint plus a command-line -CertificatePath trips the "not both"
        # guard in preflight.
        if ($PSBoundParameters.ContainsKey("CertificatePath")) {
            $CertificateThumbprint = ""
        }
        elseif ($PSBoundParameters.ContainsKey("CertificateThumbprint")) {
            $CertificatePath = ""
        }

        if (-not $PSBoundParameters.ContainsKey("CertificatePassword")) {
            $customerCertPassword = $customer.ContainsKey("certificatePassword") ? [string]$customer["certificatePassword"] : ""
            # No implicit String -> SecureString conversion exists in PowerShell, so convert
            # explicitly. An omitted key has to become $null, not an empty SecureString.
            if ([string]::IsNullOrEmpty($customerCertPassword)) {
                $CertificatePassword = $null
            }
            else {
                $CertificatePassword = ConvertTo-SecureString -String $customerCertPassword -AsPlainText -Force
            }
        }
        # Make sure a secret left in the environment cannot shadow the certificate
        $ClientSecret = $null
    }
    elseif ($usesVault) {
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

    $TenantId = [string]$customer["tenantId"]
    $ClientId = [string]$customer["clientId"]

    # --- script-specific optional values ---
    # The file is authoritative: a value the customer does not define is cleared rather than
    # left at whatever the environment held, so a value from a previously selected customer
    # cannot follow into this run.
    #
    # TenantName is the one that matters here, and it is this script's equivalent of the
    # assignment group in the upload script: it names the output folder. Inheriting customer
    # A's name would write customer B's complete security configuration into A's folder.
    # Cleared it falls back to the name read from Graph, which is always correct.
    if (-not $PSBoundParameters.ContainsKey("TenantName")) {
        $TenantName = $customer.ContainsKey("tenantName") ? [string]$customer["tenantName"] : $null
    }
    if (-not $PSBoundParameters.ContainsKey("OutputDirectory")) {
        $OutputDirectory = $customer.ContainsKey("outputDirectory") ? [string]$customer["outputDirectory"] : $null
    }
    # Conditional Access needs Policy.Read.All, which not every customer grants. Cleared it
    # returns to $false, so a customer that does not opt in cannot inherit a skipped area.
    if (-not $PSBoundParameters.ContainsKey("IncludeConditionalAccess")) {
        $IncludeConditionalAccess = [bool]($customer.ContainsKey("includeConditionalAccess") -and $customer["includeConditionalAccess"])
    }
    # Values with a working default are only replaced, never cleared
    if ($customer.ContainsKey("jsonDepth") -and $customer["jsonDepth"] -and
        -not $PSBoundParameters.ContainsKey("JsonDepth")) {
        $JsonDepth = [int]$customer["jsonDepth"]
    }

    Write-Host "Customer: $($customer["name"])  (tenant $TenantId)" -ForegroundColor Green
}

#endregion

#region Credential preflight

# Validation attributes only run on BOUND parameters, never on default values. With
# [ValidateNotNullOrEmpty()] on these three, an unset INTUNE_* variable passes silently
# and surfaces much later as a request against "login.microsoftonline.com//oauth2/...".
# Checking here turns that into one clear message.
foreach ($credential in @(
        @{ Name = 'TenantId'; Value = $TenantId; Variable = 'INTUNE_TENANT_ID' }
        @{ Name = 'ClientId'; Value = $ClientId; Variable = 'INTUNE_CLIENT_ID' })) {
    if ([string]::IsNullOrWhiteSpace($credential.Value)) {
        throw ('Missing {0}. Pass -{0} or set $env:{1}.' -f $credential.Name, $credential.Variable)
    }
}

# Either a certificate or a secret, and a certificate wins when both are present.
$script:UseCertificate = -not ([string]::IsNullOrWhiteSpace($CertificateThumbprint) -and
                               [string]::IsNullOrWhiteSpace($CertificatePath))

if ($script:UseCertificate) {
    if ($CertificateThumbprint -and $CertificatePath) {
        throw 'Specify either -CertificateThumbprint or -CertificatePath, not both.'
    }
    if (-not [string]::IsNullOrWhiteSpace($ClientSecret)) {
        Write-Verbose 'A certificate and a client secret are both present - the certificate is used and the secret ignored.'
    }
}
elseif ([string]::IsNullOrWhiteSpace($ClientSecret)) {
    throw 'No credential supplied. Provide a certificate (-CertificateThumbprint or -CertificatePath, or $env:INTUNE_CERT_THUMBPRINT / $env:INTUNE_CERT_PATH) or a client secret (-ClientSecret or $env:INTUNE_CLIENT_SECRET).'
}

$guidPattern = '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'

if ($ClientId -notmatch $guidPattern) {
    throw ('ClientId "{0}" is not a GUID.' -f $ClientId)
}

# A tenant may legitimately be addressed by GUID or by verified domain name. The
# multi-tenant aliases (common/organizations) are not valid for client credentials.
if ($TenantId -notmatch $guidPattern -and $TenantId -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}$') {
    throw ('TenantId "{0}" is neither a GUID nor a domain name.' -f $TenantId)
}

if ($PSBoundParameters.ContainsKey('ClientSecret')) {
    Write-Warning 'ClientSecret was passed as a parameter - it is now in PSReadLine history, any active transcript and potentially the process list. Prefer $env:INTUNE_CLIENT_SECRET, a SecretManagement vault or a certificate credential.'
}

#endregion Credential preflight

# Two distinct types so the main loop can tell a global auth failure (abort) from a
# per-resource permission gap (skip that area, keep the rest of the inventory).
class GraphAuthenticationException : System.Exception {
    GraphAuthenticationException([string]$message) : base($message) {}
}
class GraphAuthorizationException : System.Exception {
    GraphAuthorizationException([string]$message) : base($message) {}
}

# Script-scoped state must exist before first read - StrictMode throws on unassigned variables.
$script:TokenCache = $null
$script:AuthContext = [pscustomobject]@{
    TenantId     = $TenantId
    ClientId     = $ClientId
    ClientSecret = $ClientSecret
    # Populated in the Main region, once Get-ClientCertificate has been defined. Resolving
    # it once up front rather than per token request matters because a Keychain lookup can
    # prompt, and a bad certificate should surface before any Graph work starts.
    Certificate  = $null
}
$script:GroupNameCache = @{}
$script:FilterNameCache = @{}

#region Helpers

function Get-ObjectProperty {
    # StrictMode Latest throws on missing properties of a PSCustomObject, and Graph omits
    # properties instead of returning null - so every property read goes through here.
    # The comparison region relies on it for the same reason: exports written by different
    # script versions legitimately lack a column, and a missing one must read as absent.
    # CAUTION: an empty array value is unrolled by 'return' and comes back as $null.
    # Callers that must distinguish "property absent" from "property is an empty array"
    # have to probe PSObject.Properties directly - see Get-GraphCollection.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )
    if ($null -eq $InputObject) { return $null }
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-GraphErrorDetail {
    # Invoke-RestMethod puts the raw HTTP response body in ErrorDetails.Message. Without this the
    # caller only sees "403 (Forbidden)" and never sees which scope Intune actually wants.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $message = $ErrorRecord.Exception.Message
    $details = $ErrorRecord.ErrorDetails
    if ($null -eq $details -or [string]::IsNullOrWhiteSpace($details.Message)) { return $message }

    try {
        $parsed = $details.Message | ConvertFrom-Json
        $graphError = Get-ObjectProperty -InputObject $parsed -Name 'error'
        if ($null -ne $graphError) {
            return '{0} | {1}: {2}' -f $message,
                (Get-ObjectProperty -InputObject $graphError -Name 'code'),
                (Get-ObjectProperty -InputObject $graphError -Name 'message')
        }
    }
    catch [System.Exception] {
        # Body was not JSON - fall through and return it verbatim.
    }
    return '{0} | {1}' -f $message, $details.Message
}

function ConvertTo-CanonicalObject {
    <#
        Recursively rebuilds an object with dictionary/property keys sorted.
        Ordinal sorting, not Sort-Object: culture-aware collation would order the same
        keys differently on a Swedish workstation and on an agent running elsewhere,
        which is exactly the instability this is meant to remove.
        Array order is preserved - element order can carry meaning in Graph payloads.

        The dictionary and PSCustomObject branches are deliberately kept separate: this
        is the hot path, and merging them behind a common key/value projection costs
        readability and pipeline overhead for no functional gain.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return $null }

    # Strings are IEnumerable - must be handled before the collection branch.
    if ($InputObject -is [string]) { return $InputObject }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $keys = [string[]]@($InputObject.Keys)
        [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)

        $ordered = [ordered]@{}
        foreach ($key in $keys) {
            $ordered[$key] = ConvertTo-CanonicalObject -InputObject $InputObject[$key]
        }
        return $ordered
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $names = [string[]]@($InputObject.PSObject.Properties.Name)
        [System.Array]::Sort($names, [System.StringComparer]::Ordinal)

        $ordered = [ordered]@{}
        foreach ($name in $names) {
            $ordered[$name] = ConvertTo-CanonicalObject -InputObject $InputObject.PSObject.Properties[$name].Value
        }
        return $ordered
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = @(foreach ($element in $InputObject) { ConvertTo-CanonicalObject -InputObject $element })
        return , $list
    }

    return $InputObject
}

function ConvertFrom-JwtPayload {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param([Parameter(Mandatory)][string]$Token)

    $segments = $Token.Split('.')
    if ($segments.Count -lt 2) { throw 'Token is not a JWT.' }

    # Base64url -> base64, and restore the padding that JWT encoding strips.
    $payload = $segments[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) {
        2 { $payload += '==' }
        3 { $payload += '=' }
    }
    return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($payload)) | ConvertFrom-Json
}

function Test-RoleSatisfied {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$GrantedRole,
        [Parameter(Mandatory)][string]$RequiredRole
    )
    if ($RequiredRole -in $GrantedRole) { return $true }
    # ReadWrite is a superset of Read, and Graph emits only one of the two claims.
    return (($RequiredRole -replace '\.Read\.', '.ReadWrite.') -in $GrantedRole)
}

function ConvertTo-SafeFileNamePart {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    # ASCII-only file names. macOS stores names in NFD, Linux compares byte-exact, and a
    # normalisation mismatch would make every path in the CSV unresolvable on the consuming
    # side. Decompose first, then drop the combining marks: a-ring -> a, o-diaeresis -> o.
    # This also neutralises path traversal from a hostile tenant display name.
    $decomposed = $Value.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = [System.Text.StringBuilder]::new()
    foreach ($char in $decomposed.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($char) -ne
            [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($char)
        }
    }

    $safe = $builder.ToString() -replace '[^A-Za-z0-9._-]+', '-'
    $safe = $safe -replace '-{2,}', '-'
    # Regex rather than Trim(): no dependency on .NET overload resolution.
    return ($safe -replace '^[-._]+|[-._]+$', '')
}

function New-ConfigurationFileName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$DisplayName,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Id,
        [Parameter(Mandatory)][string]$Stamp
    )
    # Name first so the folder is navigable, id second so the file survives a rename,
    # stamp last so a file identifies its own run even when moved out of the folder.
    # 40 characters keeps the deepest path well inside Windows' 260 character limit;
    # the id guarantees uniqueness, so the name only has to be recognisable.
    $namePart = ConvertTo-SafeFileNamePart -Value $DisplayName
    if ($namePart.Length -gt 40) {
        $namePart = ($namePart.Substring(0, 40) -replace '[-._]+$', '')
    }
    if ([string]::IsNullOrWhiteSpace($namePart)) { $namePart = 'unnamed' }

    $idPart = [string]::IsNullOrWhiteSpace($Id) ? 'no-id' : (ConvertTo-SafeFileNamePart -Value $Id)
    return '{0}_{1}_{2}.json' -f $namePart, $idPart, $Stamp
}

function New-AreaResult {
    # Single shape for the manifest's per-area records, used by both skip paths and the
    # success path so they cannot drift apart.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]$Definition,
        [Parameter(Mandatory)][ValidateSet('exported', 'skipped')][string]$Status,
        [int]$ObjectCount = 0,
        [AllowEmptyString()][string]$Reason = ''
    )
    return [pscustomobject][ordered]@{
        area         = $Definition.Area
        resource     = $Definition.Resource
        status       = $Status
        objectCount  = $ObjectCount
        requiredRole = $Definition.RequiredRole
        reason       = $Reason
    }
}

function Get-TenantDisplayName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$TenantId)

    # Organization.Read.All is optional, so every failure path falls back to the GUID
    # rather than derailing the export over a cosmetic folder name.
    try {
        $org = Invoke-GraphRequest -Uri 'https://graph.microsoft.com/v1.0/organization?$select=displayName,verifiedDomains'
        $organizations = @(Get-ObjectProperty -InputObject $org -Name 'value')

        if ($organizations.Count -gt 0) {
            $name = [string](Get-ObjectProperty -InputObject $organizations[0] -Name 'displayName')
            if (-not [string]::IsNullOrWhiteSpace($name)) { return $name }

            # No display name set - the initial onmicrosoft.com prefix is the next best label.
            $domains = @(Get-ObjectProperty -InputObject $organizations[0] -Name 'verifiedDomains')
            $initial = $domains | Where-Object {
                $true -eq (Get-ObjectProperty -InputObject $PSItem -Name 'isInitial')
            } | Select-Object -First 1

            if ($null -ne $initial) {
                return ([string](Get-ObjectProperty -InputObject $initial -Name 'name')) -replace '\.onmicrosoft\.com$', ''
            }
        }
    }
    catch [System.Exception] {
        Write-Verbose ('Could not read organisation name - using tenant ID for the folder. {0}' -f $PSItem.Exception.Message)
    }
    return $TenantId
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
        Kept byte-for-byte in step with the copy in New-IntuneWin32AppJson.ps1 so both
        scripts resolve certificates identically. A later move to Key Vault is a one-line
        addition here: fetch the PFX bytes and construct the same object.
    #>
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter()][AllowEmptyString()][string]$Thumbprint,
        [Parameter()][AllowEmptyString()][string]$Path,
        [Parameter()][securestring]$Password
    )

    if ($Thumbprint -and $Path) {
        throw 'Specify either a certificate thumbprint or a certificate path, not both.'
    }

    if ($Thumbprint) {
        # Strip spaces and any invisible characters that survive a copy from the portal
        $normalized = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()

        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
        try {
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
            $found = $store.Certificates | Where-Object { $PSItem.Thumbprint -eq $normalized }
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
        catch [System.Exception] {
            # Broadened from PlatformNotSupportedException: a wrong PFX password throws
            # CryptographicException on the EphemeralKeySet attempt too, so narrowing the
            # catch would only delay the same error to the DefaultKeySet retry below, not
            # prevent it. Trade-off: an unrelated load failure (corrupt PFX) is retried here
            # as well, and the message the user sees is whatever the retry throws, not
            # necessarily the original cause.
            Write-Verbose 'Could not load with EphemeralKeySet - retrying with the default key set.'
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

function ConvertTo-Base64Url {
    # JWT uses base64url: '+' and '/' swapped for '-' and '_', padding stripped.
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][byte[]]$Bytes)

    return [System.Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-ClientAssertion {
    <#
    .SYNOPSIS
        Builds a signed JWT for the client_credentials certificate flow.

    .DESCRIPTION
        The IntuneWin32App module does this internally when handed a certificate; with raw
        REST there is no module, so the assertion is built here. Entra ID validates:

          x5t   base64url of the certificate's SHA1 hash, which is how it picks the right
                public key among those registered on the app
          aud   the exact token endpoint being posted to
          iss   and sub, both the client ID
          jti   a unique identifier, to make replay detectable
          exp   short lived - ten minutes is ample for one token request

        RS256 with PKCS#1 padding is the only algorithm Entra ID accepts here.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$TokenUri
    )

    $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($null -eq $privateKey) {
        throw 'The certificate has no usable RSA private key. ECDSA certificates are not supported by Entra ID for client assertions.'
    }

    $now = [System.DateTimeOffset]::UtcNow
    $header = [ordered]@{
        alg = 'RS256'
        typ = 'JWT'
        x5t = ConvertTo-Base64Url -Bytes $Certificate.GetCertHash()
    }
    $claims = [ordered]@{
        aud = $TokenUri
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        # MSAL sets nbf = iat = now, verified against a live tenant from both a store
        # thumbprint and a PFX. The previous value (now - 5 min) was accepted too, so this
        # was not a fix - it narrows the assertion's validity window from 15 minutes to 10
        # and keeps the claim set identical to a reference client, rather than relying on
        # our own judgment about how much clock skew an STS will tolerate.
        nbf = $now.ToUnixTimeSeconds()
        iat = $now.ToUnixTimeSeconds()
        exp = $now.AddMinutes(10).ToUnixTimeSeconds()
    }

    $encodedHeader = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $header -Compress)))
    $encodedClaims = ConvertTo-Base64Url -Bytes ([System.Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $claims -Compress)))

    $signingInput = '{0}.{1}' -f $encodedHeader, $encodedClaims
    $signature = $privateKey.SignData(
        [System.Text.Encoding]::UTF8.GetBytes($signingInput),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    return '{0}.{1}' -f $signingInput, (ConvertTo-Base64Url -Bytes $signature)
}

function Get-GraphAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 5-minute safety margin so a long-running export never dies mid-page on an expired token.
    if ($null -ne $script:TokenCache -and $script:TokenCache.ExpiresOn -gt (Get-Date).AddMinutes(5)) {
        return $script:TokenCache.AccessToken
    }

    $tokenUri = 'https://login.microsoftonline.com/{0}/oauth2/v2.0/token' -f $script:AuthContext.TenantId

    $body = @{
        client_id  = $script:AuthContext.ClientId
        scope      = 'https://graph.microsoft.com/.default'
        grant_type = 'client_credentials'
    }

    # A certificate wins whenever one was resolved, so a stale secret left in the
    # environment cannot quietly shadow it.
    if ($null -ne $script:AuthContext.Certificate) {
        $body['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $body['client_assertion'] = New-ClientAssertion -Certificate $script:AuthContext.Certificate `
            -ClientId $script:AuthContext.ClientId -TokenUri $tokenUri
    }
    else {
        $body['client_secret'] = $script:AuthContext.ClientSecret
    }

    try {
        $response = Invoke-RestMethod -Method Post -Uri $tokenUri -Body $body `
            -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
    }
    catch [System.Exception] {
        # The AADSTS code in this message is the fastest way to separate "app not registered
        # in this tenant" (AADSTS700016) from "wrong secret" (AADSTS7000215).
        throw ('Failed to acquire Graph token for tenant {0}: {1}' -f
            $script:AuthContext.TenantId, (Get-GraphErrorDetail -ErrorRecord $PSItem))
    }

    $script:TokenCache = [pscustomobject]@{
        AccessToken = $response.access_token
        ExpiresOn   = (Get-Date).AddSeconds([int]$response.expires_in)
    }
    return $script:TokenCache.AccessToken
}

function Invoke-GraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateRange(1, 10)][int]$MaxAttempt = 5
    )

    $attempt = 0
    $tokenRefreshed = $false

    while ($true) {
        $attempt++
        try {
            $token = Get-GraphAccessToken
            return Invoke-RestMethod -Uri $Uri -Method Get -ErrorAction Stop `
                -Headers @{ Authorization = "Bearer $token"; Accept = 'application/json' }
        }
        catch [System.Exception] {
            $statusCode = 0
            $retryAfterSeconds = $null
            $detail = Get-GraphErrorDetail -ErrorRecord $PSItem

            $response = $PSItem.Exception.PSObject.Properties['Response']
            if ($null -ne $response -and $null -ne $response.Value) {
                $statusCode = [int]$response.Value.StatusCode
                $retryHeader = $response.Value.Headers.RetryAfter
                if ($null -ne $retryHeader) {
                    if ($null -ne $retryHeader.Delta) {
                        $retryAfterSeconds = [int]$retryHeader.Delta.TotalSeconds
                    }
                    elseif ($null -ne $retryHeader.Date) {
                        $retryAfterSeconds = [int]([datetimeoffset]$retryHeader.Date - [datetimeoffset]::UtcNow).TotalSeconds
                    }
                }
            }

            if ($statusCode -eq 401) {
                # One refresh covers a genuinely stale token. A second 401 is global - either the
                # token is rejected outright or the tenant has no active Intune licence.
                if (-not $tokenRefreshed) {
                    $tokenRefreshed = $true
                    $script:TokenCache = $null
                    continue
                }
                throw [GraphAuthenticationException]::new(
                    ('Graph rejected the token for {0}. {1}' -f $Uri, $detail))
            }

            if ($statusCode -eq 403) {
                # Scoped to this resource only - the caller skips the area and keeps going.
                throw [GraphAuthorizationException]::new(
                    ('Access denied for {0}. {1}' -f $Uri, $detail))
            }

            $isRetryable = ($statusCode -in @(429, 500, 502, 503, 504)) -or ($statusCode -eq 0)
            if (-not $isRetryable -or $attempt -ge $MaxAttempt) { throw }

            # Retry-After wins over backoff: Graph knows the actual throttle window, we don't.
            $delay = $retryAfterSeconds ?? [int][math]::Min([math]::Pow(2, $attempt), 60)
            Write-Warning ('Graph {0} on attempt {1}/{2}, waiting {3}s: {4}' -f $statusCode, $attempt, $MaxAttempt, $delay, $Uri)
            Start-Sleep -Seconds ([math]::Max($delay, 1))
        }
    }
}

function Get-GraphCollection {
    # Follows @odata.nextLink until exhausted; returns a flat list.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Uri)

    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri

    while (-not [string]::IsNullOrWhiteSpace($nextLink)) {
        $page = Invoke-GraphRequest -Uri $nextLink

        # Probe the property itself: an empty 'value' array is unrolled to $null by any
        # helper that returns it, which would make an empty collection look like a single
        # object and put the raw Graph envelope into the inventory as a phantom row.
        # The inner null check covers a literal "value": null, where @($null) would
        # otherwise add one null element and produce a row of empty fields.
        $valueProperty = $page.PSObject.Properties['value']
        if ($null -ne $valueProperty) {
            if ($null -ne $valueProperty.Value) { $results.AddRange(@($valueProperty.Value)) }
        }
        else { $results.Add($page) }

        $nextLink = Get-ObjectProperty -InputObject $page -Name '@odata.nextLink'
    }

    return , $results
}

function Resolve-GroupDisplayName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$GroupId)

    # Cached: the same handful of groups is referenced by dozens of policies. This is an
    # N+1 pattern; /directoryObjects/getByIds would collapse it to a single POST, which is
    # worth doing only once a tenant has enough distinct target groups to notice.
    if ($script:GroupNameCache.ContainsKey($GroupId)) { return $script:GroupNameCache[$GroupId] }

    # A 404 here is normal - assignments survive deletion of the target group.
    $displayName = "<deleted-or-unresolved:$GroupId>"
    try {
        $uri = 'https://graph.microsoft.com/v1.0/groups/{0}?$select=displayName' -f $GroupId
        $group = Invoke-GraphRequest -Uri $uri
        $name = Get-ObjectProperty -InputObject $group -Name 'displayName'
        if (-not [string]::IsNullOrWhiteSpace($name)) { $displayName = $name }
    }
    catch [System.Exception] {
        Write-Verbose ('Could not resolve group {0}: {1}' -f $GroupId, $PSItem.Exception.Message)
    }

    $script:GroupNameCache[$GroupId] = $displayName
    return $displayName
}

function ConvertTo-AssignmentDetail {
    # Splits raw assignment objects into include/exclude/filter strings.
    [CmdletBinding()]
    param([AllowNull()]$Assignment)

    $included = [System.Collections.Generic.List[string]]::new()
    $excluded = [System.Collections.Generic.List[string]]::new()
    $filters = [System.Collections.Generic.List[string]]::new()
    $intents = [System.Collections.Generic.List[string]]::new()
    $count = 0

    foreach ($item in @($Assignment)) {
        if ($null -eq $item) { continue }
        $count++

        # Only app assignments carry an intent (required/available/uninstall). For an app
        # this is half the meaning of the assignment, so it gets its own column rather than
        # being buried in the group string.
        $intent = [string](Get-ObjectProperty -InputObject $item -Name 'intent')
        if (-not [string]::IsNullOrWhiteSpace($intent)) { $intents.Add($intent) }

        $target = Get-ObjectProperty -InputObject $item -Name 'target'
        if ($null -eq $target) { continue }

        $targetType = [string](Get-ObjectProperty -InputObject $target -Name '@odata.type')
        $groupId = [string](Get-ObjectProperty -InputObject $target -Name 'groupId')

        switch ($targetType) {
            '#microsoft.graph.groupAssignmentTarget' { $included.Add((Resolve-GroupDisplayName -GroupId $groupId)) }
            '#microsoft.graph.exclusionGroupAssignmentTarget' { $excluded.Add((Resolve-GroupDisplayName -GroupId $groupId)) }
            '#microsoft.graph.allDevicesAssignmentTarget' { $included.Add('All devices') }
            '#microsoft.graph.allLicensedUsersAssignmentTarget' { $included.Add('All users') }
            '#microsoft.graph.configurationManagerCollectionAssignmentTarget' {
                $included.Add('ConfigMgr collection: ' + [string](Get-ObjectProperty -InputObject $target -Name 'collectionId'))
            }
            default { $included.Add(($targetType -replace '^#microsoft\.graph\.', '')) }
        }

        $filterId = [string](Get-ObjectProperty -InputObject $target -Name 'deviceAndAppManagementAssignmentFilterId')
        if (-not [string]::IsNullOrWhiteSpace($filterId) -and $filterId -ne '00000000-0000-0000-0000-000000000000') {
            $filterType = [string](Get-ObjectProperty -InputObject $target -Name 'deviceAndAppManagementAssignmentFilterType')
            $filterName = $script:FilterNameCache.ContainsKey($filterId) ? $script:FilterNameCache[$filterId] : $filterId
            $filters.Add(('{0} ({1})' -f $filterName, $filterType))
        }
    }

    # Sorted so an unchanged assignment set always produces an identical string between runs.
    return [pscustomobject]@{
        Included = (($included | Sort-Object -Unique) -join ';')
        Excluded = (($excluded | Sort-Object -Unique) -join ';')
        Filters  = (($filters | Sort-Object -Unique) -join ';')
        Intents  = (($intents | Sort-Object -Unique) -join ';')
        Count    = $count
    }
}

function ConvertTo-StableDateString {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    if ($Value -is [datetimeoffset]) { return ([datetimeoffset]$Value).ToUniversalTime().ToString('o') }
    return [string]$Value
}

function Get-StringHash {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    # Hashed over exactly the text written to the sidecar file, so the hash can be
    # re-verified against the file on disk with Get-FileHash.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Write-Utf8File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    # No BOM: JSON consumers expect plain UTF-8, unlike the CSV where Excel needs the BOM.
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-PolicyVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()]$Item)

    # Policies use 'version'. Win32 apps expose 'displayVersion', iOS/Android store apps
    # 'versionNumber' - without the fallback the column is empty for exactly the apps that
    # matter most when reviewing what is deployed.
    foreach ($property in @('version', 'displayVersion', 'versionNumber')) {
        $value = [string](Get-ObjectProperty -InputObject $Item -Name $property)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return ''
}

function Get-PolicyPlatform {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][AllowNull()]$Item)

    $platforms = Get-ObjectProperty -InputObject $Item -Name 'platforms'
    if ($null -ne $platforms) { return (@($platforms) -join ';') }

    $odataType = [string](Get-ObjectProperty -InputObject $Item -Name '@odata.type')
    switch -Regex ($odataType) {
        'macOS'   { return 'macOS' }
        'android' { return 'android' }
        'ios'     { return 'iOS' }
        'windows' { return 'windows' }
        default   { return '' }
    }
}

function New-PolicyDefinition {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][string]$Area,
        [Parameter(Mandatory)][string]$Resource,
        [Parameter(Mandatory)][string]$RequiredRole,
        [string]$ApiVersion = 'beta',
        [string]$NameProperty = 'displayName',
        [bool]$ExpandAssignments = $true,
        [string]$ExtraQuery = '',
        [string]$DetailResourceFormat = '',
        [string]$DetailKey = ''
    )
    return [pscustomobject]@{
        Area                    = $Area
        Resource                = $Resource
        RequiredRole            = $RequiredRole
        ApiVersion              = $ApiVersion
        NameProperty            = $NameProperty
        ExpandAssignments       = $ExpandAssignments
        ExtraQuery              = $ExtraQuery
        DetailResourceFormat    = $DetailResourceFormat
        DetailKey               = $DetailKey
        FetchAssignmentsPerItem = $false
    }
}

function Get-AuditEventWindow {
    <#
        Intune audit events since $Since, projected down to (who, when, what, which resource)
        as each page is read. The raw events never leave this function - in particular
        actor.ipAddress, actor.userId, actor.userPermissions and resources[].modifiedProperties
        are dropped here and never reach disk. Only writes are kept; Get/Search are reads.
        A 403 (or any other failure) is treated like a skipped area: warn, return nothing,
        let the export finish. Returns a flat list, comma-guarded like Get-GraphCollection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Since,
        [int]$MaxPages = 20
    )

    $projected = [System.Collections.Generic.List[object]]::new()

    # activityOperationType values that represent a change. Get and Search are reads - Search
    # alone was 30 of 177 events in the 2026-08-27 measurement, all from a monitoring app.
    $writeOperations = @('Create', 'Patch', 'Delete', 'Action', 'SetReference', 'RemoveReference')

    $sinceIso = $Since.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss'Z'")
    $filter = [uri]::EscapeDataString(('activityDateTime gt {0}' -f $sinceIso))
    $orderBy = [uri]::EscapeDataString('activityDateTime desc')
    $uri = 'https://graph.microsoft.com/v1.0/deviceManagement/auditEvents?$filter={0}&$orderby={1}&$top=200' -f $filter, $orderBy

    $page = 0
    while (-not [string]::IsNullOrWhiteSpace($uri) -and $page -lt $MaxPages) {
        $page++
        try {
            $response = Invoke-GraphRequest -Uri $uri
        }
        catch [System.Exception] {
            # 403 = the app cannot read the audit log; anything else = a transient or bad
            # request already retried by Invoke-GraphRequest. Either way the export stands.
            Write-Warning ('Audit events skipped - {0}' -f $PSItem.Exception.Message)
            return , ([System.Collections.Generic.List[object]]::new())
        }

        foreach ($auditEvent in @(Get-ObjectProperty -InputObject $response -Name 'value')) {
            if ($null -eq $auditEvent) { continue }

            $operation = [string](Get-ObjectProperty -InputObject $auditEvent -Name 'activityOperationType')
            if ($operation -notin $writeOperations) { continue }

            $actor = Get-ObjectProperty -InputObject $auditEvent -Name 'actor'
            $upn = [string](Get-ObjectProperty -InputObject $actor -Name 'userPrincipalName')
            $appName = [string](Get-ObjectProperty -InputObject $actor -Name 'applicationDisplayName')
            if (-not [string]::IsNullOrWhiteSpace($upn)) { $actorMode = 'person' }
            elseif (-not [string]::IsNullOrWhiteSpace($appName)) { $actorMode = 'app' }
            else { $actorMode = 'unknown' }

            $resources = [System.Collections.Generic.List[object]]::new()
            foreach ($resource in @(Get-ObjectProperty -InputObject $auditEvent -Name 'resources')) {
                if ($null -eq $resource) { continue }

                # auditResourceType arrives bare (Win32LobApp) or fully qualified
                # (Microsoft.Management.Services.Api.DeviceManagementScript). Keep the last segment.
                $rawType = [string](Get-ObjectProperty -InputObject $resource -Name 'auditResourceType')
                $resourceType = [string]($rawType -split '\.')[-1]

                $resources.Add([ordered]@{
                    resourceId   = [string](Get-ObjectProperty -InputObject $resource -Name 'resourceId')
                    displayName  = [string](Get-ObjectProperty -InputObject $resource -Name 'displayName')
                    resourceType = $resourceType
                })
            }

            $projected.Add([ordered]@{
                activityDateTime      = [string](Get-ObjectProperty -InputObject $auditEvent -Name 'activityDateTime')
                activityType          = [string](Get-ObjectProperty -InputObject $auditEvent -Name 'activityType')
                activityOperationType = $operation
                activityResult        = [string](Get-ObjectProperty -InputObject $auditEvent -Name 'activityResult')
                actor                 = [ordered]@{
                    mode                   = $actorMode
                    userPrincipalName      = $upn
                    applicationDisplayName = $appName
                }
                resources             = @($resources)
            })
        }

        $uri = [string](Get-ObjectProperty -InputObject $response -Name '@odata.nextLink')
    }

    if (-not [string]::IsNullOrWhiteSpace($uri)) {
        Write-Warning ('Audit events truncated at {0} page(s); older events in the window were not read.' -f $MaxPages)
    }

    return , $projected
}

#endregion Helpers

#region Comparison

# The change-set engine, a separate script until 1.9.0 (see the 1.9.0 changelog for why it
# was folded in). Nothing invoked it standalone - the documentation agent reads the
# change-set JSON, not the script - so -CompareWithPrevious was its only caller. Moved
# verbatim: the taxonomy (now $script:-scoped, alongside $policyDefinitions - static config
# that would bury the logic if it sat inside the function), the nine helpers, and Main as
# Invoke-InventoryComparison.

# Category grouping. Order controls page order in the change set.
$script:categoryDefinitions = @(
    [pscustomobject]@{ Order = 1; Key = 'compliance'; Title = 'Compliance Policies'
        Areas = @('Compliance Policy') }

    [pscustomobject]@{ Order = 2; Key = 'configuration'; Title = 'Configuration Profiles & Endpoint Security'
        Areas = @('Settings Catalog', 'Device Configuration (Templates)',
                  'Group Policy Configuration (ADMX)', 'Endpoint Security (Intent)') }

    [pscustomobject]@{ Order = 3; Key = 'remediations'; Title = 'Remediation Scripts'
        Areas = @('Remediation Script') }

    [pscustomobject]@{ Order = 4; Key = 'scripts'; Title = 'Platform & Shell Scripts'
        Areas = @('Platform Script (Windows)', 'Shell Script (macOS)') }

    [pscustomobject]@{ Order = 5; Key = 'apps'; Title = 'App Protection & App Configuration'
        Areas = @('App Protection Policy (iOS)', 'App Protection Policy (Android)',
                  'App Configuration (Managed Apps)', 'App Configuration (Managed Devices)') }

    [pscustomobject]@{ Order = 6; Key = 'applications'; Title = 'Applications'
        Areas = @('Application') }

    [pscustomobject]@{ Order = 7; Key = 'enrollment'; Title = 'Enrollment & Autopilot'
        Areas = @('Autopilot Deployment Profile', 'Enrollment Configuration') }

    [pscustomobject]@{ Order = 8; Key = 'updates'; Title = 'Windows Update Rings'
        Areas = @('Windows Feature Update Profile', 'Windows Quality Update Profile',
                  'Windows Driver Update Profile') }

    [pscustomobject]@{ Order = 9; Key = 'filters'; Title = 'Assignment Filters'
        Areas = @('Assignment Filter') }

    [pscustomobject]@{ Order = 10; Key = 'conditionalaccess'; Title = 'Conditional Access'
        Areas = @('Conditional Access Policy') }
)

# Canonical platforms. Order controls page order within a category.
$script:platformDefinitions = @(
    [pscustomobject]@{ Order = 1; Name = 'Windows'; Slug = 'windows' }
    [pscustomobject]@{ Order = 2; Name = 'macOS'; Slug = 'macos' }
    [pscustomobject]@{ Order = 3; Name = 'iOS/iPadOS'; Slug = 'ios' }
    [pscustomobject]@{ Order = 4; Name = 'Android'; Slug = 'android' }
    [pscustomobject]@{ Order = 5; Name = 'Linux'; Slug = 'linux' }
    [pscustomobject]@{ Order = 6; Name = 'Cross-platform'; Slug = 'cross-platform' }
)

# Lowercase lookup for whatever Graph put in the Platform column.
$script:platformAliases = @{
    'windows'                  = 'Windows'
    'windows10'                = 'Windows'
    'windows10andlater'        = 'Windows'
    'windows10xprofile'        = 'Windows'
    'windows11'                = 'Windows'
    'windows81andlater'        = 'Windows'
    'windowsphone81'           = 'Windows'
    'macos'                    = 'macOS'
    'macosandlater'            = 'macOS'
    'ios'                      = 'iOS/iPadOS'
    'iosandipados'             = 'iOS/iPadOS'
    'ipados'                   = 'iOS/iPadOS'
    'android'                  = 'Android'
    'androidaosp'              = 'Android'
    'androiddeviceowner'       = 'Android'
    'androidenterprise'        = 'Android'
    'androidforwork'           = 'Android'
    'androidmobileapplicationmanagement' = 'Android'
    'androidworkprofile'       = 'Android'
    'aosp'                     = 'Android'
    'iosmobileapplicationmanagement'     = 'iOS/iPadOS'
    'windowsmobileapplicationmanagement' = 'Windows'
    'linux'                    = 'Linux'
    'all'                      = 'Cross-platform'
    'allplatforms'             = 'Cross-platform'
}

# PolicyType carries the Graph odata type for most areas. Anchored patterns first so
# "macOSGeneralDeviceConfiguration" cannot be caught by a loose windows/ios pattern.
#
# App odata types need explicit entries: winGetApp, officeSuiteApp and
# microsoftStoreForBusinessApp match none of the platform-prefixed patterns, and
# managedIOSStoreApp does not start with "ios". A loose 'ios' pattern is deliberately NOT
# added - "kiosk" contains the letters i-o-s, so windows10KioskConfiguration would be
# misfiled as iOS the moment the ordering changed.
$script:typePatterns = @(
    [pscustomobject]@{ Pattern = '^macos'; Platform = 'macOS' }
    [pscustomobject]@{ Pattern = '^(ios|ipad)'; Platform = 'iOS/iPadOS' }
    [pscustomobject]@{ Pattern = '^managedios'; Platform = 'iOS/iPadOS' }
    [pscustomobject]@{ Pattern = '^(android|aosp)'; Platform = 'Android' }
    [pscustomobject]@{ Pattern = '^managedandroid'; Platform = 'Android' }
    [pscustomobject]@{ Pattern = '^(windows|win32|defender|sharedpc|editionupgrade)'; Platform = 'Windows' }
    [pscustomobject]@{ Pattern = '^(winget|officesuite|microsoftstore)'; Platform = 'Windows' }
    [pscustomobject]@{ Pattern = 'macos'; Platform = 'macOS' }
    [pscustomobject]@{ Pattern = 'windows'; Platform = 'Windows' }
    [pscustomobject]@{ Pattern = 'android'; Platform = 'Android' }
)

# The platform an area implies when Graph exposes none.
$script:areaPlatformDefaults = @{
    'Remediation Script'                = 'Windows'
    'Platform Script (Windows)'         = 'Windows'
    'Shell Script (macOS)'              = 'macOS'
    'Autopilot Deployment Profile'      = 'Windows'
    'Windows Feature Update Profile'    = 'Windows'
    'Windows Quality Update Profile'    = 'Windows'
    'Windows Driver Update Profile'     = 'Windows'
    'Group Policy Configuration (ADMX)' = 'Windows'
    'App Protection Policy (iOS)'       = 'iOS/iPadOS'
    'App Protection Policy (Android)'   = 'Android'
}

# Areas whose sidecar files are worth opening purely to read a platform hint. Intents are
# included despite carrying their settings inline: there are normally few of them, and it
# is the only way to tell a Windows baseline from a macOS Defender one.
$script:sidecarPeekAreas = @('Assignment Filter', 'Enrollment Configuration', 'Endpoint Security (Intent)')

function Get-RunContext {
    <#
        Loads one run folder: its manifest, its CSV rows indexed by RecordKey, and the set
        of areas that cannot support deletion claims.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $manifestFile = Get-ChildItem -Path $Path -Filter '_manifest_*.json' -File |
        Sort-Object Name | Select-Object -Last 1
    if ($null -eq $manifestFile) {
        throw ('No _manifest_*.json found in "{0}". Is this an export run folder?' -f $Path)
    }
    $manifest = Get-Content -Path $manifestFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json

    $schema = [int](Get-ObjectProperty -InputObject $manifest -Name 'schemaVersion')
    if ($schema -ne 2) {
        Write-Warning ('Manifest in "{0}" is schemaVersion {1}; this script targets 2. Field names may differ.' -f $Path, $schema)
    }

    $csvName = [string](Get-ObjectProperty -InputObject $manifest -Name 'csvFile')
    $csvPath = Join-Path -Path $Path -ChildPath $csvName
    if (-not (Test-Path -Path $csvPath)) {
        throw ('CSV "{0}" named by the manifest is missing from "{1}".' -f $csvName, $Path)
    }

    $index = @{}
    foreach ($row in (Import-Csv -Path $csvPath)) {
        $index[$row.RecordKey] = $row
    }
    Write-Verbose ('Loaded {0} record(s) from {1}' -f $index.Count, $csvName)

    # Skipped areas are the ones where "missing" and "unreadable" are indistinguishable.
    $unreliable = @(
        @(Get-ObjectProperty -InputObject $manifest -Name 'areas') |
            Where-Object { $PSItem.status -ne 'exported' } |
            ForEach-Object { [string]$PSItem.area }
    )

    return [pscustomobject]@{
        Path       = $Path
        FolderName = Split-Path -Path $Path -Leaf
        Manifest   = $manifest
        Records    = $index
        Unreliable = $unreliable
    }
}

function Get-SidecarPlatform {
    # Some areas carry a singular 'platform' or 'platformType' that the exporter's
    # Get-PolicyPlatform (which looks for 'platforms') never sees.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)][string]$RunPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RelativeFile,
        [Parameter(Mandatory)][hashtable]$Aliases
    )

    # Comma operator on every return: PowerShell unrolls a returned array, so an empty
    # result arrives as $null and a single value as a bare string - and .Count on either
    # throws under StrictMode.
    if ([string]::IsNullOrWhiteSpace($RelativeFile)) { return , [string[]]@() }
    $fullPath = Join-Path -Path $RunPath -ChildPath $RelativeFile
    if (-not (Test-Path -Path $fullPath)) { return , [string[]]@() }

    try {
        $json = Get-Content -Path $fullPath -Raw -Encoding utf8 | ConvertFrom-Json
    }
    catch [System.Exception] {
        Write-Verbose ('Could not read {0} for platform detection: {1}' -f $RelativeFile, $PSItem.Exception.Message)
        return , [string[]]@()
    }

    $found = [System.Collections.Generic.List[string]]::new()
    foreach ($property in @('platform', 'platformType', 'platforms')) {
        $value = Get-ObjectProperty -InputObject $json -Name $property
        foreach ($token in @($value)) {
            $key = ([string]$token).Trim().ToLowerInvariant()
            if ($Aliases.ContainsKey($key)) { $found.Add($Aliases[$key]) }
        }
    }

    # Endpoint Security intents expose no platform property at all, but their settings
    # encode it in the definitionId prefix, e.g.
    # deviceConfiguration--windows10EndpointProtectionConfiguration_defenderSecurityCentre...
    if ($found.Count -eq 0) {
        foreach ($setting in @(Get-ObjectProperty -InputObject $json -Name 'settings')) {
            $definitionId = [string](Get-ObjectProperty -InputObject $setting -Name 'definitionId')
            if ([string]::IsNullOrWhiteSpace($definitionId)) { continue }

            # macOS first: a macOS definitionId never contains "windows", but checking the
            # other way round would let a broad windows match win on some identifiers.
            if ($definitionId -match 'macos') { $found.Add('macOS'); break }
            if ($definitionId -match 'windows') { $found.Add('Windows'); break }
            if ($definitionId -match 'android') { $found.Add('Android'); break }
            if ($definitionId -match '(^|-)ios') { $found.Add('iOS/iPadOS'); break }
        }
    }

    return , [string[]]@($found | Sort-Object -Unique)
}

function Resolve-RowPlatform {
    <#
        Four-step resolution described in .DESCRIPTION. Returns one or more canonical
        platform names; never returns an empty set.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$RunPath,
        [Parameter(Mandatory)][hashtable]$Aliases,
        [Parameter(Mandatory)][object[]]$TypePattern,
        [Parameter(Mandatory)][hashtable]$AreaDefault,
        [Parameter(Mandatory)][string[]]$PeekArea
    )

    # 1 - the Platform column, which the exporter joins with ';' for multi-platform policies.
    $resolved = [System.Collections.Generic.List[string]]::new()
    foreach ($token in ([string]$Row.Platform -split ';')) {
        $key = $token.Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        if ($Aliases.ContainsKey($key)) { $resolved.Add($Aliases[$key]) }
    }
    if ($resolved.Count -gt 0) { return , [string[]]@($resolved | Sort-Object -Unique) }

    # 2 - PolicyType, which holds the Graph odata type for most areas.
    $policyType = [string]$Row.PolicyType
    if (-not [string]::IsNullOrWhiteSpace($policyType)) {
        foreach ($pattern in $TypePattern) {
            if ($policyType -match $pattern.Pattern) { return , [string[]]@($pattern.Platform) }
        }
    }

    # 3 - the area's implicit platform.
    $area = [string]$Row.PolicyArea
    if ($AreaDefault.ContainsKey($area)) { return , [string[]]@($AreaDefault[$area]) }

    # 4 - a look inside the sidecar file, for the few areas where that is cheap.
    if ($area -in $PeekArea) {
        # No @() here: Get-SidecarPlatform already protects its return with the comma
        # operator. Wrapping it again nests the array inside a second one-element array,
        # which makes every later -in comparison fail silently.
        $peeked = Get-SidecarPlatform -RunPath $RunPath -RelativeFile ([string]$Row.ConfigurationFile) -Aliases $Aliases
        if ($peeked.Count -gt 0) { return , [string[]]$peeked }
    }

    return , [string[]]@('Cross-platform')
}

function Format-DiffValue {
    # Long values (script bodies, base64 icons) would swamp the change set. The agent is
    # told the field changed and can open the JSON file when the detail matters.
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()]$Value, [Parameter(Mandatory)][int]$MaxLength)

    if ($null -eq $Value) { return '<null>' }

    $text = ($Value -is [string]) ? $Value : (ConvertTo-Json -InputObject $Value -Compress -Depth 6)
    if ($text.Length -le $MaxLength) { return $text }
    return ('{0}... [{1} characters total, truncated]' -f $text.Substring(0, $MaxLength), $text.Length)
}

function Test-IsMap {
    param([AllowNull()]$Value)
    return ($Value -is [System.Management.Automation.PSCustomObject])
}

function Test-IsList {
    param([AllowNull()]$Value)
    # Strings are IEnumerable but not IList, so this is safe for them.
    return ($Value -is [System.Collections.IList])
}

function Get-ListMatchKey {
    <#
        Returns the property name to match array elements on when every element of both
        lists carries it uniquely, otherwise $null. Matching by identity rather than
        position keeps a reordered array from reading as "everything changed".
    #>
    [CmdletBinding()]
    param([AllowNull()]$Reference, [AllowNull()]$Difference)

    foreach ($candidate in @('id', 'settingDefinitionId', 'displayName')) {
        $ok = $true
        foreach ($list in @($Reference, $Difference)) {
            $values = [System.Collections.Generic.List[string]]::new()
            foreach ($element in @($list)) {
                if (-not (Test-IsMap $element)) { $ok = $false; break }
                $value = Get-ObjectProperty -InputObject $element -Name $candidate
                if ([string]::IsNullOrWhiteSpace([string]$value)) { $ok = $false; break }
                $values.Add([string]$value)
            }
            if (-not $ok) { break }
            if (($values | Sort-Object -Unique).Count -ne $values.Count) { $ok = $false; break }
        }
        if ($ok) { return $candidate }
    }
    return $null
}

function Compare-JsonNode {
    <#
        Recursive field-level diff. Appends flat records so the agent can read a change as
        one line rather than reconstructing it from two documents.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Reference,
        [AllowNull()]$Difference,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Changes,
        [Parameter(Mandatory)][int]$MaxValueLength,
        [int]$Depth = 0
    )

    if ($Depth -gt 25) { return }

    $refNull = $null -eq $Reference
    $diffNull = $null -eq $Difference
    if ($refNull -and $diffNull) { return }

    if ($refNull -or $diffNull) {
        $Changes.Add([pscustomobject][ordered]@{
            path       = $Path
            changeType = $refNull ? 'added' : 'removed'
            oldValue   = Format-DiffValue -Value $Reference -MaxLength $MaxValueLength
            newValue   = Format-DiffValue -Value $Difference -MaxLength $MaxValueLength
        })
        return
    }

    if ((Test-IsMap $Reference) -and (Test-IsMap $Difference)) {
        $names = @($Reference.PSObject.Properties.Name) + @($Difference.PSObject.Properties.Name)
        foreach ($name in ($names | Sort-Object -Unique)) {
            Compare-JsonNode -Reference (Get-ObjectProperty -InputObject $Reference -Name $name) `
                -Difference (Get-ObjectProperty -InputObject $Difference -Name $name) `
                -Path (([string]::IsNullOrEmpty($Path)) ? $name : ('{0}.{1}' -f $Path, $name)) `
                -Changes $Changes -MaxValueLength $MaxValueLength -Depth ($Depth + 1)
        }
        return
    }

    if ((Test-IsList $Reference) -and (Test-IsList $Difference)) {
        $refItems = @($Reference)
        $diffItems = @($Difference)
        $matchKey = Get-ListMatchKey -Reference $refItems -Difference $diffItems

        if ($null -ne $matchKey) {
            $refMap = @{}
            foreach ($element in $refItems) { $refMap[[string](Get-ObjectProperty -InputObject $element -Name $matchKey)] = $element }
            $diffMap = @{}
            foreach ($element in $diffItems) { $diffMap[[string](Get-ObjectProperty -InputObject $element -Name $matchKey)] = $element }

            foreach ($key in (@($refMap.Keys) + @($diffMap.Keys) | Sort-Object -Unique)) {
                Compare-JsonNode -Reference ($refMap.ContainsKey($key) ? $refMap[$key] : $null) `
                    -Difference ($diffMap.ContainsKey($key) ? $diffMap[$key] : $null) `
                    -Path ('{0}[{1}={2}]' -f $Path, $matchKey, $key) `
                    -Changes $Changes -MaxValueLength $MaxValueLength -Depth ($Depth + 1)
            }
            return
        }

        # No stable identity - fall back to positional comparison.
        $maxCount = [math]::Max($refItems.Count, $diffItems.Count)
        for ($i = 0; $i -lt $maxCount; $i++) {
            Compare-JsonNode -Reference (($i -lt $refItems.Count) ? $refItems[$i] : $null) `
                -Difference (($i -lt $diffItems.Count) ? $diffItems[$i] : $null) `
                -Path ('{0}[{1}]' -f $Path, $i) `
                -Changes $Changes -MaxValueLength $MaxValueLength -Depth ($Depth + 1)
        }
        return
    }

    # Scalars, or a type change between runs.
    if ([string]$Reference -ne [string]$Difference) {
        $Changes.Add([pscustomobject][ordered]@{
            path       = $Path
            changeType = 'modified'
            oldValue   = Format-DiffValue -Value $Reference -MaxLength $MaxValueLength
            newValue   = Format-DiffValue -Value $Difference -MaxLength $MaxValueLength
        })
    }
}

function New-RecordSummary {
    # Compact shape shared by baseline/added/removed/modified entries, so the agent gets
    # the same fields regardless of change type.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$RunFolder,
        [Parameter(Mandatory)][string[]]$Platforms
    )
    return [ordered]@{
        recordKey             = [string]$Row.RecordKey
        policyArea            = [string]$Row.PolicyArea
        policyType            = [string]$Row.PolicyType
        displayName           = [string]$Row.DisplayName
        id                    = [string]$Row.Id
        description           = [string]$Row.Description
        platforms             = @($Platforms)
        sharedAcrossPlatforms = ($Platforms.Count -gt 1)
        assignedGroups        = [string]$Row.AssignedGroups
        excludedGroups        = [string]$Row.ExcludedGroups
        assignmentFilters     = [string]$Row.AssignmentFilters
        # Absent from baselines produced before the Application area existed.
        assignmentIntent      = [string](Get-ObjectProperty -InputObject $Row -Name 'AssignmentIntent')
        lastModifiedDateTime  = [string]$Row.LastModifiedDateTime
        configurationFile     = ('{0}/{1}' -f $RunFolder, ([string]$Row.ConfigurationFile))
    }
}

function Get-PolicyAuditActor {
    <#
        The audit events from the run's _auditevents_ sidecar whose resources include this
        policy's id, newest first. $Index is $null when the export did not fetch audit events
        (no -IncludeAuditActor); the caller then omits the field entirely rather than
        emitting an empty list, so "no field" and "field is []" stay distinguishable.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]$Index,
        [Parameter(Mandatory)][AllowEmptyString()][string]$PolicyId
    )

    if ($null -eq $Index) { return , @() }
    $key = $PolicyId.ToLowerInvariant()
    if (-not $Index.ContainsKey($key)) { return , @() }

    return , @($Index[$key] |
        Sort-Object -Property @{ Expression = { [string]$PSItem.activityDateTime }; Descending = $true })
}

function Invoke-InventoryComparison {
    # The old comparison script's Main, verbatim bar three points: -CurrentRun is dropped
    # (the current run is always the one just produced), the taxonomy reads are
    # $script:-qualified, and the trailing Write-Output stays as the return path.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantDirectory,
        [string]$BaselineRun,
        [string]$OutputPath,
        [switch]$NoPlatformSplit,
        [ValidateRange(50, 10000)][int]$MaxValueLength = 300
    )

    # Run folders are named yyyy-MM-dd HH-mm, so lexical order is chronological.
    $runFolders = @(Get-ChildItem -Path $TenantDirectory -Directory | Sort-Object -Property Name)
    if ($runFolders.Count -eq 0) {
        throw ('No run folders found under "{0}".' -f $TenantDirectory)
    }

    $currentFolder = $runFolders[-1].Name
    $current = Get-RunContext -Path (Join-Path -Path $TenantDirectory -ChildPath $currentFolder)

    $baselineFolder = $null
    if (-not [string]::IsNullOrWhiteSpace($BaselineRun)) {
        $baselineFolder = $BaselineRun
    }
    elseif ($runFolders.Count -ge 2) {
        $baselineFolder = @($runFolders | Where-Object { $PSItem.Name -ne $currentFolder })[-1].Name
    }

    $isBaselineMode = [string]::IsNullOrWhiteSpace($baselineFolder)
    $baseline = $isBaselineMode ? $null : (Get-RunContext -Path (Join-Path -Path $TenantDirectory -ChildPath $baselineFolder))

    if ($isBaselineMode) {
        Write-Verbose 'Only one run folder present - emitting a baseline change set (every policy listed as baseline).'
    }
    else {
        Write-Verbose ('Comparing "{0}" -> "{1}"' -f $baselineFolder, $currentFolder)
    }

    # Union of areas skipped in either run. Deletions cannot be asserted for these.
    $unreliableAreas = @(
        @($current.Unreliable) + ($isBaselineMode ? @() : @($baseline.Unreliable)) |
            Sort-Object -Unique
    )
    if ($unreliableAreas.Count -gt 0) {
        Write-Warning ('{0} area(s) were skipped in one or both runs - removals there are reported as uncertain: {1}' -f
            $unreliableAreas.Count, ($unreliableAreas -join '; '))
    }

    # Audit actors, if the export wrote the sidecar. Still pure local file processing - the
    # comparison never calls Graph. Index is policy id (lowercase) -> list of projected
    # events; an event is filed under every GUID-shaped resourceId it carries, so an
    # assignment change reaches its parent policy through the parent resource in the same
    # event. $auditByPolicy stays $null when the file is absent, which the field emit checks.
    $auditByPolicy = $null
    $auditFile = @(Get-ChildItem -Path $current.Path -Filter '_auditevents_*.json' -File |
        Sort-Object -Property Name) | Select-Object -Last 1
    if ($null -ne $auditFile) {
        try {
            $auditByPolicy = @{}
            $guidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
            $auditDoc = Get-Content -Path $auditFile.FullName -Raw -Encoding utf8 | ConvertFrom-Json
            $auditEvents = @(Get-ObjectProperty -InputObject $auditDoc -Name 'events' | Where-Object { $null -ne $PSItem })
            foreach ($auditEvent in $auditEvents) {
                $eventKeys = [System.Collections.Generic.List[string]]::new()
                foreach ($resource in @(Get-ObjectProperty -InputObject $auditEvent -Name 'resources')) {
                    $rid = [string](Get-ObjectProperty -InputObject $resource -Name 'resourceId')
                    # Assignment resources carry non-GUID, non-unique ids - only the parent
                    # policy resource has a GUID, and that is the one worth matching on.
                    if ($rid -match $guidPattern) { $eventKeys.Add($rid.ToLowerInvariant()) }
                }
                foreach ($eventKey in ($eventKeys | Sort-Object -Unique)) {
                    if (-not $auditByPolicy.ContainsKey($eventKey)) {
                        $auditByPolicy[$eventKey] = [System.Collections.Generic.List[object]]::new()
                    }
                    $auditByPolicy[$eventKey].Add($auditEvent)
                }
            }
            Write-Verbose ('Audit sidecar: {0} event(s) across {1} policy id(s)' -f
                $auditEvents.Count, $auditByPolicy.Count)
        }
        catch [System.Exception] {
            # The audit field is additive - a broken sidecar must not sink the whole change
            # set. Drop back to "not fetched" and carry on.
            Write-Warning ('Audit sidecar "{0}" could not be read ({1}); the change set is produced without actor data.' -f
                $auditFile.Name, $PSItem.Exception.Message)
            $auditByPolicy = $null
        }
    }

    # Platform is resolved once per record and cached on RecordKey. The current run wins when
    # a policy exists in both, so a policy that changed platform is filed under its new one.
    $platformCache = @{}
    $resolveArgs = @{
        Aliases = $script:platformAliases; TypePattern = $script:typePatterns
        AreaDefault = $script:areaPlatformDefaults; PeekArea = $script:sidecarPeekAreas
    }
    foreach ($row in $current.Records.Values) {
        # No @() here either, for the same reason as the Get-SidecarPlatform call above:
        # Resolve-RowPlatform's return values already use the comma operator to survive
        # unrolling. An extra @() nests them a second time instead of flattening anything.
        $platformCache[$row.RecordKey] = Resolve-RowPlatform -Row $row -RunPath $current.Path @resolveArgs
    }
    if (-not $isBaselineMode) {
        foreach ($row in $baseline.Records.Values) {
            if (-not $platformCache.ContainsKey($row.RecordKey)) {
                $platformCache[$row.RecordKey] = Resolve-RowPlatform -Row $row -RunPath $baseline.Path @resolveArgs
            }
        }
    }

    # Reported up front: if this line shows zero records, or everything under Cross-platform,
    # the fault is in platform resolution rather than in the page grouping below.
    # Built with explicit loops - a pipeline that emits nothing leaves $null behind, and
    # $null.Count throws under StrictMode.
    $platformSpread = @()
    if ($platformCache.Count -gt 0) {
        $flatPlatforms = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $platformCache.Values) {
            foreach ($name in @($entry)) { $flatPlatforms.Add([string]$name) }
        }
        $platformSpread = @(
            $flatPlatforms | Group-Object | Sort-Object -Property Name |
                ForEach-Object { '{0}={1}' -f $PSItem.Name, $PSItem.Count }
        )
    }
    Write-Verbose ('Platforms resolved for {0} record(s): {1}' -f
        $platformCache.Count, (($platformSpread.Count -gt 0) ? ($platformSpread -join ', ') : '<none>'))

    # AssignmentIntent belongs here rather than in metadata: for an app, moving from required
    # to available is an assignment change, and like the group columns it lives outside
    # ConfigurationHash.
    $assignmentFields = @('AssignedGroups', 'ExcludedGroups', 'AssignmentFilters', 'AssignmentIntent')
    $metadataFields = @('DisplayName', 'Description', 'Version', 'TemplateName', 'Platform')

    $pages = [System.Collections.Generic.List[object]]::new()
    $totals = [ordered]@{ baseline = 0; added = 0; removed = 0; uncertain = 0; modified = 0; unchanged = 0 }
    $platformTotals = [ordered]@{}

    # Without a split every category is emitted as a single pseudo-platform page.
    $ignorePlatform = $NoPlatformSplit.IsPresent
    $platformScope = $script:platformDefinitions
    if ($ignorePlatform) {
        $platformScope = @([pscustomobject]@{ Order = 0; Name = '*'; Slug = 'all' })
    }
    Write-Verbose ('Grouping {0} categor(ies) across {1} platform(s)' -f
        $script:categoryDefinitions.Count, $platformScope.Count)

    foreach ($category in $script:categoryDefinitions) {

        # Area filter once per category rather than once per category and platform: fewer scans,
        # and the verbose line below separates an area-matching failure from a platform one.
        $categoryCurrent = @($current.Records.Values |
            Where-Object { [string]$PSItem.PolicyArea -in $category.Areas })

        $categoryBaseline = @()
        if (-not $isBaselineMode) {
            $categoryBaseline = @($baseline.Records.Values |
                Where-Object { [string]$PSItem.PolicyArea -in $category.Areas })
        }

        Write-Verbose ('{0}: {1} record(s) in scope' -f $category.Title, $categoryCurrent.Count)

        foreach ($platform in $platformScope) {

            $currentRows = @($categoryCurrent | Where-Object {
                $ignorePlatform -or ($platform.Name -in $platformCache[$PSItem.RecordKey]) })

            $baselineRows = @($categoryBaseline | Where-Object {
                $ignorePlatform -or ($platform.Name -in $platformCache[$PSItem.RecordKey]) })

            # A category/platform combination with nothing on either side produces no page.
            if ($currentRows.Count -eq 0 -and $baselineRows.Count -eq 0) { continue }

            $baselineItems = [System.Collections.Generic.List[object]]::new()
            $added = [System.Collections.Generic.List[object]]::new()
            $removed = [System.Collections.Generic.List[object]]::new()
            $uncertain = [System.Collections.Generic.List[object]]::new()
            $modified = [System.Collections.Generic.List[object]]::new()
            $unchangedCount = 0

            if ($isBaselineMode) {
                foreach ($row in ($currentRows | Sort-Object PolicyArea, DisplayName)) {
                    $baselineItems.Add((New-RecordSummary -Row $row -RunFolder $currentFolder -Platforms $platformCache[$row.RecordKey]))
                }
            }
            else {
                foreach ($row in ($currentRows | Sort-Object PolicyArea, DisplayName)) {
                    $platforms = $platformCache[$row.RecordKey]

                    if (-not $baseline.Records.ContainsKey($row.RecordKey)) {
                        $addedEntry = New-RecordSummary -Row $row -RunFolder $currentFolder -Platforms $platforms
                        if ($null -ne $auditByPolicy) {
                            $addedEntry['auditActors'] = Get-PolicyAuditActor -Index $auditByPolicy -PolicyId ([string]$row.Id)
                        }
                        $added.Add($addedEntry)
                        continue
                    }

                    $old = $baseline.Records[$row.RecordKey]

                    # Three independent signals - see the note in .DESCRIPTION about assignments
                    # living outside ConfigurationHash.
                    $configChanged = ([string]$old.ConfigurationHash -ne [string]$row.ConfigurationHash)

                    # Get-ObjectProperty rather than $old.$field: a baseline produced by an
                    # earlier version of the exporter has no AssignmentIntent column, and
                    # StrictMode throws on a missing property. A column absent on one side
                    # simply compares as empty.
                    $assignmentChanges = [System.Collections.Generic.List[object]]::new()
                    foreach ($field in $assignmentFields) {
                        $oldValue = [string](Get-ObjectProperty -InputObject $old -Name $field)
                        $newValue = [string](Get-ObjectProperty -InputObject $row -Name $field)
                        if ($oldValue -ne $newValue) {
                            $assignmentChanges.Add([pscustomobject][ordered]@{
                                field = $field; oldValue = $oldValue; newValue = $newValue
                            })
                        }
                    }

                    $metadataChanges = [System.Collections.Generic.List[object]]::new()
                    foreach ($field in $metadataFields) {
                        $oldValue = [string](Get-ObjectProperty -InputObject $old -Name $field)
                        $newValue = [string](Get-ObjectProperty -InputObject $row -Name $field)
                        if ($oldValue -ne $newValue) {
                            $metadataChanges.Add([pscustomobject][ordered]@{
                                field = $field; oldValue = $oldValue; newValue = $newValue
                            })
                        }
                    }

                    if (-not $configChanged -and $assignmentChanges.Count -eq 0 -and $metadataChanges.Count -eq 0) {
                        $unchangedCount++
                        continue
                    }

                    $fieldChanges = [System.Collections.Generic.List[object]]::new()
                    if ($configChanged) {
                        $oldFile = Join-Path -Path $baseline.Path -ChildPath ([string]$old.ConfigurationFile)
                        $newFile = Join-Path -Path $current.Path -ChildPath ([string]$row.ConfigurationFile)

                        if ((Test-Path -Path $oldFile) -and (Test-Path -Path $newFile)) {
                            $oldJson = Get-Content -Path $oldFile -Raw -Encoding utf8 | ConvertFrom-Json
                            $newJson = Get-Content -Path $newFile -Raw -Encoding utf8 | ConvertFrom-Json
                            Compare-JsonNode -Reference $oldJson -Difference $newJson -Path '' `
                                -Changes $fieldChanges -MaxValueLength $MaxValueLength
                        }
                        else {
                            Write-Warning ('Sidecar JSON missing for {0} - hash differs but no field diff could be produced.' -f $row.RecordKey)
                        }
                    }

                    $entry = New-RecordSummary -Row $row -RunFolder $currentFolder -Platforms $platforms
                    $entry['previousConfigurationFile'] = '{0}/{1}' -f $baselineFolder, ([string]$old.ConfigurationFile)
                    $entry['configurationChanged'] = $configChanged
                    $entry['assignmentChanges'] = @($assignmentChanges)
                    $entry['metadataChanges'] = @($metadataChanges)
                    $entry['fieldChanges'] = @($fieldChanges)
                    $entry['fieldChangeCount'] = $fieldChanges.Count
                    if ($null -ne $auditByPolicy) {
                        $entry['auditActors'] = Get-PolicyAuditActor -Index $auditByPolicy -PolicyId ([string]$row.Id)
                    }
                    $modified.Add($entry)
                }

                foreach ($row in ($baselineRows | Sort-Object PolicyArea, DisplayName)) {
                    if ($current.Records.ContainsKey($row.RecordKey)) { continue }

                    $entry = New-RecordSummary -Row $row -RunFolder $baselineFolder -Platforms $platformCache[$row.RecordKey]
                    if ([string]$row.PolicyArea -in $unreliableAreas) {
                        # The area could not be read - absence is not evidence of deletion.
                        $entry['reason'] = 'Area was skipped in one of the runs; the policy may still exist.'
                        $uncertain.Add($entry)
                    }
                    else {
                        $removed.Add($entry)
                    }
                }
            }

            $totals.baseline += $baselineItems.Count
            $totals.added += $added.Count
            $totals.removed += $removed.Count
            $totals.uncertain += $uncertain.Count
            $totals.modified += $modified.Count
            $totals.unchanged += $unchangedCount

            if (-not $platformTotals.Contains($platform.Name)) { $platformTotals[$platform.Name] = 0 }
            $platformTotals[$platform.Name] += $currentRows.Count

            $pageKey = '{0:d2}-{1}-{2:d2}-{3}' -f $category.Order, $category.Key, $platform.Order, $platform.Slug
            $pageTitle = '{0} - {1}' -f $category.Title, $platform.Name
            if ($ignorePlatform) {
                $pageKey = '{0:d2}-{1}' -f $category.Order, $category.Key
                $pageTitle = $category.Title
            }

            $pages.Add([ordered]@{
                pageKey        = $pageKey
                pageTitle      = $pageTitle
                category       = $category.Title
                platform       = $NoPlatformSplit ? 'All' : $platform.Name
                areas          = @($category.Areas)
                currentCount   = $currentRows.Count
                baselineItems  = @($baselineItems)
                added          = @($added)
                removed        = @($removed)
                uncertain      = @($uncertain)
                modified       = @($modified)
                unchangedCount = $unchangedCount
                hasChanges     = (($added.Count + $removed.Count + $uncertain.Count + $modified.Count) -gt 0)
            })
        }
    }

    $changeSet = [ordered]@{
        schemaVersion   = 2
        mode            = $isBaselineMode ? 'baseline' : 'delta'
        generatedUtc    = (Get-Date).ToUniversalTime().ToString('o')
        tenantName      = [string](Get-ObjectProperty -InputObject $current.Manifest -Name 'tenantName')
        tenantId        = [string](Get-ObjectProperty -InputObject $current.Manifest -Name 'tenantId')
        tenantDirectory = $TenantDirectory
        baselineRun     = $baselineFolder
        currentRun      = $currentFolder
        baselineRunUtc  = $isBaselineMode ? $null : [string](Get-ObjectProperty -InputObject $baseline.Manifest -Name 'runTimestampUtc')
        currentRunUtc   = [string](Get-ObjectProperty -InputObject $current.Manifest -Name 'runTimestampUtc')
        platformSplit   = (-not $NoPlatformSplit.IsPresent)
        # False means at least one area is unreadable in one of the runs, so the change set is
        # not a complete picture and deletions in those areas are unproven.
        reliable        = ($unreliableAreas.Count -eq 0)
        unreliableAreas = @($unreliableAreas)
        totals          = $totals
        platformTotals  = $platformTotals
        pages           = @($pages)
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $suffix = $isBaselineMode ? 'baseline' : ('vs_{0}' -f ($baselineFolder -replace '[^0-9A-Za-z-]+', '-'))
        $OutputPath = Join-Path -Path $current.Path -ChildPath ('_changeset_{0}.json' -f $suffix)
    }

    # No BOM - this is machine input, not a spreadsheet.
    [System.IO.File]::WriteAllText($OutputPath,
        (ConvertTo-Json -InputObject $changeSet -Depth 12),
        [System.Text.UTF8Encoding]::new($false))

    Write-Verbose ('Change set written to {0}' -f $OutputPath)

    Write-Output ([pscustomobject]@{
        ChangeSetPath    = $OutputPath
        Mode             = $changeSet.mode
        TenantName       = $changeSet.tenantName
        BaselineRun      = $baselineFolder
        CurrentRun       = $currentFolder
        Reliable         = $changeSet.reliable
        PageCount        = $pages.Count
        Totals           = [pscustomobject]$totals
        PlatformTotals   = [pscustomobject]$platformTotals
        PagesWithChanges = @($pages | Where-Object { $PSItem.hasChanges } | ForEach-Object { $PSItem.pageTitle })
    })
}

#endregion Comparison

#region Policy definitions

$roleConfig = 'DeviceManagementConfiguration.Read.All'
$roleScripts = 'DeviceManagementScripts.Read.All'
$roleApps = 'DeviceManagementApps.Read.All'
$roleService = 'DeviceManagementServiceConfig.Read.All'

# Data-driven: every area goes through the same generic pipeline below.
#
# ORDER MATTERS for the first entry only. Assignment filters are referenced by
# assignments in every other area, and the loop populates the filter-name cache from
# this area's own result rather than fetching the same collection a second time.
# Moving it later leaves filters in earlier areas showing as raw GUIDs.
$policyDefinitions = @(
    New-PolicyDefinition -Area 'Assignment Filter' -Resource 'deviceManagement/assignmentFilters' -RequiredRole $roleService -ExpandAssignments $false

    New-PolicyDefinition -Area 'Settings Catalog' -Resource 'deviceManagement/configurationPolicies' -RequiredRole $roleConfig `
        -NameProperty 'name' -DetailResourceFormat 'deviceManagement/configurationPolicies/{0}/settings' -DetailKey 'settings'

    New-PolicyDefinition -Area 'Device Configuration (Templates)' -Resource 'deviceManagement/deviceConfigurations' -RequiredRole $roleConfig

    New-PolicyDefinition -Area 'Group Policy Configuration (ADMX)' -Resource 'deviceManagement/groupPolicyConfigurations' -RequiredRole $roleConfig `
        -DetailResourceFormat 'deviceManagement/groupPolicyConfigurations/{0}/definitionValues?$expand=presentationValues,definition' -DetailKey 'definitionValues'

    New-PolicyDefinition -Area 'Endpoint Security (Intent)' -Resource 'deviceManagement/intents' -RequiredRole $roleConfig `
        -DetailResourceFormat 'deviceManagement/intents/{0}/settings' -DetailKey 'settings'

    New-PolicyDefinition -Area 'Compliance Policy' -Resource 'deviceManagement/deviceCompliancePolicies' -RequiredRole $roleConfig `
        -ExtraQuery 'scheduledActionsForRule($expand=scheduledActionConfigurations)'

    New-PolicyDefinition -Area 'Remediation Script' -Resource 'deviceManagement/deviceHealthScripts' -RequiredRole $roleScripts
    New-PolicyDefinition -Area 'Platform Script (Windows)' -Resource 'deviceManagement/deviceManagementScripts' -RequiredRole $roleScripts
    New-PolicyDefinition -Area 'Shell Script (macOS)' -Resource 'deviceManagement/deviceShellScripts' -RequiredRole $roleScripts

    New-PolicyDefinition -Area 'Autopilot Deployment Profile' -Resource 'deviceManagement/windowsAutopilotDeploymentProfiles' -RequiredRole $roleService
    New-PolicyDefinition -Area 'Enrollment Configuration' -Resource 'deviceManagement/deviceEnrollmentConfigurations' -RequiredRole $roleService

    New-PolicyDefinition -Area 'Windows Feature Update Profile' -Resource 'deviceManagement/windowsFeatureUpdateProfiles' -RequiredRole $roleConfig
    New-PolicyDefinition -Area 'Windows Quality Update Profile' -Resource 'deviceManagement/windowsQualityUpdateProfiles' -RequiredRole $roleConfig
    New-PolicyDefinition -Area 'Windows Driver Update Profile' -Resource 'deviceManagement/windowsDriverUpdateProfiles' -RequiredRole $roleConfig

    New-PolicyDefinition -Area 'App Protection Policy (iOS)' -Resource 'deviceAppManagement/iosManagedAppProtections' -RequiredRole $roleApps
    New-PolicyDefinition -Area 'App Protection Policy (Android)' -Resource 'deviceAppManagement/androidManagedAppProtections' -RequiredRole $roleApps
    New-PolicyDefinition -Area 'App Configuration (Managed Apps)' -Resource 'deviceAppManagement/targetedManagedAppConfigurations' -RequiredRole $roleApps
    New-PolicyDefinition -Area 'App Configuration (Managed Devices)' -Resource 'deviceAppManagement/mobileAppConfigurations' -RequiredRole $roleApps

    # One area for every app type rather than one per platform: PolicyType carries the Graph
    # odata type (win32LobApp, iosStoreApp, macOSPkgApp), which the platform resolution in
    # the Comparison region already uses to split them onto per-platform pages.
    New-PolicyDefinition -Area 'Application' -Resource 'deviceAppManagement/mobileApps' -RequiredRole $roleApps
)

if ($IncludeConditionalAccess) {
    $policyDefinitions += New-PolicyDefinition -Area 'Conditional Access Policy' `
        -Resource 'identity/conditionalAccess/policies' -RequiredRole 'Policy.Read.All' `
        -ApiVersion 'v1.0' -ExpandAssignments $false
}

#endregion Policy definitions

#region Main

# Resolve the certificate before anything else touches Graph, so a missing key or a wrong
# thumbprint fails here rather than mid-export.
if ($script:UseCertificate) {
    $script:AuthContext.Certificate = Get-ClientCertificate -Thumbprint $CertificateThumbprint `
        -Path $CertificatePath -Password $CertificatePassword
    Write-Verbose ('Authenticating with certificate {0} (expires {1:yyyy-MM-dd})' -f
        $script:AuthContext.Certificate.Thumbprint, $script:AuthContext.Certificate.NotAfter)

    # A certificate that expires during a scheduled run fails with an opaque AADSTS error,
    # so warn while there is still time to rotate.
    $daysLeft = ($script:AuthContext.Certificate.NotAfter - (Get-Date)).TotalDays
    if ($daysLeft -lt 0) {
        throw ('Certificate {0} expired on {1:yyyy-MM-dd}.' -f
            $script:AuthContext.Certificate.Thumbprint, $script:AuthContext.Certificate.NotAfter)
    }
    if ($daysLeft -lt 30) {
        Write-Warning ('Certificate {0} expires in {1:N0} day(s), on {2:yyyy-MM-dd}.' -f
            $script:AuthContext.Certificate.Thumbprint, $daysLeft, $script:AuthContext.Certificate.NotAfter)
    }
}

# One instant, three representations: UTC for the record, local for the human-facing
# folder and file names, offset so the two can always be reconciled.
$runLocal = Get-Date
$runUtc = $runLocal.ToUniversalTime()
$runStamp = $runUtc.ToString('o')
$folderStamp = $runLocal.ToString('yyyy-MM-dd HH-mm')
$fileStamp = $runLocal.ToString('yyyy-MM-dd_HHmm')

# Preflight: report which areas the token cannot reach, but never block the run -
# a partial inventory is far more useful than none.
$claims = ConvertFrom-JwtPayload -Token (Get-GraphAccessToken)
$grantedRoles = @(Get-ObjectProperty -InputObject $claims -Name 'roles')
$tokenTenantId = [string](Get-ObjectProperty -InputObject $claims -Name 'tid')

if ([string]::IsNullOrWhiteSpace($TenantName)) {
    $TenantName = Get-TenantDisplayName -TenantId $tokenTenantId
}
$tenantNamePart = ConvertTo-SafeFileNamePart -Value $TenantName
if ([string]::IsNullOrWhiteSpace($tenantNamePart)) { $tenantNamePart = $tokenTenantId }

Write-Verbose ('Tenant         : {0} ({1})' -f $TenantName, $tokenTenantId)
Write-Verbose ('Token audience : {0}' -f [string](Get-ObjectProperty -InputObject $claims -Name 'aud'))
Write-Verbose ('Token appid    : {0}' -f [string](Get-ObjectProperty -InputObject $claims -Name 'appid'))
Write-Verbose ('Token roles    : {0}' -f (($grantedRoles.Count -gt 0) ? ($grantedRoles -join ', ') : '<none>'))

if ($grantedRoles.Count -eq 0) {
    Write-Warning 'The token contains no "roles" claim. The app registration has no admin-consented APPLICATION permissions - delegated permissions are ignored by the client credentials flow.'
}

if (-not (Test-RoleSatisfied -GrantedRole $grantedRoles -RequiredRole 'Group.Read.All')) {
    Write-Warning 'Group.Read.All is missing - assigned/excluded groups will be exported as raw GUIDs.'
}

$blockedAreas = @($policyDefinitions | Where-Object {
    -not (Test-RoleSatisfied -GrantedRole $grantedRoles -RequiredRole $PSItem.RequiredRole)
})
foreach ($blocked in $blockedAreas) {
    Write-Warning ('{0} will likely fail - token lacks {1}.' -f $blocked.Area, $blocked.RequiredRole)
}

if ($TestPermissionOnly) {
    Write-Output ([pscustomobject]@{
        TenantName    = $TenantName
        TenantId      = $tokenTenantId
        GrantedRoles  = ($grantedRoles -join ', ')
        # Member enumeration over an empty collection throws under StrictMode Latest.
        BlockedAreas  = (@($blockedAreas | ForEach-Object { $PSItem.Area }) -join ', ')
        AllAreasReady = ($blockedAreas.Count -eq 0)
    })
    return
}

# <OutputDirectory>/<Tenant>/<yyyy-MM-dd HH-mm>/ - resolved before the loop because
# sidecar files are written as policies are read.
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = -not [string]::IsNullOrWhiteSpace($PSScriptRoot) ? $PSScriptRoot : (Get-Location).Path
}

$tenantRoot = Join-Path -Path $OutputDirectory -ChildPath $tenantNamePart
$runDirectory = Join-Path -Path $tenantRoot -ChildPath $folderStamp

# Minute precision collides when two exports start within the same minute. BOTH stamps
# get the seconds: $fileStamp names the CSV, the manifest, every JSON file and the zip,
# so leaving it at minute precision would let a second run silently overwrite the first
# run's archive even though its folder was uniquely named.
if (Test-Path -Path $runDirectory) {
    $seconds = $runLocal.ToString('ss')
    $folderStamp = '{0}-{1}' -f $folderStamp, $seconds
    $fileStamp = '{0}{1}' -f $fileStamp, $seconds
    $runDirectory = Join-Path -Path $tenantRoot -ChildPath $folderStamp
    Write-Warning ('A run folder for this minute already exists - using "{0}" instead.' -f $folderStamp)
}

# Audit-event window start: the previous run's UTC timestamp. Resolved here, before the new
# run folder exists, so Get-RunContext does not read the folder we are about to create as the
# current run. No previous run, or an unreadable one - fall back to 30 days.
$auditSince = $null
if ($IncludeAuditActor) {
    $auditSince = (Get-Date).ToUniversalTime().AddDays(-30)
    $priorRun = @(Get-ChildItem -Path $tenantRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object -Property Name) | Select-Object -Last 1
    if ($null -ne $priorRun) {
        try {
            $priorStamp = [string](Get-ObjectProperty -InputObject (Get-RunContext -Path $priorRun.FullName).Manifest -Name 'runTimestampUtc')
            if (-not [string]::IsNullOrWhiteSpace($priorStamp)) {
                $auditSince = [datetimeoffset]::Parse($priorStamp, [cultureinfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind).UtcDateTime
            }
        }
        catch [System.Exception] {
            Write-Warning ('Could not read the previous run''s timestamp ({0}); auditing the last 30 days instead.' -f $PSItem.Exception.Message)
        }
    }
    Write-Verbose ('Audit-event window starts {0:o}' -f $auditSince)
}

New-Item -Path $runDirectory -ItemType Directory -Force | Out-Null

$csvName = 'IntuneConfigurationInventory_{0}_{1}.csv' -f $tenantNamePart, $fileStamp
$csvPath = Join-Path -Path $runDirectory -ChildPath $csvName

$inventory = [System.Collections.Generic.List[pscustomobject]]::new()
$appInstallStatus = [System.Collections.Generic.List[pscustomobject]]::new()
$areaResults = [System.Collections.Generic.List[pscustomobject]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()

foreach ($definition in $policyDefinitions) {
    $baseUri = 'https://graph.microsoft.com/{0}/{1}' -f $definition.ApiVersion, $definition.Resource

    $expandParts = [System.Collections.Generic.List[string]]::new()
    if ($definition.ExpandAssignments) { $expandParts.Add('assignments') }
    if (-not [string]::IsNullOrWhiteSpace($definition.ExtraQuery)) { $expandParts.Add($definition.ExtraQuery) }

    $listUri = ($expandParts.Count -gt 0) ? ($baseUri + '?$expand=' + ($expandParts -join ',')) : $baseUri

    Write-Verbose "Reading $($definition.Area) from $listUri"

    $items = $null
    try {
        $items = Get-GraphCollection -Uri $listUri
    }
    catch [GraphAuthenticationException] {
        # Global: the token itself is not accepted. Nothing else will work either.
        throw ('Aborting: {0}{1}If the message names no specific scope, this is not a permission problem - verify that the tenant has an active Intune licence.' -f
            $PSItem.Exception.Message, [System.Environment]::NewLine)
    }
    catch [GraphAuthorizationException] {
        # Local: this resource needs a scope the token lacks. Skip it, keep the rest.
        Write-Warning ('{0}: skipped - {1}' -f $definition.Area, $PSItem.Exception.Message)
        $skipped.Add(('{0} (needs {1})' -f $definition.Area, $definition.RequiredRole))
        $areaResults.Add((New-AreaResult -Definition $definition -Status 'skipped' -Reason $PSItem.Exception.Message))
        continue
    }
    catch [System.Exception] {
        # Some resources reject $expand; retry flat and pull assignments per object instead.
        Write-Warning ('{0}: expanded query failed ({1}). Retrying without $expand.' -f $definition.Area, $PSItem.Exception.Message)
        try {
            $items = Get-GraphCollection -Uri $baseUri
            $definition.ExtraQuery = ''
            $definition.ExpandAssignments = $false
            $definition.FetchAssignmentsPerItem = $true
        }
        catch [System.Exception] {
            Write-Warning ('{0}: skipped - {1}' -f $definition.Area, $PSItem.Exception.Message)
            $skipped.Add($definition.Area)
            $areaResults.Add((New-AreaResult -Definition $definition -Status 'skipped' -Reason $PSItem.Exception.Message))
            continue
        }
    }

    # Doubles as the filter-name cache source - see the ordering note on $policyDefinitions.
    if ($definition.Resource -eq 'deviceManagement/assignmentFilters') {
        foreach ($filter in $items) {
            $script:FilterNameCache[[string]$filter.id] = [string]$filter.displayName
        }
    }

    # One subfolder per area, created only when the area actually returned objects.
    $areaFolderName = ConvertTo-SafeFileNamePart -Value $definition.Area
    $areaFolderPath = Join-Path -Path $runDirectory -ChildPath $areaFolderName
    if (@($items).Count -gt 0) {
        New-Item -Path $areaFolderPath -ItemType Directory -Force | Out-Null
    }

    foreach ($item in $items) {
        $id = [string](Get-ObjectProperty -InputObject $item -Name 'id')
        $assignments = Get-ObjectProperty -InputObject $item -Name 'assignments'

        if ($definition.FetchAssignmentsPerItem -and -not [string]::IsNullOrWhiteSpace($id)) {
            try {
                $assignments = Get-GraphCollection -Uri ('{0}/{1}/assignments' -f $baseUri, $id)
            }
            catch [System.Exception] {
                Write-Verbose ('No assignments for {0} {1}: {2}' -f $definition.Area, $id, $PSItem.Exception.Message)
                $assignments = $null
            }
        }

        $assignmentDetail = ConvertTo-AssignmentDetail -Assignment $assignments

        # Build the configuration payload: the object itself minus noise, plus fetched detail.
        # largeIcon is a base64 PNG on Win32 apps - tens of kilobytes of payload that would
        # also change the hash if Intune ever re-encodes it, without anything having changed.
        # usedLicenseCount is VPP licence consumption: it changes whenever a user gains or
        # loses a licence, and reported six apps as modified in a production run that nobody
        # had touched. releaseDateTime was observed reset to DateTime.MinValue on eleven apps
        # by a Microsoft-side metadata sync, all with an unchanged lastModifiedDateTime - same
        # class of problem as installSummary: a field that drifts on its own turns every run
        # into a diff. informationUrl and publisher stay in - they are genuine configuration.
        $configuration = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -in @('assignments', 'largeIcon', '@odata.context', 'assignments@odata.context',
                                     'usedLicenseCount', 'releaseDateTime')) { continue }
            $configuration[$property.Name] = $property.Value
        }

        # Supersedence relationships, only for apps that actually have any. The list response
        # already reports the counts, so this stays a handful of calls rather than one per app.
        if ($definition.Resource -eq 'deviceAppManagement/mobileApps' -and -not [string]::IsNullOrWhiteSpace($id)) {
            $supersedingCount = [int](Get-ObjectProperty -InputObject $item -Name 'supersedingAppCount')
            $supersededCount = [int](Get-ObjectProperty -InputObject $item -Name 'supersededAppCount')

            if (($supersedingCount + $supersededCount) -gt 0) {
                try {
                    $configuration['relationships'] = @(Get-GraphCollection -Uri ('{0}/{1}/relationships' -f $baseUri, $id))
                }
                catch [System.Exception] {
                    Write-Warning ('Application "{0}": could not read supersedence relationships - {1}' -f $id, $PSItem.Exception.Message)
                }
            }
        }

        if (-not $SkipDetailedSettings -and -not [string]::IsNullOrWhiteSpace($definition.DetailResourceFormat) -and -not [string]::IsNullOrWhiteSpace($id)) {
            try {
                $detailUri = 'https://graph.microsoft.com/{0}/{1}' -f $definition.ApiVersion, ($definition.DetailResourceFormat -f $id)
                $configuration[$definition.DetailKey] = @(Get-GraphCollection -Uri $detailUri)
            }
            catch [System.Exception] {
                Write-Warning ('{0} "{1}": could not read detail settings - {2}' -f $definition.Area, $id, $PSItem.Exception.Message)
            }
        }

        $displayName = [string](Get-ObjectProperty -InputObject $item -Name $definition.NameProperty)
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = [string](Get-ObjectProperty -InputObject $item -Name 'displayName')
        }

        # Canonicalise before serialising - otherwise Graph's property order leaks into the
        # hash and every run looks like a change. Indented, not compressed: the whole point
        # of the sidecar is a diff a human or an agent can read line by line.
        $canonical = ConvertTo-CanonicalObject -InputObject $configuration
        $configurationJson = ConvertTo-Json -InputObject $canonical -Depth $JsonDepth

        $configFileName = New-ConfigurationFileName -DisplayName $displayName -Id $id -Stamp $fileStamp
        Write-Utf8File -Path (Join-Path -Path $areaFolderPath -ChildPath $configFileName) -Content $configurationJson

        # Relative to the run folder, so the CSV and its JSON files stay together when moved.
        # Forward slashes regardless of platform - the path is data for a consumer that may
        # well not be running on the machine that produced it.
        $relativeConfigPath = '{0}/{1}' -f $areaFolderName, $configFileName

        $templateReference = Get-ObjectProperty -InputObject $item -Name 'templateReference'
        $templateName = [string](Get-ObjectProperty -InputObject $templateReference -Name 'templateDisplayName')

        $odataType = [string](Get-ObjectProperty -InputObject $item -Name '@odata.type')
        $policyType = if (-not [string]::IsNullOrWhiteSpace($odataType)) {
            $odataType -replace '^#microsoft\.graph\.', ''
        }
        elseif (-not [string]::IsNullOrWhiteSpace($templateName)) { $templateName }
        else { $definition.Area }

        # Built before the hashtable literal - a bare -f with a comma inside @{} is a parser error.
        $recordKey = '{0}|{1}' -f $definition.Area, $id
        $resourceUri = '{0}/{1}' -f $baseUri, $id

        # Volatile by nature: these counts move every time a device checks in, which is why
        # they go to their own file and never into the hashed configuration.
        if ($IncludeAppInstallStatus -and $definition.Resource -eq 'deviceAppManagement/mobileApps' -and
            -not [string]::IsNullOrWhiteSpace($id)) {
            try {
                $summary = Invoke-GraphRequest -Uri ('{0}/{1}/installSummary' -f $baseUri, $id)
                $appInstallStatus.Add([pscustomobject][ordered]@{
                    RunTimestamp             = $runStamp
                    RecordKey                = $recordKey
                    DisplayName              = $displayName
                    Id                       = $id
                    AppType                  = $policyType
                    InstalledDeviceCount     = [int](Get-ObjectProperty -InputObject $summary -Name 'installedDeviceCount')
                    FailedDeviceCount        = [int](Get-ObjectProperty -InputObject $summary -Name 'failedDeviceCount')
                    NotInstalledDeviceCount  = [int](Get-ObjectProperty -InputObject $summary -Name 'notInstalledDeviceCount')
                    PendingInstallDeviceCount = [int](Get-ObjectProperty -InputObject $summary -Name 'pendingInstallDeviceCount')
                    NotApplicableDeviceCount = [int](Get-ObjectProperty -InputObject $summary -Name 'notApplicableDeviceCount')
                    InstalledUserCount       = [int](Get-ObjectProperty -InputObject $summary -Name 'installedUserCount')
                    FailedUserCount          = [int](Get-ObjectProperty -InputObject $summary -Name 'failedUserCount')
                })
            }
            catch [System.Exception] {
                Write-Warning ('Application "{0}": could not read installSummary - {1}' -f $displayName, $PSItem.Exception.Message)
            }
        }

        $inventory.Add([pscustomobject][ordered]@{
            RunTimestamp         = $runStamp
            RecordKey            = $recordKey
            PolicyArea           = $definition.Area
            PolicyType           = $policyType
            DisplayName          = $displayName
            Id                   = $id
            Description          = [string](Get-ObjectProperty -InputObject $item -Name 'description')
            Platform             = Get-PolicyPlatform -Item $item
            TemplateName         = $templateName
            Version              = Get-PolicyVersion -Item $item
            CreatedDateTime      = ConvertTo-StableDateString -Value (Get-ObjectProperty -InputObject $item -Name 'createdDateTime')
            LastModifiedDateTime = ConvertTo-StableDateString -Value (Get-ObjectProperty -InputObject $item -Name 'lastModifiedDateTime')
            AssignedGroups       = $assignmentDetail.Included
            ExcludedGroups       = $assignmentDetail.Excluded
            AssignmentFilters    = $assignmentDetail.Filters
            AssignmentIntent     = $assignmentDetail.Intents
            AssignmentCount      = $assignmentDetail.Count
            ConfigurationHash    = Get-StringHash -Value $configurationJson
            ConfigurationFile    = $relativeConfigPath
            GraphResourceUri     = $resourceUri
        })
    }

    $areaResults.Add((New-AreaResult -Definition $definition -Status 'exported' -ObjectCount @($items).Count))
    Write-Verbose ('{0}: {1} object(s)' -f $definition.Area, @($items).Count)
}

if ($inventory.Count -eq 0) {
    throw 'No policies were exported - run with -TestPermissionOnly to inspect the token.'
}

# Deterministic row order - required for a meaningful line-by-line diff between runs.
$inventory |
    Sort-Object -Property PolicyArea, DisplayName, Id |
    Export-Csv -Path $csvPath -NoTypeInformation -Delimiter $Delimiter -Encoding utf8BOM

# The manifest is what lets a diffing agent tell an empty area from an unreadable one.
$manifest = [ordered]@{
    schemaVersion            = 2
    runTimestampUtc          = $runStamp
    runTimestampLocal        = $runLocal.ToString('yyyy-MM-ddTHH:mm:ss')
    utcOffset                = [System.TimeZoneInfo]::Local.GetUtcOffset($runLocal).ToString()
    timeZone                 = [System.TimeZoneInfo]::Local.Id
    tenantName               = $TenantName
    tenantId                 = $tokenTenantId
    tenantDirectory          = $tenantNamePart
    runDirectory             = $folderStamp
    csvFile                  = $csvName
    jsonDepth                = $JsonDepth
    detailedSettingsIncluded = (-not $SkipDetailedSettings.IsPresent)
    totalPolicies            = $inventory.Count
    areasExported            = @($areaResults | Where-Object { $PSItem.status -eq 'exported' }).Count
    areasSkipped             = @($areaResults | Where-Object { $PSItem.status -eq 'skipped' }).Count
    exportComplete           = ($skipped.Count -eq 0)
    areas                    = @($areaResults)
}
$manifestPath = Join-Path -Path $runDirectory -ChildPath ('_manifest_{0}.json' -f $fileStamp)
Write-Utf8File -Path $manifestPath -Content (ConvertTo-Json -InputObject $manifest -Depth 6)

# Kept out of the inventory CSV and out of every hash on purpose: install counts are a
# point-in-time reading, not configuration, and folding them in would make every app look
# changed on every run.
$appInstallStatusPath = $null
if ($IncludeAppInstallStatus -and $appInstallStatus.Count -gt 0) {
    $appInstallStatusPath = Join-Path -Path $runDirectory -ChildPath ('AppInstallStatus_{0}.csv' -f $fileStamp)
    $appInstallStatus |
        Sort-Object -Property DisplayName, Id |
        Export-Csv -Path $appInstallStatusPath -NoTypeInformation -Delimiter $Delimiter -Encoding utf8BOM
    Write-Verbose ('Install status for {0} app(s): {1}' -f $appInstallStatus.Count, $appInstallStatusPath)
}

# Audit events for the window since the previous run. The projection in Get-AuditEventWindow
# has already dropped every raw field; only (who, when, what, which resource) is left. The
# comparison reads this file from disk and correlates it - it never calls Graph itself. The
# file is written even when empty: its absence means "not fetched", not "no changes". A 403
# or any other failure here must not fail the export - the inventory on disk is already done.
$auditEventsPath = $null
if ($IncludeAuditActor) {
    try {
        $auditProjection = Get-AuditEventWindow -Since $auditSince
        $auditEventsPath = Join-Path -Path $runDirectory -ChildPath ('_auditevents_{0}.json' -f $fileStamp)
        $auditDocument = [ordered]@{
            schemaVersion  = 1
            generatedUtc   = (Get-Date).ToUniversalTime().ToString('o')
            windowStartUtc = $auditSince.ToString('o')
            eventCount     = $auditProjection.Count
            events         = @($auditProjection)
        }
        Write-Utf8File -Path $auditEventsPath -Content (ConvertTo-Json -InputObject $auditDocument -Depth 8)
        Write-Verbose ('Audit events in window: {0} -> {1}' -f $auditProjection.Count, $auditEventsPath)
    }
    catch [System.Exception] {
        Write-Warning ('Audit events not written, export unaffected: {0}' -f $PSItem.Exception.Message)
        $auditEventsPath = $null
    }
}

# Optional handover artefact. Written after the manifest so the archive is complete.
$zipPath = $null
if ($CompressOutput) {
    $zipPath = Join-Path -Path $tenantRoot -ChildPath ('{0}_{1}.zip' -f $tenantNamePart, $fileStamp)

    # Unreachable in practice now that $fileStamp gains seconds on a folder collision;
    # kept as a guard so a manually re-created archive cannot fail the run.
    if (Test-Path -Path $zipPath) {
        Write-Warning ('Overwriting existing archive {0}.' -f $zipPath)
        Remove-Item -Path $zipPath -Force
    }

    # ZipFile rather than Compress-Archive: markedly faster on many small files and free of
    # the cmdlet's wildcard and empty-folder quirks. NOTE: PS7 resolves the type without
    # Add-Type; on 5.1 you would need Add-Type -AssemblyName System.IO.Compression.FileSystem.
    # includeBaseDirectory = $true so unpacking yields a folder, not loose files.
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $runDirectory,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true)

    Write-Verbose ('Compressed to {0} ({1:N2} MB)' -f $zipPath, ((Get-Item -Path $zipPath).Length / 1MB))
}

# Optional downstream step. The comparison was a separate script until 1.9.0; it is now
# Invoke-InventoryComparison in the region above. What the merge gave up: pointing the
# comparison at a root above the per-customer folders to sweep every customer in one pass.
# A failure here must never fail the export, because the exported data on disk is complete
# and valid regardless.
$changeSetPath = $null
if ($CompareWithPrevious) {
    try {
        $comparison = @(Invoke-InventoryComparison -TenantDirectory $tenantRoot)
        if ($comparison.Count -gt 0) {
            $changeSetPath = $comparison[-1].ChangeSetPath
            Write-Verbose ('Change set: {0}' -f $changeSetPath)
        }
    }
    catch [System.Exception] {
        Write-Warning ('Comparison failed, export unaffected: {0}' -f $PSItem.Exception.Message)
    }
}

# Incomplete exports must be obvious - a diffing agent would otherwise read a skipped
# area as "everything in it was deleted".
if ($skipped.Count -gt 0) {
    Write-Warning ('INCOMPLETE EXPORT - {0} area(s) skipped: {1}' -f $skipped.Count, ($skipped -join '; '))
}

Write-Verbose ('Exported {0} policies from {1} area(s) in tenant {2}' -f
    $inventory.Count, $manifest.areasExported, $TenantName)

Write-Output ([pscustomobject]@{
    TenantRoot           = $tenantRoot
    RunDirectory         = $runDirectory
    CsvPath              = $csvPath
    ManifestPath         = $manifestPath
    ZipPath              = $zipPath
    AppInstallStatusPath = $appInstallStatusPath
    AuditEventsPath      = $auditEventsPath
    ChangeSetPath        = $changeSetPath
    PolicyCount          = $inventory.Count
    ExportComplete       = $manifest.exportComplete
})

#endregion Main