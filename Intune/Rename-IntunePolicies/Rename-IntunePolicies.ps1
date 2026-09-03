<#
.SYNOPSIS
    Exports Intune policy names to a CSV and applies an edited copy of that CSV back to the
    tenant, via Microsoft Graph REST.

.DESCRIPTION
    Two modes, run as two separate commands. There is no combined path.

    MODE 1 - Export (default):
        Reads policies from Graph and writes one CSV row per policy:

            Id, GraphType, CurrentName, NewName

        NewName is pre-filled with CurrentName so the file can be edited in place. Nothing in
        the tenant is touched.

    MODE 2 - Rename (-ImportCsv <path>):
        Reads the edited CSV and applies every row whose NewName differs from its CurrentName,
        one PATCH each. One confirmation gate for the whole run, a run report written whenever
        the run reaches the rename loop, and no rollback.

    The script has no opinion about what a name should be. It does not parse names, does not
    derive names and does not know about any naming convention. What you type in NewName is
    what the policy is called afterwards.

    The one thing it does refuse: two policies of the same type ending up with the same name.
    Intune requires names to be unique per policy type, so that run would fail halfway and
    leave the tenant half-renamed.

    Only displayName / name is written. Assignments, descriptions and settings are never
    touched.

.NOTES
    REQUIRED MICROSOFT GRAPH *APPLICATION* PERMISSIONS (admin consent required), read off
    each endpoint's own Update page rather than derived from a Read scope:

        DeviceManagementConfiguration.ReadWrite.All - deviceConfigurations,
                                                      configurationPolicies,
                                                      deviceCompliancePolicies,
                                                      assignmentFilters,
                                                      windowsFeatureUpdateProfiles,
                                                      windowsQualityUpdateProfiles,
                                                      windowsDriverUpdateProfiles
        DeviceManagementScripts.ReadWrite.All       - deviceHealthScripts,
                                                      deviceManagementScripts
        DeviceManagementServiceConfig.ReadWrite.All - windowsAutopilotDeploymentProfiles

    OPTIONAL:
        Organization.Read.All                       - tenant display name in the banner.
                                                      Without it the banner shows the GUID.

    assignmentFilters is the one worth stating explicitly: it is READ with
    DeviceManagementServiceConfig.Read.All but PATCHED with
    DeviceManagementConfiguration.ReadWrite.All. Deriving the write scope from the read
    scope produces a preflight that passes and a PATCH that 403s.

    No Microsoft.Graph module and no interactive sign-in. Raw REST, client credentials.

    Error semantics: Intune names the missing scope on 403 ("Application must have one of
    the following scopes: ..."). A 401 with a generic Forbidden and no scope name is not a
    permission problem - check that the tenant has an active Intune licence.

    DATA SENSITIVITY: the exported CSV and the run report list every policy name in the
    tenant together with its object ID. That is a map of the customer's security
    configuration. Both files are unencrypted and inherit the permissions of the folder
    they are written to. Do not leave them in a synchronised folder (OneDrive, Dropbox)
    unless that is a deliberate decision.

    THERE IS NO ROLLBACK. The exported CSV and the run report are the only record of the
    previous names. To undo a run, swap the CurrentName and NewName columns of
    _renamereport_<stamp>.csv and run mode 2 against the result.

    Secrets: read from environment variables by default. Prefer SecretManagement or a
    certificate credential over a client secret for anything long-lived. A secret passed as
    -ClientSecret lands in PSReadLine history, any active transcript and potentially the
    process list.

    Certificate authentication (-CertificateThumbprint or -CertificatePath) is preferred
    over a client secret and takes precedence whenever a certificate is resolved. On macOS
    the CurrentUser\My store is Keychain-backed and signing triggers a Keychain dialog that
    pwsh -NonInteractive does not suppress, so thumbprint lookup is for interactive use;
    -CertificatePath is what unattended runs need.

    SHARED CODE, AND IT IS NOT IN SYNC. Get-ClientCertificate, ConvertTo-Base64Url and
    New-ClientAssertion here were copied verbatim from
    Export-IntuneConfigurationInventory.ps1 v1.12.1 on 2026-09-01. Four copies of
    Get-ClientCertificate now exist in this repository and they have deliberately drifted -
    see the SHARED CODE note in Import-IntuneConfigurationFromJson.ps1. Do not paste
    another copy over these. Change the copy you are working on and record it in the
    changelog below.

    Version:        2.0.0
    Creation Date:  2026-07-31
    Last Updated:   2026-09-01
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    CHANGELOG

        2.0.0 - 2026-09-01
            The naming standard is gone. The script no longer derives names, and a CSV
            produced by 1.0.0 is not valid input to this version.

            1.0.0 read each policy's name, tried to work out what it should be called under
            the OS-SCOPE-TARGET-TYP-KAT-Name convention, and graded every guess with a
            Confidence column the reviewer had to audit row by row. That was the wrong
            division of labour: the script cannot know whether a policy is Base or Custom,
            or whether it targets users or devices, so a large share of every run came out
            Assumed or Unresolved and had to be corrected by hand anyway.

            What replaces it is what the review step was actually for. Mode 1 exports
            Id, GraphType, CurrentName and NewName, with NewName pre-filled from
            CurrentName. You edit the names. Mode 2 applies them. Nothing is inferred.

            Removed: Get-StandardName, Test-StandardName, ConvertTo-OsToken, the standard's
            OS / SCOPE / TARGET / TYP / KAT tables, the redundant-word cleanup, the
            Confidence and Reason columns, and the -DefaultScope and -AllowUnresolved
            parameters.

            Kept from 1.0.0, because none of it depended on the convention: the two-mode
            split, the client-credentials authentication with certificate support, the
            collision check, the one YES gate, the run report written from a finally block,
            and the per-endpoint Update scopes.

            Mode 2 gained a duplicate-Id check and trims leading and trailing whitespace
            from NewName, warning when it had to. Both are Excel damage that is invisible
            in the spreadsheet and permanent in the tenant.

            Fixed before this version was ever committed, found in review: a 403 reading a
            type's existing names left $existingByType[$type] empty, which the collision
            check read as "no collisions" rather than "unverifiable" - two rows could be
            PATCHed to the same name with no warning and without -Force. Rows of a type
            whose names could not be read are now pulled out before the collision check and
            recorded as blocked instead. Also: a CSV with a Confidence column (one from
            1.0.0) is now rejected rather than silently accepted, which is what the
            paragraph above already claimed. Get-ExistingPolicyName now carries
            @odata.type, removing the extra per-policy GET in Set-PolicyName for the common
            case; it stays as a fallback.

        1.0.0 - 2026-09-01
            First versioned release. Reworked the pre-1.0 script onto the export script's
            authentication, added the two-mode split, the collision check, the run report
            and four endpoints (Windows feature/quality/driver update profiles, Autopilot).
            Its name-derivation logic is the part 2.0.0 removed.

.EXAMPLE
    # Mode 1 - export the current names. Writes a CSV, changes nothing in the tenant.
    $env:INTUNE_CLIENT_SECRET = '<secret>'
    .\Rename-IntunePolicies.ps1 -TenantId '<guid>' -ClientId '<guid>' -Verbose

.EXAMPLE
    # Mode 1 against one customer from a credential file, limited to two policy types.
    .\Rename-IntunePolicies.ps1 -CustomerConfigPath ~/.intune/customers.json `
        -CustomerName 'Contoso' -PolicyType Configuration, SettingsCatalog `
        -CsvPath ~/Desktop/contoso-names.csv

.EXAMPLE
    # Mode 2 - dry run first, every time. Writes the run report, PATCHes nothing.
    .\Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/contoso-names.csv `
        -CustomerConfigPath ~/.intune/customers.json -CustomerName 'Contoso' -WhatIf

.EXAMPLE
    # Mode 2 for real. One YES gate, then the renames.
    .\Rename-IntunePolicies.ps1 -ImportCsv ~/Desktop/contoso-names.csv `
        -CustomerConfigPath ~/.intune/customers.json -CustomerName 'Contoso'

.EXAMPLE
    # Permission check only - decodes the token, reports tenant, roles and blocked types.
    .\Rename-IntunePolicies.ps1 -TenantId '<guid>' -ClientId '<guid>' -TestPermissionOnly
#>

#Requires -Version 7.4

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Export')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Plaintext originates outside the script; conversion is the containment point.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost', '',
    Justification = 'The customer picker and the target banner are console UI. Write-Output would put them in the pipeline this script returns its results on, and Write-Verbose would hide the very prompt the operator has to answer.')]
param(
    # Mode 1 only. Restricts the export to policies whose current name starts with this value,
    # for example "Windows - ". Empty means every policy of the selected types.
    [Parameter(ParameterSetName = 'Export')]
    [string]$Prefix = '',

    # Mode 1 only. Keys from $script:EndpointMap; 'All' is every one of them.
    [Parameter(ParameterSetName = 'Export')]
    [ValidateSet('Configuration', 'SettingsCatalog', 'Compliance', 'Remediation', 'PlatformScript',
        'Filter', 'WindowsFeatureUpdate', 'WindowsQualityUpdate', 'WindowsDriverUpdate', 'Autopilot', 'All')]
    [string[]]$PolicyType = @('All'),

    # Mode 1: where the CSV is written. Defaults to the script folder.
    [Parameter(ParameterSetName = 'Export')]
    [string]$CsvPath = '',

    # Mode 2: the edited CSV to apply. Its presence is what selects the mode.
    [Parameter(ParameterSetName = 'Rename', Mandatory)]
    [string]$ImportCsv,

    [string]$TenantId = $env:INTUNE_TENANT_ID,

    [string]$ClientId = $env:INTUNE_CLIENT_ID,

    # Left as [string] rather than [securestring] on purpose: the value normally arrives
    # from $env:INTUNE_CLIENT_SECRET or a customer file, both plaintext, so a SecureString
    # parameter would only move the conversion one line and add a type the caller has to
    # build. Prefer the environment variable, a SecretManagement vault or a certificate.
    [string]$ClientSecret = $env:INTUNE_CLIENT_SECRET,

    # Certificate authentication, preferred over a client secret. Thumbprint looks the
    # certificate up in the current user's store - the login Keychain on macOS, the
    # certificate store on Windows - so the private key never leaves the OS keystore.
    # Use the path form where no store exists, such as a Linux-based Azure Function.
    [string]$CertificateThumbprint = $env:INTUNE_CERT_THUMBPRINT,

    [string]$CertificatePath = $env:INTUNE_CERT_PATH,

    # SecureString rather than string: X509Certificate2 has a SecureString overload, so the
    # plaintext never has to be materialised. The environment variable is still plaintext -
    # it is converted here rather than carried any further.
    [securestring]$CertificatePassword = $(
        if (-not [string]::IsNullOrEmpty($env:INTUNE_CERT_PASSWORD)) {
            ConvertTo-SecureString -String $env:INTUNE_CERT_PASSWORD -AsPlainText -Force
        }
    ),

    # Local JSON file holding per-customer credentials. When supplied, the customer selected
    # from it is the TARGET tenant - the one renamed. Same file and field names as
    # Export-IntuneConfigurationInventory.ps1 and Import-IntuneConfigurationFromJson.ps1.
    [string]$CustomerConfigPath,

    # Picks the target customer without prompting. Without it the run prompts.
    [string]$CustomerName,

    # Overrides the tenant label in the banner. Cosmetic only; the tenant GUID shown beside
    # it always comes from the token, which is the one source that cannot be wrong about
    # which tenant is about to be written to.
    [string]$TenantName = '',

    # Decode the token, report tenant, roles and which of the selected policy types it
    # cannot rename, then exit. Reads no policies and writes nothing.
    [switch]$TestPermissionOnly,

    # Mode 2: skip the one confirmation prompt before the first PATCH. Scheduled runs need
    # this; interactive ones should not use it. It does not skip collision detection.
    [switch]$Force,

    # Where the run report is written. Empty means next to the CSV being read.
    [ValidateScript({ Test-Path -Path $PSItem -PathType Container })]
    [string]$ReportDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Set before the customer region so StrictMode has something to read when no customer file
# is in play; the run report and the target banner both print it.
$script:TargetCustomerName = ''


#region Customer selection

# Resolves credentials from a local multi-customer JSON file. Self-contained on purpose:
# the script stays a single file that can be copied to a machine on its own.
#
# Same file, same field names and the same four precedence rules as the export and import
# scripts, so one customers.json serves all three. The credential parameters default to the
# INTUNE_* environment variables, which are evaluated when the script is invoked, so the
# values have to be assigned here rather than by setting the environment. This must also run
# BEFORE the credential preflight below, which throws on an empty TenantId - with a customer
# file the environment is legitimately empty until this block has populated the variables.
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
    $script:TargetCustomerName = [string]$customer["name"]

    # --- script-specific optional values ---
    # The file is authoritative: a value the customer does not define is cleared rather than
    # left at whatever the environment held, so a value from a previously selected customer
    # cannot follow into this run. TenantName is the only one here, and it is cosmetic - the
    # tenant GUID in the banner comes from the token either way.
    if (-not $PSBoundParameters.ContainsKey("TenantName")) {
        $TenantName = $customer.ContainsKey("tenantName") ? [string]$customer["tenantName"] : ''
    }

    Write-Host "Customer: $($customer["name"])  (tenant $TenantId)" -ForegroundColor Green
}

#endregion Customer selection

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

# Two distinct types so the caller can tell a global auth failure (abort the run) from a
# per-resource permission gap (skip that policy type, keep the rest).
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
    # prompt, and a bad certificate should surface before any Graph work starts. The resolved
    # object is deliberately never disposed: New-ClientAssertion needs its private key to
    # re-sign an assertion on every token renewal, not just the first, for the life of the run.
    Certificate  = $null
}


#region Helpers

function Get-ObjectProperty {
    # StrictMode Latest throws on missing properties of a PSCustomObject, and Graph omits
    # properties instead of returning null - so every property read goes through here.
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
    # ReadWrite is a superset of Read, and Graph emits only one of the two claims. Every
    # requirement here is already a ReadWrite scope, where the widening cannot match
    # (what follows '.Read' in '...ReadWrite.All' is 'W', not '.'), so this collapses to
    # exact matching - which is what a write scope needs.
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
        Copied verbatim from Export-IntuneConfigurationInventory.ps1 v1.12.1 on 2026-09-01.
        The four copies of this function in the repository have deliberately drifted - see
        the SHARED CODE note in Import-IntuneConfigurationFromJson.ps1. Do not paste another
        copy over this one; change this copy and record what changed in the CHANGELOG above.
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
    # Copied verbatim from Export-IntuneConfigurationInventory.ps1 v1.12.1 on 2026-09-01;
    # see the provenance note on Get-ClientCertificate.
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
        With raw REST there is no module to build the assertion, so it is built here.
        Entra ID validates:

          x5t   base64url of the certificate's SHA1 hash, which is how it picks the right
                public key among those registered on the app
          aud   the exact token endpoint being posted to
          iss   and sub, both the client ID
          jti   a unique identifier, to make replay detectable
          exp   short lived - ten minutes is ample for one token request

        RS256 with PKCS#1 padding is the only algorithm Entra ID accepts here.

    .NOTES
        Copied verbatim from Export-IntuneConfigurationInventory.ps1 v1.12.1 on 2026-09-01;
        see the provenance note on Get-ClientCertificate.
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
        # thumbprint and a PFX. This keeps the claim set identical to a reference client
        # rather than relying on our own judgment about STS clock skew tolerance.
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

    # 5-minute safety margin so a long-running rename never dies mid-loop on an expired token.
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
        # Patch added to the export's set. This is the only method that writes.
        [ValidateSet('Get', 'Post', 'Patch')][string]$Method = 'Get',
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
                $requestArgs['Body'] = $Body
                $requestArgs['ContentType'] = 'application/json'
            }
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
                    $script:TokenCache = $null
                    continue
                }
                throw [GraphAuthenticationException]::new(
                    ('Graph rejected the token for {0}. {1}' -f $Uri, $detail))
            }

            if ($statusCode -eq 403) {
                # Scoped to this resource only - the caller skips the type and keeps going.
                throw [GraphAuthorizationException]::new(
                    ('Access denied for {0}. {1}' -f $Uri, $detail))
            }

            # Unlike the import script, which retries a POST only on 429, a PATCH keeps the
            # export's wider retry set (429, 5xx, no-response). Setting a display name to a
            # value it may already have is idempotent - a retry after a 502 that in fact
            # succeeded re-applies the same name. A retried POST would create a second
            # policy; a retried PATCH cannot.
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
        # object and put the raw Graph envelope into the result as a phantom row.
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

function Get-TenantDisplayName {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory)][string]$TenantId)

    # Organization.Read.All is optional, so every failure path falls back to the GUID
    # rather than derailing the run over a cosmetic label.
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
        Write-Verbose ('Could not read organisation name - using tenant ID in the banner. {0}' -f $PSItem.Exception.Message)
    }
    return $TenantId
}

#endregion Helpers

#region Collision detection

function Get-NameCollision {
    <#
    .SYNOPSIS
        Finds names that two policies of the same type would end up sharing.

    .DESCRIPTION
        This is the only judgment the script makes about a name, and it is not an opinion
        about naming: Intune enforces unique names per policy type, so a run that produced a
        duplicate would fail partway through and leave the tenant half-renamed. The grouping
        key is therefore GraphType plus name, not name alone, and the comparison is
        OrdinalIgnoreCase.

        The check is done over the FINAL state of every policy of the affected types, not
        only over the rows in the run: a rename can collide with a policy nobody is
        touching. Modelling it as "what will each object be called when this run finishes"
        also handles the case where the name being taken is one another row in the same run
        is vacating, which a simple duplicate check would report as a false positive.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        # Rows about to be applied. Needs Id, GraphType, CurrentName and NewName.
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Row,
        # GraphType -> every object of that type in the tenant, as Id / CurrentName pairs.
        [Parameter(Mandatory)][hashtable]$ExistingByType
    )

    $collisions = [System.Collections.Generic.List[pscustomobject]]::new()

    $newNameById = @{}
    foreach ($item in $Row) {
        if (-not [string]::IsNullOrWhiteSpace($item.NewName)) { $newNameById[[string]$item.Id] = [string]$item.NewName }
    }
    $rowIds = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@($Row | ForEach-Object { [string]$PSItem.Id }), [StringComparer]::OrdinalIgnoreCase)

    foreach ($graphType in $ExistingByType.Keys) {
        $finalByName = @{}
        foreach ($existing in @($ExistingByType[$graphType])) {
            $id = [string]$existing.Id
            $finalName = $newNameById.ContainsKey($id) ? $newNameById[$id] : [string]$existing.CurrentName
            if ([string]::IsNullOrWhiteSpace($finalName)) { continue }

            $key = $finalName.ToUpperInvariant()
            if (-not $finalByName.ContainsKey($key)) {
                $finalByName[$key] = [System.Collections.Generic.List[pscustomobject]]::new()
            }
            $finalByName[$key].Add([pscustomobject]@{
                Id          = $id
                CurrentName = [string]$existing.CurrentName
                FinalName   = $finalName
                Source      = $rowIds.Contains($id) ? 'run' : 'tenant'
            })
        }

        foreach ($key in $finalByName.Keys) {
            $group = @($finalByName[$key])
            if ($group.Count -lt 2) { continue }
            # A pre-existing duplicate that this run does not touch is the tenant's problem,
            # not this run's - report only groups the run actually contributes to.
            if (-not ($group | Where-Object { $PSItem.Source -eq 'run' })) { continue }

            $collisions.Add([pscustomobject]@{
                GraphType = $graphType
                NewName   = $group[0].FinalName
                Member    = $group
            })
        }
    }

    # Deliberately NOT comma-guarded, unlike Get-IntunePolicy's return. The caller asks this
    # one "how many", and a guarded return arrives at @(...) as a one-element array holding
    # the list - so an empty result would count as 1 and every run would report a collision.
    # Letting the list enumerate is what makes "no collisions" countable as zero.
    return $collisions
}

#endregion Collision detection

#region Endpoints

# RequiredScope is the permission Graph demands to UPDATE the resource, read off each
# endpoint's own Update page - NOT the export's read scope with Read swapped for ReadWrite.
# assignmentFilters is why: it is read with DeviceManagementServiceConfig.Read.All but
# patched with DeviceManagementConfiguration.ReadWrite.All. Deriving it would have produced
# a preflight that passes and a PATCH that 403s. Verified against the Graph beta reference
# on 2026-09-01.
#
# NeedsOdataType marks the endpoints whose resource is an abstract base type: the PATCH body
# has to name the derived type, or Graph rejects it before looking at the payload.
$script:EndpointMap = @(
    @{ Key = 'Configuration';        Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations';               NameField = 'displayName'; NeedsOdataType = $true;  RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'SettingsCatalog';      Uri = 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies';              NameField = 'name';        NeedsOdataType = $false; RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'Compliance';           Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies';           NameField = 'displayName'; NeedsOdataType = $true;  RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'Remediation';          Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts';                NameField = 'displayName'; NeedsOdataType = $false; RequiredScope = 'DeviceManagementScripts.ReadWrite.All' }
    @{ Key = 'PlatformScript';       Uri = 'https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts';            NameField = 'displayName'; NeedsOdataType = $false; RequiredScope = 'DeviceManagementScripts.ReadWrite.All' }
    @{ Key = 'Filter';               Uri = 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters';                  NameField = 'displayName'; NeedsOdataType = $false; RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'WindowsFeatureUpdate'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles';       NameField = 'displayName'; NeedsOdataType = $false; RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'WindowsQualityUpdate'; Uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles';       NameField = 'displayName'; NeedsOdataType = $false; RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'WindowsDriverUpdate';  Uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles';        NameField = 'displayName'; NeedsOdataType = $false; RequiredScope = 'DeviceManagementConfiguration.ReadWrite.All' }
    @{ Key = 'Autopilot';            Uri = 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeploymentProfiles'; NameField = 'displayName'; NeedsOdataType = $true;  RequiredScope = 'DeviceManagementServiceConfig.ReadWrite.All' }
)

function Get-EndpointDefinition {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory)][string]$GraphType)

    foreach ($endpoint in $script:EndpointMap) {
        if ($endpoint.Key -eq $GraphType) { return $endpoint }
    }
    return $null
}

function Get-IntunePolicy {
    <#
        One list call per selected type, paginated through Get-GraphCollection. Reads the id
        and the name and nothing else - the name is the only property this script has any
        business knowing about.
    #>
    [CmdletBinding()]
    # Both, or PSUseOutputTypeCorrectly flags the comma-guarded return: the guard wraps the
    # list in an Object[] on the way out, which is the point of it.
    [OutputType([System.Collections.Generic.List[pscustomobject]], [object[]])]
    param([Parameter(Mandatory)][string[]]$Type)

    $policies = [System.Collections.Generic.List[pscustomobject]]::new()
    $wantAll = $Type -contains 'All'

    foreach ($endpoint in $script:EndpointMap) {
        if (-not $wantAll -and $Type -notcontains $endpoint.Key) { continue }

        Write-Verbose ('Reading {0}' -f $endpoint.Key)
        try {
            $items = Get-GraphCollection -Uri $endpoint.Uri
        }
        catch [GraphAuthorizationException] {
            # Scoped to this endpoint - report it and keep the rest of the run.
            Write-Warning ('{0}: {1}' -f $endpoint.Key, $PSItem.Exception.Message)
            continue
        }

        foreach ($item in $items) {
            $currentName = [string](Get-ObjectProperty -InputObject $item -Name $endpoint.NameField)
            if ([string]::IsNullOrWhiteSpace($currentName)) { continue }

            $policies.Add([pscustomobject]@{
                Id          = [string](Get-ObjectProperty -InputObject $item -Name 'id')
                GraphType   = $endpoint.Key
                CurrentName = $currentName
                # Pre-filled so the CSV can be edited in place. A row still equal to
                # CurrentName when the file comes back is a row nobody chose to change, and
                # mode 2 skips it.
                NewName     = $currentName
            })
        }
    }

    # Comma guard: PowerShell enumerates a collection on the way out of a function, so a bare
    # return turns an empty list into $null and a one-item list into a bare object. This was a
    # live bug in Import-IntuneConfigurationFromJson.ps1 with exactly this cause.
    return , $policies
}

function Get-ExistingPolicyName {
    <#
        Id and name for every object of one type, for the collision check. One call per
        type rather than one per row: a tenant holds at most a few hundred policies per
        type, and knowing which id owns which name is what separates a real collision from
        a name another row in the same run is vacating.

        Also carries @odata.type for the three abstract-base endpoints. This call already
        reads every object of the affected type, so recording the derived type here means
        Set-PolicyName does not need a second GET per renamed policy on those endpoints - it
        falls back to one only when this value is missing. For those three, $select is
        skipped entirely rather than listing @odata.type alongside id/name: whether an
        annotation survives a $select is not something to rely on, and the collections in
        question are small.
    #>
    [CmdletBinding()]
    # Both, same reason as Get-IntunePolicy.
    [OutputType([System.Collections.Generic.List[pscustomobject]], [object[]])]
    param([Parameter(Mandatory)][string]$GraphType)

    $endpoint = Get-EndpointDefinition -GraphType $GraphType
    if ($null -eq $endpoint) { throw "Unknown policy type '$GraphType'." }

    $uri = $endpoint.NeedsOdataType ?
        $endpoint.Uri :
        ('{0}?$select=id,{1}' -f $endpoint.Uri, $endpoint.NameField)

    $existing = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($item in (Get-GraphCollection -Uri $uri)) {
        $existing.Add([pscustomobject]@{
            Id          = [string](Get-ObjectProperty -InputObject $item -Name 'id')
            CurrentName = [string](Get-ObjectProperty -InputObject $item -Name $endpoint.NameField)
            OdataType   = [string](Get-ObjectProperty -InputObject $item -Name '@odata.type')
        })
    }

    # Comma guard, same reason as Get-IntunePolicy's return.
    return , $existing
}

#endregion Endpoints

#region CSV

function Import-RenameCsv {
    <#
        Validates the edited CSV up front rather than discovering its problems one 404 at a
        time in the middle of the rename loop. The checks are about the file being usable,
        not about the names being good: the columns are present, the file was not exported
        by 1.0.0, each Id is a GUID and appears once, and each GraphType is one this script
        knows. What NewName says is the operator's business.
    #>
    [CmdletBinding()]
    # Both, same reason as Get-IntunePolicy.
    [OutputType([System.Collections.Generic.List[pscustomobject]], [object[]])]
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$GuidPattern)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "CSV file not found: $Path"
    }

    $csv = @(Import-Csv -Path $Path -Encoding utf8)
    if ($csv.Count -eq 0) {
        throw "'$Path' contains no rows."
    }

    # Count first: $csv[0] on an empty file throws under StrictMode before this message
    # would ever be reached.
    $columns = @($csv[0].PSObject.Properties.Name)
    $missing = @(@('Id', 'CurrentName', 'NewName', 'GraphType') | Where-Object { $PSItem -notin $columns })
    if ($missing.Count -gt 0) {
        throw ("'$Path' is missing required column(s): {0}. Present: {1}" -f ($missing -join ', '), ($columns -join ', '))
    }

    # A Confidence column identifies a file exported by 1.0.0 unambiguously - this version
    # never writes one. 1.0.0's NewName held a machine-derived guess nobody may have reviewed
    # as carefully as a name they typed themselves; running it through unchanged would apply
    # exactly the Assumed/Unresolved rows 1.0.0 either flagged or refused.
    if ('Confidence' -in $columns) {
        throw ("'$Path' has a Confidence column, which means it was exported by version 1.0.0. " +
               "Its NewName values are derived names this version does not stand behind. " +
               "Export a fresh CSV with mode 1 and edit that instead.")
    }

    $validTypes = @($script:EndpointMap | ForEach-Object { $PSItem.Key })
    $rows = [System.Collections.Generic.List[pscustomobject]]::new()
    $seenId = @{}
    $trimmed = 0
    $lineNumber = 1

    foreach ($row in $csv) {
        $lineNumber++
        $currentName = [string]$row.CurrentName
        $id          = [string]$row.Id
        $graphType   = [string]$row.GraphType

        # Excel adds trailing spaces on an edited cell more often than anyone would like, and
        # a policy whose name ends in a space is invisible in the portal and permanent in the
        # tenant. Trimmed rather than rejected, but counted so it is never silent.
        $newNameRaw = [string]$row.NewName
        $newName    = $newNameRaw.Trim()
        if ($newName -cne $newNameRaw) { $trimmed++ }

        if ([string]::IsNullOrWhiteSpace($newName) -or $newName -ceq $currentName) {
            Write-Verbose ('Row {0} ({1}): no change requested, skipping.' -f $lineNumber, $currentName)
            continue
        }

        if ($id -notmatch $GuidPattern) {
            throw ("Row {0} ('{1}'): Id '{2}' is not a GUID." -f $lineNumber, $currentName, $id)
        }

        # Two rows renaming the same policy is an edit mistake with no correct resolution -
        # whichever ran last would win, and which that is depends on row order.
        if ($seenId.ContainsKey($id)) {
            throw ("Row {0}: Id {1} also appears on row {2}. A policy can only be renamed once per run." -f
                $lineNumber, $id, $seenId[$id])
        }
        $seenId[$id] = $lineNumber

        if ($graphType -notin $validTypes) {
            throw ("Row {0} ('{1}'): GraphType '{2}' is not one of: {3}" -f
                $lineNumber, $currentName, $graphType, ($validTypes -join ', '))
        }

        $endpoint = Get-EndpointDefinition -GraphType $graphType
        $rows.Add([pscustomobject]@{
            Id          = $id
            GraphType   = $graphType
            CurrentName = $currentName
            NewName     = $newName
            Uri         = $endpoint.Uri
            NameField   = $endpoint.NameField
            # The list response is not seen in this mode, so the derived type is fetched by
            # Set-PolicyName for the endpoints that need it. See the note there.
            OdataType   = ''
        })
    }

    if ($trimmed -gt 0) {
        Write-Warning ('{0} NewName value(s) had leading or trailing whitespace, which was removed.' -f $trimmed)
    }

    # An empty result is not an error - a valid file where nothing was edited is a
    # legitimate outcome, and a scheduled run should not page anyone over it. The caller
    # decides what to say about it.

    # Comma guard, same reason as Get-IntunePolicy's return.
    return , $rows
}

#endregion CSV

#region Rename

function Set-PolicyName {
    <#
        The only function in the script that writes. Errors are deliberately not caught
        here: GraphAuthenticationException has to reach the run loop so a global auth
        failure aborts instead of being logged once per policy.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Policy,
        [Parameter(Mandatory)][string]$NewName
    )

    $patchUri = '{0}/{1}' -f $Policy.Uri, $Policy.Id
    $endpoint = Get-EndpointDefinition -GraphType $Policy.GraphType
    $body = @{ $Policy.NameField = $NewName }

    if ($endpoint.NeedsOdataType) {
        # deviceConfigurations, deviceCompliancePolicies and Autopilot profiles are abstract
        # base types: the body has to name the derived type or Graph rejects the request.
        # The caller normally sets $Policy.OdataType from the collision-check read
        # (Get-ExistingPolicyName), which already covers every policy of these types. This
        # GET is therefore only the fallback for what that read cannot guarantee: an Id in
        # the CSV that was not in the read set, or a Graph object with no annotation at all.
        $odataType = [string]$Policy.OdataType
        if ([string]::IsNullOrWhiteSpace($odataType)) {
            Write-Verbose ('{0}: reading @odata.type for the PATCH body.' -f $Policy.Id)
            $existing = Invoke-GraphRequest -Uri $patchUri
            $odataType = [string](Get-ObjectProperty -InputObject $existing -Name '@odata.type')
        }
        if ([string]::IsNullOrWhiteSpace($odataType)) {
            throw ("Could not determine @odata.type for {0} '{1}', which {2} requires in a PATCH body." -f
                $Policy.Id, $Policy.CurrentName, $Policy.GraphType)
        }
        $body['@odata.type'] = $odataType
    }

    Invoke-GraphRequest -Method Patch -Uri $patchUri -Body ($body | ConvertTo-Json -Compress) | Out-Null
}

#endregion Rename

#region Main

# Resolve the certificate before anything else touches Graph, so a missing key or a wrong
# thumbprint fails here rather than mid-run.
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

$isRenameMode = $PSCmdlet.ParameterSetName -eq 'Rename'

# One instant, three representations: UTC for the record, local for the file name, offset so
# the two can be reconciled. Same convention as the export's manifest.
$runLocal = Get-Date
$runUtc = $runLocal.ToUniversalTime()
$fileStamp = $runLocal.ToString('yyyy-MM-dd_HHmm')

# Mode 2 reads and validates its CSV before any Graph call: the validation is local and
# free, and a malformed CSV should fail before a token is even requested.
$csvRows = $null
$importCsvResolved = ''
if ($isRenameMode) {
    if (-not (Test-Path -Path $ImportCsv -PathType Leaf)) {
        throw "CSV file not found: $ImportCsv"
    }
    $importCsvResolved = (Resolve-Path -Path $ImportCsv).Path
    $csvRows = Import-RenameCsv -Path $importCsvResolved -GuidPattern $guidPattern
    if ($csvRows.Count -eq 0) {
        Write-Warning ("No row in '{0}' has a NewName that differs from its CurrentName. Nothing to do." -f $importCsvResolved)
        return
    }
    $selectedTypes = @($csvRows | ForEach-Object { [string]$PSItem.GraphType } | Sort-Object -Unique)
}
else {
    $selectedTypes = ($PolicyType -contains 'All') ?
        @($script:EndpointMap | ForEach-Object { [string]$PSItem.Key }) :
        @($PolicyType | Sort-Object -Unique)
}

# Preflight: report which of the selected types the token cannot rename. Advisory, never
# blocking - a 403 on the endpoint is what really stops it, and the loop handles that.
$claims = ConvertFrom-JwtPayload -Token (Get-GraphAccessToken)
# Filtered rather than a bare @(Get-ObjectProperty ...): an absent 'roles' claim comes back
# as $null, and @($null) is a one-element array, so an unfiltered count never reaches zero
# and the warning below would never fire.
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

$scopeByType = @{}
foreach ($endpoint in $script:EndpointMap) { $scopeByType[$endpoint.Key] = $endpoint.RequiredScope }

$blockedTypes = @($selectedTypes | Where-Object {
    -not (Test-RoleSatisfied -GrantedRole $grantedRoles -RequiredRole $scopeByType[$PSItem])
})

if ($TestPermissionOnly) {
    # Member enumeration over an empty collection throws under StrictMode Latest.
    Write-Output ([pscustomobject]@{
        TenantId      = $tokenTenantId
        TenantName    = ([string]::IsNullOrWhiteSpace($TenantName) ? $script:TargetCustomerName : $TenantName)
        GrantedRoles  = (@($grantedRoles | ForEach-Object { [string]$PSItem }) -join ', ')
        TypesSelected = (@($selectedTypes | ForEach-Object { [string]$PSItem }) -join ', ')
        BlockedTypes  = (@($blockedTypes | ForEach-Object { '{0} (needs {1})' -f $PSItem, $scopeByType[$PSItem] }) -join ', ')
        AllTypesReady = ($blockedTypes.Count -eq 0)
    })
    return
}

foreach ($blocked in $blockedTypes) {
    Write-Warning ('{0} will likely fail - token lacks {1}.' -f $blocked, $scopeByType[$blocked])
}

# The tenant label is cosmetic; the GUID beside it comes from the token's own 'tid' claim,
# which is the only source that cannot be wrong about which tenant is about to be written to.
$tenantLabel = $TenantName
if ([string]::IsNullOrWhiteSpace($tenantLabel)) { $tenantLabel = $script:TargetCustomerName }
if ([string]::IsNullOrWhiteSpace($tenantLabel)) { $tenantLabel = Get-TenantDisplayName -TenantId $tokenTenantId }

if (-not $isRenameMode) {

    # --- MODE 1: export ------------------------------------------------------------------
    # Nothing here writes to the tenant. The CSV is the deliverable and, once mode 2 has run,
    # the only record of what the old names were.

    $policies = Get-IntunePolicy -Type $PolicyType
    if ($policies.Count -eq 0) {
        Write-Warning 'No policies were read. Run with -TestPermissionOnly to inspect the token.'
        return
    }

    $results = @($policies | Where-Object {
        -not $Prefix -or $PSItem.CurrentName -like "$Prefix*"
    })

    if ($results.Count -eq 0) {
        Write-Warning ("No policy matched the prefix '{0}'." -f $Prefix)
        return
    }

    if ([string]::IsNullOrWhiteSpace($CsvPath)) {
        $csvRoot = -not [string]::IsNullOrWhiteSpace($PSScriptRoot) ? $PSScriptRoot : (Get-Location).Path
        $CsvPath = Join-Path -Path $csvRoot -ChildPath ('IntuneRename_{0}_{1}.csv' -f
            ($tenantLabel -replace '[\\/:*?"<>|]', '' -replace '\s+', '_'), $fileStamp)
    }
    $CsvPath = [System.IO.Path]::GetFullPath($CsvPath)

    # utf8BOM, not UTF8: in PowerShell 7 'UTF8' means UTF-8 WITHOUT a BOM, and Excel then
    # reads the file as Windows-1252. A Swedish character in a policy name would come back
    # from the edited CSV mangled and be written to the tenant that way.
    $results |
        Sort-Object -Property GraphType, CurrentName |
        Select-Object -Property Id, GraphType, CurrentName, NewName |
        Export-Csv -Path $CsvPath -NoTypeInformation -Encoding utf8BOM -WhatIf:$false

    $byType = $results | Group-Object -Property GraphType |
        Sort-Object -Property Name |
        ForEach-Object { '{0}={1}' -f $PSItem.Name, $PSItem.Count }

    Write-Host ''
    Write-Host ('Tenant : {0}  ({1})' -f $tenantLabel, $tokenTenantId) -ForegroundColor Cyan
    Write-Host ('Rows   : {0}  ({1})' -f $results.Count, ($byType -join ', '))
    Write-Host ('CSV    : {0}' -f $CsvPath) -ForegroundColor Green
    Write-Host ''
    Write-Host 'Edit the NewName column, then apply it with:' -ForegroundColor Yellow
    Write-Host ("    ./Rename-IntunePolicies.ps1 -ImportCsv '{0}' -WhatIf" -f $CsvPath)
    Write-Host ''
    Write-Host 'A name that looks like a date or a number (2025-03-13, 1.5) can be silently' -ForegroundColor DarkGray
    Write-Host 'rewritten by Excel on open/save. See the README before editing in Excel.' -ForegroundColor DarkGray
    Write-Host ''

    Write-Output $results
    return
}

# --- MODE 2: rename -----------------------------------------------------------------------

$results = [System.Collections.Generic.List[pscustomobject]]::new()

function Add-Result {
    # Detail carries the reason a row ended up with the status it has; for a failure that is
    # Graph's own code and message, never just "400 (Bad Request)".
    param(
        [string]$Id, [string]$GraphType, [string]$CurrentName, [string]$NewName,
        [string]$Status, [string]$Detail
    )
    $results.Add([pscustomobject][ordered]@{
        Id = $Id; GraphType = $GraphType; CurrentName = $CurrentName; NewName = $NewName
        Status = $Status; Detail = $Detail
    })
}

function Write-CollisionReport {
    # Reports the whole group, not just the offending row: knowing that two names collide is
    # useless without knowing which two policies they are.
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Collision)

    foreach ($group in $Collision) {
        Write-Warning ('Name collision in {0}: {1} object(s) would be called "{2}".' -f
            $group.GraphType, @($group.Member).Count, $group.NewName)
        foreach ($member in @($group.Member)) {
            Write-Warning ('    [{0}] {1}  (currently "{2}")' -f $member.Source, $member.Id, $member.CurrentName)
        }
    }
}

$reportRoot = [string]::IsNullOrWhiteSpace($ReportDirectory) ?
    (Split-Path -Path $importCsvResolved -Parent) : (Resolve-Path -Path $ReportDirectory).Path
$runComplete = $false
$abortReason = ''

# The report is the only record of what was renamed, and there is no rollback - so it is
# written in 'finally', not after the loop. The case that needs it most is the one that never
# reaches the end: a global 401 halfway through leaves a tenant whose policies are named
# neither what they were nor what the CSV says.
try {
    # Every object of every affected type, so a rename that collides with a policy nobody is
    # touching is caught too. This runs before the banner: an operator should not be asked to
    # confirm a run that cannot legally complete.
    $existingByType = @{}
    # Types whose existing names could NOT be read. An empty list here is not "no
    # collisions" - it is "we do not know", and uniqueness is the one guarantee -Force may
    # not bypass. Rows of these types are pulled out below, before the collision check ever
    # runs, and recorded as blocked rather than being treated as collision-free by default.
    $unverifiableTypes = [System.Collections.Generic.List[string]]::new()
    foreach ($graphType in $selectedTypes) {
        try {
            # Assigned straight from the call: wrapping a comma-guarded return in @() yields a
            # one-element array holding the list, not the rows.
            $existingByType[$graphType] = Get-ExistingPolicyName -GraphType $graphType
        }
        catch [GraphAuthorizationException] {
            Write-Warning ('{0}: {1}' -f $graphType, $PSItem.Exception.Message)
            $existingByType[$graphType] = @()
            $unverifiableTypes.Add($graphType)
        }
    }

    $verifiableRows = @($csvRows | Where-Object { $PSItem.GraphType -notin $unverifiableTypes })
    $unverifiableRows = @($csvRows | Where-Object { $PSItem.GraphType -in $unverifiableTypes })
    foreach ($row in $unverifiableRows) {
        Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
            -Status 'blocked' -Detail 'existing names could not be read, so uniqueness could not be verified'
    }

    $collisions = @(Get-NameCollision -Row $verifiableRows -ExistingByType $existingByType)
    if ($collisions.Count -gt 0) {
        Write-CollisionReport -Collision $collisions
        foreach ($group in $collisions) {
            foreach ($member in @($group.Member)) {
                Add-Result -Id $member.Id -GraphType $group.GraphType -CurrentName $member.CurrentName `
                    -NewName $group.NewName -Status 'collision' `
                    -Detail ('{0} object(s) of type {1} would share this name' -f @($group.Member).Count, $group.GraphType)
            }
        }
        # -Force does not get past this. Two identically named policies are precisely the
        # outcome the check exists to prevent, and unlike a bad name they cannot be corrected
        # by running the tool again - the collision is already in the tenant.
        throw ('{0} name collision(s) detected. Nothing was renamed.' -f $collisions.Count)
    }

    # Current name (and, where it was read, the derived type - see the OdataType note in
    # Get-ExistingPolicyName) per id, so a row whose target name is already in place is
    # recognised rather than patched again, and so Set-PolicyName does not need a second GET
    # for it. Built only from types that were actually read; an unverifiable type has no
    # entries here on purpose, so its rows cannot be mistaken for "already named as requested".
    $currentNameById = @{}
    $odataTypeById = @{}
    foreach ($graphType in $existingByType.Keys) {
        if ($graphType -in $unverifiableTypes) { continue }
        foreach ($existing in @($existingByType[$graphType])) {
            $currentNameById[[string]$existing.Id] = [string]$existing.CurrentName
            if (-not [string]::IsNullOrWhiteSpace([string]$existing.OdataType)) {
                $odataTypeById[[string]$existing.Id] = [string]$existing.OdataType
            }
        }
    }

    # Ids rather than object identity: an id set is what the loop below can ask about cheaply,
    # and -in over a list of PSCustomObjects compares by reference, which is a property of the
    # collection rather than of the data.
    $renameIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $verifiableRows) {
        if ($odataTypeById.ContainsKey($row.Id)) { $row.OdataType = $odataTypeById[$row.Id] }
        $alreadyNamed = $currentNameById.ContainsKey($row.Id) -and $currentNameById[$row.Id] -ceq $row.NewName
        if (-not $alreadyNamed) { [void]$renameIds.Add([string]$row.Id) }
    }

    Write-Host ''
    Write-Host ('Source : {0}' -f $importCsvResolved) -ForegroundColor Cyan
    Write-Host ('Tenant : {0}  ({1})' -f $tenantLabel, $tokenTenantId) -ForegroundColor Yellow -NoNewline
    Write-Host ($WhatIfPreference ? '   DRY RUN' : '   WRITE') -ForegroundColor ($WhatIfPreference ? 'Green' : 'Red')
    Write-Host ('Rows   : {0} to rename, {1} already named as requested, {2} blocked' -f
        $renameIds.Count, ($verifiableRows.Count - $renameIds.Count), $unverifiableRows.Count)
    Write-Host ''

    # One gate for the whole run, not ConfirmImpact = 'High' - that asks once per policy, and
    # an operator clicking through eighteen prompts has stopped reading by the third. Asked
    # only when something will actually be written and there is someone at the keyboard to
    # answer: a redirected stdin means a scheduled run, where Read-Host would block forever.
    $sessionIsInteractive = [Environment]::UserInteractive -and -not [System.Console]::IsInputRedirected
    if (-not $WhatIfPreference -and -not $Force -and $renameIds.Count -gt 0) {
        if ($sessionIsInteractive) {
            $answer = Read-Host 'Rename the above in the TARGET tenant? Type YES to continue'
            if ($answer -cne 'YES') { throw 'Aborted at the confirmation prompt. Nothing was renamed.' }
        }
        else {
            Write-Warning 'Non-interactive session - the confirmation prompt was skipped. Use -Force to make that explicit.'
        }
    }

    foreach ($row in $verifiableRows) {
        if (-not $renameIds.Contains([string]$row.Id)) {
            Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
                -Status 'unchanged' -Detail 'the policy is already named as the CSV requests'
            continue
        }

        # Once a type has answered 403 there is no point asking it again for every remaining
        # row of that type - one clear line each, and no further calls.
        if ($blockedTypes -contains $row.GraphType) {
            Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
                -Status 'blocked' -Detail ('token lacks {0}' -f $scopeByType[$row.GraphType])
            continue
        }

        $target = '{0}: {1}' -f $row.GraphType, $row.CurrentName
        if (-not $PSCmdlet.ShouldProcess($target, ("Rename to '{0}'" -f $row.NewName))) {
            # -WhatIf and a declined -Confirm land here. WhatIfPreference tells them apart.
            Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
                -Status ($WhatIfPreference ? 'whatif' : 'skipped') `
                -Detail ($WhatIfPreference ? 'dry run' : 'declined at the confirmation prompt')
            continue
        }

        try {
            Set-PolicyName -Policy $row -NewName $row.NewName
            Write-Verbose ('{0}  ->  {1}' -f $row.CurrentName, $row.NewName)
            Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
                -Status 'renamed' -Detail ''
        }
        catch [GraphAuthenticationException] {
            # Global, not per-policy: the token is rejected outright. Let it out so the run
            # aborts instead of logging the same rejection once for every remaining row.
            throw
        }
        catch [GraphAuthorizationException] {
            # This type is not writable with this token. Mark it so the remaining rows of the
            # same type are recorded without another call.
            $blockedTypes += $row.GraphType
            Write-Warning ('{0}: {1}' -f $row.CurrentName, $PSItem.Exception.Message)
            Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
                -Status 'blocked' -Detail $PSItem.Exception.Message
        }
        catch [System.Exception] {
            $detail = Get-GraphErrorDetail -ErrorRecord $PSItem
            Write-Warning ('{0}: {1}' -f $row.CurrentName, $detail)
            Add-Result -Id $row.Id -GraphType $row.GraphType -CurrentName $row.CurrentName -NewName $row.NewName `
                -Status 'failed' -Detail $detail
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
    # not be missing. "No rows" and "did not happen" are different states, and both have to be
    # legible without interpreting the warning stream.
    $totals = [ordered]@{}
    foreach ($statusKey in @('renamed', 'unchanged', 'collision', 'whatif', 'skipped', 'blocked', 'failed')) {
        $totals[$statusKey] = 0
    }
    foreach ($row in $results) {
        if ($totals.Contains($row.Status)) { $totals[$row.Status]++ }
    }

    $report = [ordered]@{
        schemaVersion      = 2
        runTimestampUtc    = $runUtc.ToString('o')
        runTimestampLocal  = $runLocal.ToString('yyyy-MM-ddTHH:mm:ss')
        utcOffset          = [System.TimeZoneInfo]::Local.GetUtcOffset($runLocal).ToString()
        timeZone           = [System.TimeZoneInfo]::Local.Id
        scriptVersion      = '2.0.0'
        whatIf             = [bool]$WhatIfPreference
        targetTenantId     = $tokenTenantId
        targetTenantName   = $tenantLabel
        targetCustomerName = $script:TargetCustomerName
        sourceCsv          = $importCsvResolved
        typesSelected      = (@($selectedTypes | ForEach-Object { [string]$PSItem }) -join ', ')
        runComplete        = $runComplete
        abortReason        = $abortReason
        totals             = $totals
        results            = @($results | ForEach-Object {
            [ordered]@{
                id          = $PSItem.Id
                graphType   = $PSItem.GraphType
                currentName = $PSItem.CurrentName
                newName     = $PSItem.NewName
                status      = $PSItem.Status
                detail      = $PSItem.Detail
            }
        })
    }

    $reportBase = Join-Path -Path $reportRoot -ChildPath ('_renamereport_{0}' -f $fileStamp)
    try {
        # Both files are written on a -WhatIf run too. A dry run that leaves something you can
        # read afterwards is the point of the dry run; whatIf: true is what tells them apart.
        Write-Utf8File -Path ('{0}.json' -f $reportBase) -Content (ConvertTo-Json -InputObject $report -Depth 6)
        # utf8BOM for the same reason as the exported CSV: this is the file an operator opens
        # in Excel to build the reverse run that undoes a rename.
        $results | Export-Csv -Path ('{0}.csv' -f $reportBase) -NoTypeInformation -Encoding utf8BOM -WhatIf:$false
        Write-Verbose ('Report: {0}.json / .csv' -f $reportBase)
    }
    catch [System.Exception] {
        # Never let a failed report write replace the exception that caused the abort.
        Write-Warning ('Could not write the run report to "{0}": {1}' -f $reportBase, $PSItem.Exception.Message)
    }
}

$summary = $results | Group-Object -Property Status |
    Sort-Object -Property Name |
    ForEach-Object { '{0}={1}' -f $PSItem.Name, $PSItem.Count }

Write-Verbose ('Done. {0}' -f ($summary -join ', '))
Write-Output $results

#endregion Main
