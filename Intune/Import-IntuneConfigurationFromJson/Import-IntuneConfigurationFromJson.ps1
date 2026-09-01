<#
.SYNOPSIS
    Creates Intune policies in a target tenant from sidecar JSON files produced by
    Export-IntuneConfigurationInventory.ps1. Everything is created unassigned.

.DESCRIPTION
    Reads a folder that mirrors the export's area sub-folder layout, for example:

        <SourceDirectory>/
            Settings-Catalog/
                WIN-B-CP-SC-Teams-Integrity_<id>_<stamp>.json
            Compliance-Policy/
                ...

    The area folder name decides which Graph endpoint each file is posted to. Files sitting
    directly in the root, or in a folder that is not a known area, are reported and skipped -
    the script never guesses an endpoint from a file's contents.

    A sidecar is a record of what a policy looked like, not a request body. Three things are
    done to each file before it is posted:

      1. The service-owned properties are removed (id, createdDateTime, settingCount,
         endOfSupportDate and so on). Graph rejects some of them outright and silently
         ignores the rest, so leaving them in produces confusing failures.
      2. The double-wrapped 'settings' array from exports before v1.11.0 is flattened.
         Those files carry [[{...}]] rather than [{...}] and would create a policy with no
         settings at all.
      3. Required properties are verified up front. A file that cannot produce a valid
         policy is reported as skipped rather than posted and half-created.

    Duplicate handling: the display names already present in the target tenant are read once
    per area. A file whose name matches an existing policy is skipped and reported.

    NOT SUPPORTED, by design rather than omission. These need more than a single POST and
    are reported with the reason when their folder is present:
      Group-Policy-Configuration-ADMX     container first, then one definitionValue per setting
      Endpoint-Security-Intent            bound to a template ID that differs between tenants
      Enrollment-Configuration            largely tenant singletons that cannot be created
      App-Configuration-Managed-Devices   references app IDs that do not exist in the target
      Application                         needs content upload, not a JSON body

.NOTES
    Version:        1.1.1
    Creation Date:  2026-09-01
    Last Updated:   2026-09-01
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Requires:       DeviceManagementConfiguration.ReadWrite.All
                    DeviceManagementApps.ReadWrite.All      (app protection / app config)
                    DeviceManagementScripts.ReadWrite.All   (scripts and remediations)
                    DeviceManagementServiceConfig.ReadWrite.All (Autopilot)
                    Application permissions, client credentials flow.

    SHARED CODE, AND IT IS NOT IN SYNC. Get-ClientCertificate exists in three files - here
    (52 lines), Export-IntuneConfigurationInventory.ps1 (90) and New-IntuneWin32AppJson.ps1
    (83) - in three different versions. ConvertTo-Base64Url and New-ClientAssertion exist
    here and in the export, and those two have drifted as well.

    So do NOT "resynchronise" by pasting one copy over another. The win32 copy takes a
    [string] password, has no [CmdletBinding()], and catches only
    PlatformNotSupportedException where the export deliberately widened to System.Exception
    because a wrong PFX password throws CryptographicException. Pasting the export's copy
    over it, or its copy over this one, silently changes behaviour in a credential path.
    Change the copy you are actually working on, and record what you changed here.

    This writes to a customer tenant. Run it with -WhatIf first, every time.

    CHANGELOG

        1.1.1 - 2026-09-01
            Fixes from the first real run. No new parameter, no changed parameter.

            A compliance policy could not be created. Graph annotates every $expand'd
            navigation property with '<name>@odata.context', the annotation travels into the
            sidecar, and a request body may carry only one annotation on a navigation link -
            '@odata.bind'. Anything else fails model validation before the payload is even
            looked at, so the policy's own settings were never the problem. Two of these sat
            in the sidecar: one at the top level and one inside each scheduledActionsForRule
            entry, where $script:CommonRemove could never have reached it.
            ConvertTo-AnnotationFreeObject now walks the whole structure and drops every
            '@odata.' key except '@odata.type', which has to survive - it selects the derived
            type and sits in four areas' Require list.

            The same sidecar carried the source tenant's ids on the scheduled action rule and
            on each action configuration. Those are stripped too, for compliance policies
            only - Settings Catalog settings legitimately carry id "0", "1", ... and importing
            them works.

            The banner now counts what will actually be attempted. Run with
            -Area 'Compliance-Policy' it said "7 folder(s), 20 file(s)" and then processed one
            file; it applies -Area, the unsupported list and unknown folder names, and reports
            "N of M folder(s) selected". The loop still walks every folder, because it has to
            report the unsupported and unknown-area rows.

            A Settings Catalog policy whose templateReference.templateFamily is not 'none' -
            a security baseline - now warns before the POST. Such a policy is validated
            against the target tenant's revision of that template and one unrecognised
            setting reference rejects the whole thing. Not fixed, and deliberately not:
            stripping the template references would create it as a plain configuration
            profile instead of a baseline. See README.md, "Known limitations".

        1.1.0 - 2026-09-01
            Brought in line with Export-IntuneConfigurationInventory.ps1. Additive - no
            existing switch changes meaning, and a command line that worked before still
            does.

            Graph errors now say what Graph said. Get-GraphErrorDetail reads the response
            body that Invoke-RestMethod hides in ErrorDetails.Message, so a rejected POST
            reports 'BadRequest: Property platforms has an invalid value ...' instead of
            '400 (Bad Request)'. 401 and 403 become typed exceptions: 401 aborts the run,
            403 marks the one area 'blocked' and moves on.

            A POST is retried only on 429. The export retries 429, 5xx and status 0 (no
            response), which is right for a GET and wrong for a create: 5xx and a dropped
            connection can both happen after the service has already made the policy.

            The run report, _importreport_<stamp>.json, written to the source folder or to
            -ReportDirectory. Written from a finally block, so an aborted run still leaves
            the list of what was created, with runComplete: false and abortReason. Written
            on -WhatIf runs too, marked whatIf: true.

            -TestPermissionOnly decodes the token and names the areas present in the source
            folder that it cannot create. Each area now carries the RequiredScope Graph
            wants to CREATE it, read off each endpoint's Create page - not derived from the
            export's read scopes, which would have got assignmentFilters wrong.

            -CustomerConfigPath / -CustomerName select the TARGET tenant from the same
            customers.json the export uses. A banner names source and target before the
            first write, followed by one confirmation prompt; -Force skips it.

            Fixes found while porting: the export's 401 handler nulls a single token cache
            variable and would have been a no-op here, where the token and its expiry are
            two fields; the source manifest's timestamp was rendered in the current culture;
            a misspelt -Area value produced a silent empty run.

            Regions, helper set and comment-based help now follow the export's layout.
            Get-ClientCertificate, ConvertTo-Base64Url and New-ClientAssertion are unchanged
            apart from being moved - see SHARED CODE above.

        1.0.0 - 2026-09-01
            First version. Creates policies in a target tenant from the export's sidecar
            JSON files, one POST per file, everything unassigned.

.EXAMPLE
    # Dry run - shows what would be created, contacts Graph only to read existing names.
    $env:INTUNE_CERT_THUMBPRINT = 'D9091502576A01A1150F4AE0486093DDF59E6B3E'
    .\Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -TenantId <guid> `
        -ClientId <guid> -WhatIf

.EXAMPLE
    # Only the Settings Catalog folder, for real.
    .\Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -TenantId <guid> `
        -ClientId <guid> -Area 'Settings-Catalog' -Verbose

.EXAMPLE
    # Pick the TARGET tenant from the same customers.json the export uses. Omit
    # -CustomerName to be prompted. The source folder is never read from the file.
    .\Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import `
        -CustomerConfigPath ~/.intune/customers.json -CustomerName 'Fabrikam AB' -WhatIf

.EXAMPLE
    # Check the token before touching anything: which areas in the source folder can this
    # app registration actually create? Reads nothing, writes nothing, posts nothing.
    .\Import-IntuneConfigurationFromJson.ps1 -SourceDirectory ~/Import -TenantId <guid> `
        -ClientId <guid> -TestPermissionOnly
#>

#Requires -Version 7.4

[CmdletBinding(SupportsShouldProcess)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Plaintext originates outside the script; conversion is the containment point.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'The customer picker and the target banner are console UI. Write-Output would put them in the pipeline this script returns its results on, and Write-Verbose would hide the very prompt the operator has to answer.')]
param(
    # Folder containing the area sub-folders to import from.
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $PSItem -PathType Container })]
    [string]$SourceDirectory,

    [string]$TenantId = $env:INTUNE_TENANT_ID,

    [string]$ClientId = $env:INTUNE_CLIENT_ID,

    [string]$ClientSecret = $env:INTUNE_CLIENT_SECRET,

    [string]$CertificateThumbprint = $env:INTUNE_CERT_THUMBPRINT,

    [string]$CertificatePath = $env:INTUNE_CERT_PATH,

    [securestring]$CertificatePassword = $(
        if (-not [string]::IsNullOrEmpty($env:INTUNE_CERT_PASSWORD)) {
            ConvertTo-SecureString -String $env:INTUNE_CERT_PASSWORD -AsPlainText -Force
        }
    ),

    # Restrict the run to one or more area folders. Empty means every folder found.
    [string[]]$Area = @(),

    # Local JSON file holding per-customer credentials. When supplied, the customer selected
    # from it is the TARGET tenant - the one written to. Same file and field names as
    # Export-IntuneConfigurationInventory.ps1.
    [string]$CustomerConfigPath,

    # Picks the target customer without prompting. Without it the run prompts.
    [string]$CustomerName,

    # Decode the token, report tenant, roles and the areas present in the source that it
    # cannot create, then exit. Reads nothing and writes nothing.
    [switch]$TestPermissionOnly,

    # Skip the one confirmation prompt before the first write. Scheduled runs need this;
    # interactive ones should not use it.
    [switch]$Force,

    # Where the run report is written. Empty means the source folder, next to the data it
    # describes, mirroring where the export puts its _manifest_. Point it elsewhere when the
    # source sits in a synchronised folder: the report names the target tenant's ID and every
    # policy name that was created.
    [ValidateScript({ Test-Path -Path $PSItem -PathType Container })]
    [string]$ReportDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Set before the customer region so StrictMode has something to read when no customer file
# is in play; the import report and the target banner both print it.
$script:TargetCustomerName = ''

#region Customer selection

# Resolves credentials from a local multi-customer JSON file. Self-contained on purpose:
# the script stays a single file that can be copied to a machine on its own.
#
# Same file, same field names and same four precedence rules as
# Export-IntuneConfigurationInventory.ps1, so one customers.json serves both. What differs is
# what the selection means: in the export it names the tenant being read, here it names the
# tenant being WRITTEN TO. Nothing checks that it is the tenant the source data came from -
# importing customer A's configuration into customer B is the whole point of the script.
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
    # The export reads tenantName, outputDirectory, includeConditionalAccess and jsonDepth
    # from the customer entry here. This script deliberately reads NONE. -SourceDirectory is
    # the one value that looks like a candidate and must never be one: it is the exported
    # data being imported, not a property of the target tenant, and letting a customer entry
    # supply it would make "which folder am I about to push into this tenant" depend on which
    # customer was picked. The omission is deliberate, not an oversight.
    $script:TargetCustomerName = [string]$customer["name"]
}

#endregion Customer selection

#region Credential preflight

# Validation attributes do not run on default values - enforce them explicitly so a missing
# environment variable fails here rather than as a cryptic HTTP error later.
foreach ($required in @(@{ Name = 'TenantId'; Value = $TenantId }, @{ Name = 'ClientId'; Value = $ClientId })) {
    if ([string]::IsNullOrWhiteSpace($required.Value)) {
        throw ('Missing {0}. Pass -{0} or set INTUNE_{1}.' -f $required.Name, $required.Name.ToUpperInvariant())
    }
}

if ($CertificateThumbprint -and $CertificatePath) {
    throw 'Specify either -CertificateThumbprint or -CertificatePath, not both.'
}

$useCertificate = -not ([string]::IsNullOrWhiteSpace($CertificateThumbprint) -and
                        [string]::IsNullOrWhiteSpace($CertificatePath))

if (-not $useCertificate -and [string]::IsNullOrWhiteSpace($ClientSecret)) {
    throw 'No credential supplied. Provide a certificate or a client secret.'
}

if ($useCertificate -and -not [string]::IsNullOrWhiteSpace($ClientSecret)) {
    Write-Verbose 'Certificate and client secret both present - the certificate wins.'
    $ClientSecret = $null
}

#endregion Credential preflight

# Two distinct types so the import loop can tell a global auth failure (abort) from a
# per-area permission gap (skip that area, keep importing the rest).
class GraphAuthenticationException : System.Exception {
    GraphAuthenticationException([string]$message) : base($message) {}
}
class GraphAuthorizationException : System.Exception {
    GraphAuthorizationException([string]$message) : base($message) {}
}

# Script-scoped state must exist before first read - StrictMode throws on unassigned variables.
# Certificate is populated in the Main region, once Get-ClientCertificate has been defined.
# Resolving it once up front rather than per token request matters because a Keychain lookup
# can prompt, and a bad certificate should surface before any Graph work starts. The resolved
# object is deliberately never disposed: New-ClientAssertion needs its private key to re-sign
# an assertion on every token renewal, not just the first, for the life of the run.
$script:AuthContext = @{ Token = $null; ExpiresOn = [datetime]::MinValue; Certificate = $null }

#region Helpers

function Get-ObjectProperty {
    # StrictMode Latest throws on missing properties of a PSCustomObject, and Graph omits
    # properties instead of returning null - so every property read goes through here.
    # CAUTION: an empty array value is unrolled by 'return' and comes back as $null.
    # Callers that must distinguish "property absent" from "property is an empty array"
    # have to probe PSObject.Properties directly - see Get-ExistingName.
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingEmptyCatchBlock', '',
        Justification = 'A non-JSON error body is not an error condition here - the fall-through below returns it verbatim.')]
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

function Write-Utf8File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )
    # No BOM: JSON consumers expect plain UTF-8, unlike the CSV where Excel needs the BOM.
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

# One of three copies - see SHARED CODE in the .NOTES block above. This one behaves like the
# export's (securestring password, catch widened to System.Exception) with the commentary
# trimmed; New-IntuneWin32AppJson.ps1's does not. They are not interchangeable.
function Get-ClientCertificate {
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
        $normalised = ($Thumbprint -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
        try {
            $store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadOnly)
            $match = $store.Certificates | Where-Object { $PSItem.Thumbprint -eq $normalised }
        }
        finally { $store.Close() }

        if (-not $match) { throw "No certificate with thumbprint '$normalised' in CurrentUser\My." }
        $certificate = @($match)[0]
        if (-not $certificate.HasPrivateKey) { throw "Certificate '$normalised' has no private key." }
        return $certificate
    }

    if ($Path) {
        if (-not (Test-Path -Path $Path -PathType Leaf)) {
            throw "Certificate file '$Path' does not exist or is not a file."
        }
        $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -Path $Path).Path)
        $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]
        try {
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $bytes, $Password, $flags::EphemeralKeySet)
        }
        catch [System.Exception] {
            # Broadened from PlatformNotSupportedException: a wrong PFX password throws
            # CryptographicException on the EphemeralKeySet attempt too, so a narrow catch
            # would only delay the same error to the retry below.
            Write-Verbose 'Could not load with EphemeralKeySet - retrying with the default key set.'
            $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $bytes, $Password, $flags::DefaultKeySet)
        }
        if (-not $certificate.HasPrivateKey) { throw "Certificate '$Path' has no private key." }
        return $certificate
    }

    return $null
}

function ConvertTo-Base64Url {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-ClientAssertion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$TokenUri
    )

    $now = [System.DateTimeOffset]::UtcNow
    $header = [ordered]@{
        alg = 'RS256'
        typ = 'JWT'
        x5t = ConvertTo-Base64Url -Bytes $Certificate.GetCertHash()
    }
    $payload = [ordered]@{
        aud = $TokenUri
        iss = $ClientId
        sub = $ClientId
        jti = [guid]::NewGuid().ToString()
        # MSAL sets nbf = iat = now. Keeping the claim set identical to a reference client
        # rather than relying on our own judgment about clock-skew tolerance.
        nbf = $now.ToUnixTimeSeconds()
        iat = $now.ToUnixTimeSeconds()
        exp = $now.AddMinutes(10).ToUnixTimeSeconds()
    }

    $encodedHeader = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $header -Compress)))
    $encodedPayload = ConvertTo-Base64Url -Bytes ([Text.Encoding]::UTF8.GetBytes(
        (ConvertTo-Json -InputObject $payload -Compress)))
    $signingInput = '{0}.{1}' -f $encodedHeader, $encodedPayload

    $privateKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($null -eq $privateKey) { throw 'Could not obtain the certificate private key for signing.' }

    $signature = $privateKey.SignData(
        [Text.Encoding]::UTF8.GetBytes($signingInput),
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

    return '{0}.{1}' -f $signingInput, (ConvertTo-Base64Url -Bytes $signature)
}

function Get-GraphAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Five-minute margin: a token that expires mid-import turns into a 401 on a POST, and a
    # POST that has already reached the service is not safe to blindly retry.
    if ($null -ne $script:AuthContext.Token -and
        $script:AuthContext.ExpiresOn -gt (Get-Date).AddMinutes(5)) {
        return $script:AuthContext.Token
    }

    $tokenUri = 'https://login.microsoftonline.com/{0}/oauth2/v2.0/token' -f $TenantId
    $body = @{
        client_id  = $ClientId
        scope      = 'https://graph.microsoft.com/.default'
        grant_type = 'client_credentials'
    }

    if ($null -ne $script:AuthContext.Certificate) {
        $body['client_assertion_type'] = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        $body['client_assertion'] = New-ClientAssertion -Certificate $script:AuthContext.Certificate `
            -ClientId $ClientId -TokenUri $tokenUri
    }
    else {
        $body['client_secret'] = $ClientSecret
    }

    $response = Invoke-RestMethod -Uri $tokenUri -Method Post -Body $body `
        -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

    $script:AuthContext.Token = $response.access_token
    $script:AuthContext.ExpiresOn = (Get-Date).AddSeconds([int]$response.expires_in)
    return $script:AuthContext.Token
}

function Invoke-GraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [ValidateSet('Get', 'Post')][string]$Method = 'Get',
        [string]$Body,
        [ValidateRange(1, 10)][int]$MaxAttempt = 5
    )

    $attempt = 0
    $tokenRefreshed = $false

    while ($true) {
        $attempt++
        try {
            $token = Get-GraphAccessToken
            $requestArgs = @{
                Uri         = $Uri
                Method      = $Method
                ErrorAction = 'Stop'
                Headers     = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
            }
            if ($Method -ne 'Get' -and -not [string]::IsNullOrEmpty($Body)) {
                # Bytes, not the string the export passes: this script POSTs policy names, and
                # letting Invoke-RestMethod pick an encoding for a name containing a, a or o
                # produces mojibake in the target tenant. The charset is stated explicitly for
                # the same reason.
                $requestArgs['Body'] = [Text.Encoding]::UTF8.GetBytes($Body)
                $requestArgs['ContentType'] = 'application/json; charset=utf-8'
            }
            # Deliberately not comma-guarded, unlike Get-ExistingName's return: every endpoint
            # this script calls answers with a single object - a {"value": [...]} envelope on
            # GET, the created resource on POST - so 'return' has no collection to unroll here.
            # Guarding it would instead hand every caller a one-element array.
            return Invoke-RestMethod @requestArgs
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
                    # Both fields, not just the token. The export nulls a single $script:TokenCache;
                    # here the cache is two fields, and Get-GraphAccessToken returns early on
                    # ExpiresOn alone - clearing only the token would hand the same rejected token
                    # straight back and turn a renewable 401 into a fatal one.
                    $script:AuthContext.Token = $null
                    $script:AuthContext.ExpiresOn = [datetime]::MinValue
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

            # Where this deliberately differs from the export, which retries 429/5xx/0 on
            # everything: a GET can be replayed freely and keeps that set. A POST cannot. A 5xx
            # or a dropped connection (status 0 - network error, timeout) can happen AFTER the
            # service has already created the policy, so replaying it creates a second copy and
            # there is no rollback. 429 is the one status that is safe on a POST: the request
            # was rejected before it was processed. Everything else on a POST is thrown to the
            # caller and becomes a 'failed' row carrying Graph's own message.
            $retryable = ($Method -eq 'Get') ? @(429, 500, 502, 503, 504, 0) : @(429)
            if ($statusCode -notin $retryable -or $attempt -ge $MaxAttempt) { throw }

            # Retry-After wins over backoff: Graph knows the actual throttle window, we don't.
            $delay = $retryAfterSeconds ?? [int][math]::Min([math]::Pow(2, $attempt), 60)
            Write-Warning ('Graph {0} on attempt {1}/{2}, waiting {3}s: {4}' -f $statusCode, $attempt, $MaxAttempt, $delay, $Uri)
            Start-Sleep -Seconds ([math]::Max($delay, 1))
        }
    }
}

function ConvertTo-AnnotationFreeObject {
    <#
        Graph annotates every $expand'd navigation property with '<name>@odata.context' - a
        receipt describing where the response came from. The annotation travels into the
        sidecar, and posting one back is rejected outright: in a request body OData allows
        exactly one annotation on a navigation link, '@odata.bind', so anything else fails
        model validation before the payload itself is looked at.

        $script:CommonRemove could not catch these. It holds two hard-coded top-level
        spellings, and the drop loop only ever compares it against top-level keys - while the
        copy that broke the compliance import sat one level down, inside each
        scheduledActionsForRule entry.

        Measured over one 20-file export: 1227 '@odata.type' keys, which MUST survive (they
        select the derived type and sit in four areas' Require list) and exactly two
        '@odata.context' keys, which must not. Hence keep-the-type, drop-the-rest rather than
        a list of known annotation names - a list would miss the next $expand the same way.
    #>
    [CmdletBinding()]
    # All three, or PSUseOutputTypeCorrectly flags the comma-guarded array return: the
    # dictionary branch gives a Hashtable, the collection branch an Object[], and a scalar
    # comes back as whatever it already was.
    [OutputType([hashtable], [object[]], [object])]
    param([Parameter(Mandatory)][AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return $null }
    # Strings are IEnumerable - must be handled before the collection branch.
    if ($InputObject -is [string]) { return $InputObject }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $clean = @{}
        foreach ($key in $InputObject.Keys) {
            if ($key -like '*@odata.*' -and $key -notlike '*@odata.type') { continue }
            $clean[$key] = ConvertTo-AnnotationFreeObject -InputObject $InputObject[$key]
        }
        return $clean
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = @(foreach ($element in $InputObject) { ConvertTo-AnnotationFreeObject -InputObject $element })
        # Comma guard, same reason as Get-ExistingName: a one-element array returned bare comes
        # back as the element itself, and a settings array of one would stop being an array.
        return , $list
    }

    return $InputObject
}

function ConvertTo-CreationBody {
    <#
        Turns a sidecar into something Graph will accept: drops the OData annotations that
        a request body may not carry, strips the service-owned properties, flattens the
        legacy double-wrapped settings array, and either injects the compliance scheduled
        action Graph insists on or clears the source tenant's ids off the one already there.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][hashtable]$Sidecar,
        [Parameter(Mandatory)][hashtable]$Definition,
        [Parameter(Mandatory)][string]$AreaName
    )

    # Annotations first: they are meaningless in a request body and one of them is a hard
    # rejection. See ConvertTo-AnnotationFreeObject.
    $Sidecar = ConvertTo-AnnotationFreeObject -InputObject $Sidecar

    $body = @{}
    $drop = @($script:CommonRemove) + @($Definition.Remove)
    foreach ($key in $Sidecar.Keys) {
        if ($key -in $drop) { continue }
        $body[$key] = $Sidecar[$key]
    }

    # Exports before v1.11.0 wrote 'settings' as [[{...}]] - the call site wrapped an
    # already comma-guarded collection a second time. Posting that creates a policy with no
    # settings at all. Detection is shape-based so the script keeps working once the export
    # is fixed: a genuine settings array holds objects, never a nested collection.
    if ($body.ContainsKey('settings') -and $null -ne $body['settings']) {
        $settings = @($body['settings'])
        if ($settings.Count -eq 1 -and $settings[0] -is [System.Collections.IList]) {
            Write-Verbose ('{0}: flattened a double-wrapped settings array.' -f $AreaName)
            $body['settings'] = @($settings[0])
        }
    }

    # Graph refuses to create a compliance policy without at least one scheduled action.
    # scheduledActionsForRule is a navigation property, so a plain collection GET omits it;
    # the export asks for it with $expand and a current sidecar therefore has it. Sidecars
    # from before that was added, and any run where the expanded query failed and the export
    # fell back to a flat one, do not - and those are the ones this fills in. A block action
    # with no grace period is the least surprising default, but it is still a decision the
    # script is making on the operator's behalf.
    if ($Definition.Resource -eq 'deviceManagement/deviceCompliancePolicies' -and
        -not $body.ContainsKey('scheduledActionsForRule')) {
        Write-Warning ('Compliance policy "{0}": no scheduled actions in the sidecar - creating with block after 0 hours. Review the grace period in the portal, and see "Known limitations" in README.md.' -f $body['displayName'])
        $body['scheduledActionsForRule'] = @(
            @{
                ruleName = 'PasswordRequired'
                scheduledActionConfigurations = @(
                    @{ actionType = 'block'; gracePeriodHours = 0; notificationTemplateId = '' }
                )
            }
        )
    }

    # Template-bound policies are validated against the TARGET tenant's revision of the
    # template, and one setting reference it does not recognise fails the whole POST. Say so
    # before the request rather than leaving it as a 400 afterwards. $body is a hashtable here,
    # not a Graph object, so this is ContainsKey - Get-ObjectProperty is for PSCustomObject.
    if ($Definition.Resource -eq 'deviceManagement/configurationPolicies' -and
        $body.ContainsKey('templateReference') -and
        $body['templateReference'] -is [System.Collections.IDictionary] -and
        $body['templateReference'].ContainsKey('templateFamily') -and
        [string]$body['templateReference']['templateFamily'] -ne 'none') {
        Write-Warning ('Settings Catalog policy "{0}" is bound to template family "{1}" - the target tenant validates every setting against its own revision of that template, and one unrecognised reference rejects the whole policy. See "Known limitations" in README.md.' -f
            $body['name'], [string]$body['templateReference']['templateFamily'])
    }

    # The other half of the same problem: a current sidecar HAS scheduledActionsForRule, and it
    # carries the source tenant's rule id - identical to the source policy id - plus one id per
    # action configuration. Stripped here rather than in $script:CommonRemove, which is
    # top-level only, and deliberately NOT recursively for every area: Settings Catalog
    # settings legitimately carry id "0", "1", ... and those imports work today.
    if ($Definition.Resource -eq 'deviceManagement/deviceCompliancePolicies' -and
        $body.ContainsKey('scheduledActionsForRule')) {
        foreach ($rule in @($body['scheduledActionsForRule'])) {
            if ($rule -isnot [System.Collections.IDictionary]) { continue }
            $rule.Remove('id')
            if (-not $rule.ContainsKey('scheduledActionConfigurations')) { continue }
            foreach ($action in @($rule['scheduledActionConfigurations'])) {
                if ($action -is [System.Collections.IDictionary]) { $action.Remove('id') }
            }
        }
    }

    return $body
}

function Test-CreationBody {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][hashtable]$Body,
        [Parameter(Mandatory)][hashtable]$Definition
    )

    foreach ($property in $Definition.Require) {
        if (-not $Body.ContainsKey($property)) { return ('missing required property "{0}"' -f $property) }
        $value = $Body[$property]
        if ($null -eq $value) { return ('required property "{0}" is null' -f $property) }
        if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) {
            return ('required property "{0}" is empty' -f $property)
        }
    }
    return ''
}

function Get-ExistingName {
    <#
        One call per area rather than one per file: a tenant has at most a few hundred
        policies per area, and the duplicate check is the only reason we read at all.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [Parameter(Mandatory)][string]$Resource,
        [Parameter(Mandatory)][string]$NameProperty
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $uri = 'https://graph.microsoft.com/beta/{0}?$select=id,{1}' -f $Resource, $NameProperty

    while (-not [string]::IsNullOrWhiteSpace($uri)) {
        $page = Invoke-GraphRequest -Uri $uri

        # Probe the property itself rather than going through Get-ObjectProperty: an empty
        # 'value' array is unrolled to $null on the way out of that function, which would
        # make an empty area look like a single object and put the raw Graph envelope into
        # the name set. The inner null check covers a literal "value": null, where @($null)
        # would otherwise add one null element.
        $valueProperty = $page.PSObject.Properties['value']
        if ($null -ne $valueProperty -and $null -ne $valueProperty.Value) {
            foreach ($item in @($valueProperty.Value)) {
                # A name is always a scalar string, so the unrolling caveat above does not apply.
                $name = [string](Get-ObjectProperty -InputObject $item -Name $NameProperty)
                if (-not [string]::IsNullOrWhiteSpace($name)) {
                    [void]$names.Add($name)
                }
            }
        }
        $uri = [string](Get-ObjectProperty -InputObject $page -Name '@odata.nextLink')
    }

    # Comma guard: PowerShell enumerates a collection on the way out of a function, so a
    # bare return turns an empty set into $null and a one-item set into a bare string.
    # Both silently break the duplicate check - $null throws, a string does substring
    # matching, and an Object[] falls back to case-sensitive comparison.
    return , $names
}

#endregion Helpers

#region Area definitions

# Keyed by the export's area folder name. NameProperty differs: configurationPolicies and
# assignmentFilters call it 'name', everything else 'displayName'.
#
# Remove: properties the service owns. Some make Graph reject the request outright, the rest
# are silently ignored - either way they do not belong in a creation body.
# Require: without these the POST either fails or creates something useless.
#
# RequiredScope: the application permission Graph demands to CREATE this resource, read off
# each endpoint's own Create page - NOT derived from the export's read scopes by swapping
# Read for ReadWrite. Assignment-Filter is why: the export reads assignmentFilters with
# DeviceManagementServiceConfig.Read.All, but creating one needs
# DeviceManagementConfiguration.ReadWrite.All. Deriving it would have produced a preflight
# that passes and a POST that 403s.
# The three script areas moved from DeviceManagementConfiguration.* to
# DeviceManagementScripts.ReadWrite.All on 2025-07-31; older documentation says otherwise.
$script:AreaMap = [ordered]@{
    'Assignment-Filter' = @{
        Resource = 'deviceManagement/assignmentFilters'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        Remove = @('payloads')
        Require = @('displayName', 'platform', 'rule')
    }
    'Settings-Catalog' = @{
        Resource = 'deviceManagement/configurationPolicies'
        NameProperty = 'name'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        # settingDefinitions only exists in exports run with -IncludeSettingDefinitions; it is
        # documentation payload, not configuration.
        Remove = @('creationSource', 'settingCount', 'priorityMetaData', 'settingDefinitions', 'isAssigned')
        Require = @('name', 'platforms', 'technologies', 'settings')
    }
    'Device-Configuration-Templates' = @{
        Resource = 'deviceManagement/deviceConfigurations'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        Remove = @('supportsScopeTags')
        Require = @('displayName', '@odata.type')
    }
    'Compliance-Policy' = @{
        Resource = 'deviceManagement/deviceCompliancePolicies'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        Remove = @()
        Require = @('displayName', '@odata.type')
    }
    'Remediation-Script' = @{
        Resource = 'deviceManagement/deviceHealthScripts'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementScripts.ReadWrite.All'
        Remove = @('isGlobalScript', 'highestAvailableVersion')
        Require = @('displayName', 'detectionScriptContent', 'remediationScriptContent')
    }
    'Platform-Script-Windows' = @{
        Resource = 'deviceManagement/deviceManagementScripts'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementScripts.ReadWrite.All'
        Remove = @()
        Require = @('displayName', 'scriptContent')
    }
    'Shell-Script-macOS' = @{
        Resource = 'deviceManagement/deviceShellScripts'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementScripts.ReadWrite.All'
        Remove = @()
        Require = @('displayName', 'scriptContent')
    }
    'Autopilot-Deployment-Profile' = @{
        Resource = 'deviceManagement/windowsAutopilotDeploymentProfiles'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementServiceConfig.ReadWrite.All'
        Remove = @()
        Require = @('displayName', '@odata.type')
    }
    'Windows-Feature-Update-Profile' = @{
        Resource = 'deviceManagement/windowsFeatureUpdateProfiles'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        Remove = @('endOfSupportDate', 'deployableContentDisplayName')
        Require = @('displayName', 'featureUpdateVersion')
    }
    'Windows-Quality-Update-Profile' = @{
        Resource = 'deviceManagement/windowsQualityUpdateProfiles'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        Remove = @('releaseDateTime', 'deployableContentDisplayName')
        Require = @('displayName')
    }
    'Windows-Driver-Update-Profile' = @{
        Resource = 'deviceManagement/windowsDriverUpdateProfiles'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All'
        Remove = @('newUpdates', 'deviceReporting', 'inventorySyncStatus')
        Require = @('displayName', 'approvalType')
    }
    'App-Protection-Policy-iOS' = @{
        Resource = 'deviceAppManagement/iosManagedAppProtections'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementApps.ReadWrite.All'
        Remove = @('deployedAppCount', 'isAssigned', 'apps')
        Require = @('displayName')
    }
    'App-Protection-Policy-Android' = @{
        Resource = 'deviceAppManagement/androidManagedAppProtections'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementApps.ReadWrite.All'
        Remove = @('deployedAppCount', 'isAssigned', 'apps')
        Require = @('displayName')
    }
    'App-Configuration-Managed-Apps' = @{
        Resource = 'deviceAppManagement/targetedManagedAppConfigurations'
        NameProperty = 'displayName'
        RequiredScope = 'DeviceManagementApps.ReadWrite.All'
        Remove = @('deployedAppCount', 'isAssigned', 'apps')
        Require = @('displayName')
    }
}

# Present in an export but not creatable from a single POST. Listed explicitly so the run
# reports them rather than leaving the operator wondering why a folder was ignored.
$script:UnsupportedAreas = [ordered]@{
    'Group-Policy-Configuration-ADMX'    = 'needs the container created first, then one definitionValue per setting'
    'Endpoint-Security-Intent'           = 'bound to a template ID that is not portable between tenants'
    'Enrollment-Configuration'           = 'largely tenant singletons that cannot be created, only edited'
    'App-Configuration-Managed-Devices'  = 'references app IDs that do not exist in the target tenant'
    'Application'                        = 'needs content upload, not a JSON body'
}

# Properties the service owns on every resource type.
# The two '@odata.context' entries are redundant since ConvertTo-AnnotationFreeObject took
# over annotation removal generally - they are left in place because they cost nothing and
# this list is what someone reads when looking for service-owned properties. The general
# rule lives in that function, not here: this list is compared against top-level keys only.
$script:CommonRemove = @(
    'id', 'createdDateTime', 'lastModifiedDateTime', 'version', 'assignments',
    '@odata.context', 'assignments@odata.context', 'roleScopeTagIds'
)

#endregion Area definitions

#region Main

if ($useCertificate) {
    $script:AuthContext.Certificate = Get-ClientCertificate -Thumbprint $CertificateThumbprint `
        -Path $CertificatePath -Password $CertificatePassword
    Write-Verbose ('Authenticating with certificate {0} (expires {1:yyyy-MM-dd})' -f
        $script:AuthContext.Certificate.Thumbprint, $script:AuthContext.Certificate.NotAfter)
}

$sourceDirectoryResolved = (Resolve-Path -Path $SourceDirectory).Path

$folders = Get-ChildItem -Path $sourceDirectoryResolved -Directory | Sort-Object -Property Name
if (@($folders).Count -eq 0) {
    throw ('No area sub-folders in "{0}". Copy the export''s area folders, not loose JSON files. If this is an export run folder from 1.12.0 or later, unpack <Tenant>_<stamp>_sidecars.zip first - the area folders live inside the archive.' -f $sourceDirectoryResolved)
}

# The '_' prefix is the export's convention for run-level files, and it is this script's
# convention for its own report. Skipping them keeps a second run from warning about the
# first run's _importreport_ and about the export's own _manifest_ / _changeset_ files.
$looseFiles = @(Get-ChildItem -Path $sourceDirectoryResolved -File -Filter '*.json' |
    Where-Object { -not $PSItem.Name.StartsWith('_') })
if ($looseFiles.Count -gt 0) {
    Write-Warning ('{0} JSON file(s) sit directly in the source root and were ignored - the area folder is what selects the endpoint.' -f $looseFiles.Count)
}

# Preflight: report which of the areas actually present in the source the token cannot
# create. Advisory only, never blocking - a 403 on the area is what really stops it, and
# that is handled in the loop below. Areas with no folder here are not worth a warning.
$claims = ConvertFrom-JwtPayload -Token (Get-GraphAccessToken)
# Filtered rather than the export's bare @(Get-ObjectProperty ...): an absent 'roles' claim
# comes back as $null, and @($null) is a one-element array, so an unfiltered count never
# reaches zero and the warning below would never fire.
$grantedRoles = @(Get-ObjectProperty -InputObject $claims -Name 'roles' |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$PSItem) } |
    ForEach-Object { [string]$PSItem })
$tokenTenantId = [string](Get-ObjectProperty -InputObject $claims -Name 'tid')

Write-Verbose ('Target tenant  : {0}' -f $tokenTenantId)
Write-Verbose ('Token appid    : {0}' -f [string](Get-ObjectProperty -InputObject $claims -Name 'appid'))
Write-Verbose ('Token roles    : {0}' -f (($grantedRoles.Count -gt 0) ? ($grantedRoles -join ', ') : '<none>'))

if ($grantedRoles.Count -eq 0) {
    Write-Warning 'The token contains no "roles" claim. The app registration has no admin-consented APPLICATION permissions - delegated permissions are ignored by the client credentials flow.'
}

$areasPresent = @($folders |
    Where-Object { $script:AreaMap.Contains($PSItem.Name) } |
    ForEach-Object { [string]$PSItem.Name })

# Test-RoleSatisfied is the export's, written for Read scopes, and is correct here unchanged:
# its '.Read.' -> '.ReadWrite.' widening cannot match inside a '...ReadWrite.All' string
# (what follows '.Read' there is 'W', not '.'), so for a ReadWrite requirement it collapses
# to exact matching, which is what creating needs.
$blockedAreas = @($areasPresent | Where-Object {
    -not (Test-RoleSatisfied -GrantedRole $grantedRoles -RequiredRole $script:AreaMap[$PSItem].RequiredScope)
})

if ($TestPermissionOnly) {
    # Member enumeration over an empty collection throws under StrictMode Latest.
    Write-Output ([pscustomobject]@{
        TenantId      = $tokenTenantId
        GrantedRoles  = (@($grantedRoles | ForEach-Object { [string]$PSItem }) -join ', ')
        AreasPresent  = (@($areasPresent | ForEach-Object { [string]$PSItem }) -join ', ')
        BlockedAreas  = (@($blockedAreas | ForEach-Object { '{0} (needs {1})' -f $PSItem, $script:AreaMap[$PSItem].RequiredScope }) -join ', ')
        AllAreasReady = ($blockedAreas.Count -eq 0)
    })
    return
}

foreach ($blocked in $blockedAreas) {
    Write-Warning ('{0} will likely fail - token lacks {1}.' -f $blocked, $script:AreaMap[$blocked].RequiredScope)
}

# The export's manifest, if the source is an export run folder. It carries the tenant the
# data came FROM, which is the one thing that makes "these are not the same customer"
# visible, and it costs no Graph call.
$script:SourceTenantId = ''
$script:SourceTenantName = ''
$script:SourceRun = ''
$sourceManifest = @(Get-ChildItem -Path $sourceDirectoryResolved -File -Filter '_manifest_*.json' |
    Sort-Object -Property Name)
if ($sourceManifest.Count -gt 0) {
    try {
        $manifestData = Get-Content -Path $sourceManifest[-1].FullName -Raw -Encoding utf8 | ConvertFrom-Json
        $script:SourceTenantId = [string](Get-ObjectProperty -InputObject $manifestData -Name 'tenantId')
        $script:SourceTenantName = [string](Get-ObjectProperty -InputObject $manifestData -Name 'tenantName')
        # ConvertFrom-Json turns the export's yyyy-MM-ddTHH:mm:ss into a [datetime], and a bare
        # [string] cast on one of those renders it in the current culture - "08/20/2026" here,
        # "2026-08-20" on the next machine. Put it back into the export's own format.
        $sourceRunValue = Get-ObjectProperty -InputObject $manifestData -Name 'runTimestampLocal'
        $script:SourceRun = [string]$sourceRunValue
        if ($sourceRunValue -is [datetime]) { $script:SourceRun = $sourceRunValue.ToString('yyyy-MM-ddTHH:mm:ss') }
    }
    catch [System.Exception] {
        # An unreadable manifest costs the banner one line of context, nothing more.
        Write-Warning ('Could not read {0}: {1}' -f $sourceManifest[-1].Name, $PSItem.Exception.Message)
    }
}

# The banner is what the operator reads before typing YES, so it describes what will actually
# be attempted: -Area, the unsupported list and unknown folder names all applied. The loop
# below still walks every folder - it has to, to report 'unsupported' and 'unknown-area' rows.
$selectedFolders = @($folders | Where-Object {
    ($Area.Count -eq 0 -or $PSItem.Name -in $Area) -and
    -not $script:UnsupportedAreas.Contains($PSItem.Name) -and
    $script:AreaMap.Contains($PSItem.Name)
})
$selectedFileCount = @($selectedFolders | ForEach-Object { Get-ChildItem -Path $PSItem.FullName -File -Filter '*.json' }).Count
$sourceLabel = 'no export manifest'
if ($script:SourceTenantId -or $script:SourceRun) {
    $sourceLabel = 'export {0}, {1} / {2}' -f $script:SourceRun, $script:SourceTenantName, $script:SourceTenantId
}
$targetLabel = $tokenTenantId
if (-not [string]::IsNullOrWhiteSpace($script:TargetCustomerName)) {
    $targetLabel = '{0}  ({1})' -f $script:TargetCustomerName, $tokenTenantId
}

Write-Host ''
Write-Host ('Source : {0}' -f $sourceDirectoryResolved) -ForegroundColor Cyan
Write-Host ('         ({0})' -f $sourceLabel)
Write-Host ('Target : {0}' -f $targetLabel) -ForegroundColor Yellow -NoNewline
Write-Host ($WhatIfPreference ? '   DRY RUN' : '   WRITE') -ForegroundColor ($WhatIfPreference ? 'Green' : 'Red')
Write-Host ('Areas  : {0} of {1} folder(s) selected, {2} file(s)' -f $selectedFolders.Count, $folders.Count, $selectedFileCount)
Write-Host ''

# One gate for the whole run, not ConfirmImpact = 'High' - that asks once per object, and an
# operator clicking through eighteen prompts has stopped reading by the third. Asked only
# when something will actually be written and there is someone at the keyboard to answer:
# a redirected stdin means a scheduled run, where Read-Host would block forever.
$sessionIsInteractive = [Environment]::UserInteractive -and -not [System.Console]::IsInputRedirected
if (-not $WhatIfPreference -and -not $Force) {
    if ($sessionIsInteractive) {
        $answer = Read-Host 'Create the above in the TARGET tenant? Type YES to continue'
        if ($answer -cne 'YES') { throw 'Aborted at the confirmation prompt. Nothing was created.' }
    }
    else {
        Write-Warning 'Non-interactive session - the confirmation prompt was skipped. Use -Force to make that explicit.'
    }
}

$results = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Result {
    # CreatedId is its own field rather than being stuffed into Detail: Detail carries the
    # reason a row ended up with the status it has, and for a failure that reason is Graph's
    # own message. One column cannot be both.
    param(
        [string]$AreaName, [string]$File, [string]$Name, [string]$Status,
        [string]$Detail, [string]$CreatedId = ''
    )
    $results.Add([pscustomobject][ordered]@{
        Area = $AreaName; File = $File; Name = $Name
        Status = $Status; Detail = $Detail; CreatedId = $CreatedId
    })
}

# One instant, three representations: UTC for the record, local for the file name, offset so
# the two can be reconciled. Same convention as the export's manifest.
$runLocal = Get-Date
$runUtc = $runLocal.ToUniversalTime()
$fileStamp = $runLocal.ToString('yyyy-MM-dd_HHmm')

$runComplete = $false
$abortReason = ''

# The report is the only record of what was created, and there is no rollback - so it is
# written in 'finally', not after the loop. The case that needs it most is the one that never
# reaches the end: a global 401 halfway through leaves objects in the target tenant that
# exist nowhere else in writing.
try {
    foreach ($folder in $folders) {
        $areaName = $folder.Name

        if ($Area.Count -gt 0 -and $areaName -notin $Area) {
            Write-Verbose ('{0}: not selected by -Area, skipping.' -f $areaName)
            continue
        }

        if ($script:UnsupportedAreas.Contains($areaName)) {
            Write-Warning ('{0}: not supported - {1}.' -f $areaName, $script:UnsupportedAreas[$areaName])
            Add-Result -AreaName $areaName -File '' -Name '' -Status 'unsupported' -Detail $script:UnsupportedAreas[$areaName]
            continue
        }

        if (-not $script:AreaMap.Contains($areaName)) {
            Write-Warning ('{0}: unknown area folder, skipping. Expected one of: {1}' -f $areaName, ($script:AreaMap.Keys -join ', '))
            Add-Result -AreaName $areaName -File '' -Name '' -Status 'unknown-area' -Detail 'folder name does not match a known export area'
            continue
        }

        $definition = $script:AreaMap[$areaName]
        $files = @(Get-ChildItem -Path $folder.FullName -File -Filter '*.json' | Sort-Object -Property Name)
        if ($files.Count -eq 0) {
            Write-Verbose ('{0}: no JSON files.' -f $areaName)
            continue
        }

        Write-Verbose ('{0}: {1} file(s) -> {2}' -f $areaName, $files.Count, $definition.Resource)
        try {
            $existing = Get-ExistingName -Resource $definition.Resource -NameProperty $definition.NameProperty
        }
        catch [GraphAuthenticationException] {
            # Global: the token itself is not accepted. Nothing else will work either, so the
            # run ends here and 'finally' writes what was created up to this point.
            throw ('Aborting: {0}{1}If the message names no specific scope, this is not a permission problem - verify that the tenant has an active Intune licence.' -f
                $PSItem.Exception.Message, [System.Environment]::NewLine)
        }
        catch [GraphAuthorizationException] {
            # Local: this resource needs a scope the token lacks. One row for the area, not one
            # per file - every file in it would fail for the identical reason.
            Write-Warning ('{0}: skipped - {1}' -f $areaName, $PSItem.Exception.Message)
            Add-Result -AreaName $areaName -File '' -Name '' -Status 'blocked' -Detail $PSItem.Exception.Message
            continue
        }
        $targetUri = 'https://graph.microsoft.com/beta/{0}' -f $definition.Resource

        foreach ($file in $files) {
            $displayName = ''
            try {
                $sidecar = Get-Content -Path $file.FullName -Raw -Encoding utf8 |
                    ConvertFrom-Json -AsHashtable -Depth 50

                $body = ConvertTo-CreationBody -Sidecar $sidecar -Definition $definition -AreaName $areaName
                $displayName = $body.ContainsKey($definition.NameProperty) ? [string]$body[$definition.NameProperty] : ''

                $problem = Test-CreationBody -Body $body -Definition $definition
                if ($problem) {
                    Write-Warning ('{0}: skipped - {1}.' -f $file.Name, $problem)
                    Add-Result -AreaName $areaName -File $file.Name -Name $displayName -Status 'invalid' -Detail $problem
                    continue
                }

                if ($existing.Contains($displayName)) {
                    Write-Verbose ('{0}: "{1}" already exists in the tenant, skipping.' -f $areaName, $displayName)
                    Add-Result -AreaName $areaName -File $file.Name -Name $displayName -Status 'duplicate' -Detail 'a policy with this name already exists'
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess(('{0} "{1}"' -f $areaName, $displayName), 'Create in tenant')) {
                    Add-Result -AreaName $areaName -File $file.Name -Name $displayName -Status 'whatif' -Detail $definition.Resource
                    continue
                }

                $json = ConvertTo-Json -InputObject $body -Depth 50
                $created = Invoke-GraphRequest -Uri $targetUri -Method 'POST' -Body $json

                $createdId = [string](Get-ObjectProperty -InputObject $created -Name 'id')

                # Added to the local set so two files with the same name in one run cannot both
                # be created.
                [void]$existing.Add($displayName)
                Write-Verbose ('{0}: created "{1}" ({2}).' -f $areaName, $displayName, $createdId)
                Add-Result -AreaName $areaName -File $file.Name -Name $displayName -Status 'created' `
                    -Detail $definition.Resource -CreatedId $createdId
            }
            catch [GraphAuthenticationException] {
                # Same global abort as above. Must be declared before the catch-all below, or
                # the untyped handler swallows it and the run limps on with a dead token.
                throw ('Aborting: {0}{1}If the message names no specific scope, this is not a permission problem - verify that the tenant has an active Intune licence.' -f
                    $PSItem.Exception.Message, [System.Environment]::NewLine)
            }
            catch [GraphAuthorizationException] {
                # A 403 that only shows up on the POST: the duplicate read needs a Read scope,
                # creating needs ReadWrite, and an app can hold one without the other. One row
                # for the area, then on to the next - the remaining files would all fail the
                # same way.
                Write-Warning ('{0}: skipped - {1}' -f $areaName, $PSItem.Exception.Message)
                Add-Result -AreaName $areaName -File '' -Name '' -Status 'blocked' -Detail $PSItem.Exception.Message
                break
            }
            catch {
                # One bad file must not abort the rest of the import; the summary is what the
                # operator acts on. Get-GraphErrorDetail rather than Exception.Message alone:
                # the bare message is "400 (Bad Request)" and says nothing about which property
                # Graph objected to.
                $message = Get-GraphErrorDetail -ErrorRecord $PSItem
                Write-Warning ('{0}: failed - {1}' -f $file.Name, $message)
                Add-Result -AreaName $areaName -File $file.Name -Name $displayName -Status 'failed' -Detail $message
            }
        }
    }
    # A misspelt -Area value matches no folder, the filter at the top of the loop skips every
    # folder there is, and the run ends with zero rows and nothing said about why. Name them.
    $folderNames = @($folders | ForEach-Object { [string]$PSItem.Name })
    foreach ($requestedArea in $Area) {
        if ($requestedArea -notin $folderNames) {
            Write-Warning ('-Area "{0}" matched no folder in "{1}". Folders present: {2}' -f
                $requestedArea, $sourceDirectoryResolved, ($folderNames -join ', '))
        }
    }

    $runComplete = $true
}
catch [System.Exception] {
    $abortReason = $PSItem.Exception.Message
    throw
}
finally {
    # Fixed key list rather than Group-Object: a status that did not occur has to read as 0,
    # not be missing. "no rows" and "did not happen" are different states, and both have to
    # be legible without interpreting the warning stream.
    # 'unknown-area' keeps the spelling the result rows have always used; the report key is
    # camelCase like every other field in the schema.
    $statusKeyByStatus = [ordered]@{
        'created'      = 'created'
        'duplicate'    = 'duplicate'
        'invalid'      = 'invalid'
        'failed'       = 'failed'
        'whatif'       = 'whatif'
        'unsupported'  = 'unsupported'
        'unknown-area' = 'unknownArea'
        'blocked'      = 'blocked'
    }
    $totals = [ordered]@{}
    foreach ($statusKey in $statusKeyByStatus.Values) { $totals[$statusKey] = 0 }
    foreach ($row in $results) {
        if ($statusKeyByStatus.Contains($row.Status)) { $totals[$statusKeyByStatus[$row.Status]]++ }
    }

    $report = [ordered]@{
        schemaVersion      = 1
        runTimestampUtc    = $runUtc.ToString('o')
        runTimestampLocal  = $runLocal.ToString('yyyy-MM-ddTHH:mm:ss')
        utcOffset          = [System.TimeZoneInfo]::Local.GetUtcOffset($runLocal).ToString()
        timeZone           = [System.TimeZoneInfo]::Local.Id
        scriptVersion      = '1.1.1'
        whatIf             = [bool]$WhatIfPreference
        targetTenantId     = $tokenTenantId
        targetCustomerName = $script:TargetCustomerName
        sourceDirectory    = $sourceDirectoryResolved
        sourceTenantId     = $script:SourceTenantId
        sourceTenantName   = $script:SourceTenantName
        sourceRun          = $script:SourceRun
        areasSelected      = (@($Area | ForEach-Object { [string]$PSItem }) -join ', ')
        runComplete        = $runComplete
        abortReason        = $abortReason
        totals             = $totals
        results            = @($results | ForEach-Object {
            [ordered]@{
                area      = $PSItem.Area
                file      = $PSItem.File
                name      = $PSItem.Name
                status    = $PSItem.Status
                detail    = $PSItem.Detail
                createdId = $PSItem.CreatedId
            }
        })
    }

    $reportRoot = [string]::IsNullOrWhiteSpace($ReportDirectory) ? $sourceDirectoryResolved : (Resolve-Path -Path $ReportDirectory).Path
    $reportPath = Join-Path -Path $reportRoot -ChildPath ('_importreport_{0}.json' -f $fileStamp)
    try {
        # Written on a -WhatIf run too. A dry run that produces a file you can read afterwards
        # is the point of the dry run; whatIf: true is what tells the two apart.
        Write-Utf8File -Path $reportPath -Content (ConvertTo-Json -InputObject $report -Depth 6)
        Write-Verbose ('Report: {0}' -f $reportPath)
    }
    catch [System.Exception] {
        # Never let a failed report write replace the exception that caused the abort.
        Write-Warning ('Could not write the import report to "{0}": {1}' -f $reportPath, $PSItem.Exception.Message)
    }
}

$summary = $results | Group-Object -Property Status |
    Sort-Object -Property Name |
    ForEach-Object { '{0}={1}' -f $PSItem.Name, $PSItem.Count }

Write-Verbose ('Done. {0}' -f ($summary -join ', '))
Write-Output $results

#endregion Main