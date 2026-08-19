#Requires -Version 7.4
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
    # first run. Requires Compare-IntuneConfigurationInventory.ps1 alongside this script.
    .\Export-IntuneConfigurationInventory.ps1 -CompareWithPrevious -Verbose

.EXAMPLE
    # Permission check only - decodes the token, reports tenant, roles and affected areas.
    .\Export-IntuneConfigurationInventory.ps1 -TestPermissionOnly -Verbose
#>

[CmdletBinding()]
param(
    [string]$TenantId = $env:INTUNE_TENANT_ID,

    [string]$ClientId = $env:INTUNE_CLIENT_ID,

    [string]$ClientSecret = $env:INTUNE_CLIENT_SECRET,

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

    # Run Compare-IntuneConfigurationInventory.ps1 against this tenant once the export
    # finishes, producing a change set against the previous run in the same command.
    [switch]$CompareWithPrevious,

    # Path to the comparison script. Defaults to the export script's own folder.
    [string]$ComparePath,

    # Settings Catalog / Endpoint Security settings need one extra call per policy. Skip for a fast run.
    [switch]$SkipDetailedSettings,

    [switch]$IncludeConditionalAccess,

    # Decode the token, report tenant, roles and affected areas, exit.
    [switch]$TestPermissionOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Credential preflight

# Validation attributes only run on BOUND parameters, never on default values. With
# [ValidateNotNullOrEmpty()] on these three, an unset INTUNE_* variable passes silently
# and surfaces much later as a request against "login.microsoftonline.com//oauth2/...".
# Checking here turns that into one clear message.
foreach ($credential in @(
        @{ Name = 'TenantId'; Value = $TenantId; Variable = 'INTUNE_TENANT_ID' }
        @{ Name = 'ClientId'; Value = $ClientId; Variable = 'INTUNE_CLIENT_ID' }
        @{ Name = 'ClientSecret'; Value = $ClientSecret; Variable = 'INTUNE_CLIENT_SECRET' })) {
    if ([string]::IsNullOrWhiteSpace($credential.Value)) {
        throw ('Missing {0}. Pass -{0} or set $env:{1}.' -f $credential.Name, $credential.Variable)
    }
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
$script:AuthContext = [pscustomobject]@{ TenantId = $TenantId; ClientId = $ClientId; ClientSecret = $ClientSecret }
$script:GroupNameCache = @{}
$script:FilterNameCache = @{}

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

function Get-GraphAccessToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # 5-minute safety margin so a long-running export never dies mid-page on an expired token.
    if ($null -ne $script:TokenCache -and $script:TokenCache.ExpiresOn -gt (Get-Date).AddMinutes(5)) {
        return $script:TokenCache.AccessToken
    }

    $body = @{
        client_id     = $script:AuthContext.ClientId
        client_secret = $script:AuthContext.ClientSecret
        scope         = 'https://graph.microsoft.com/.default'
        grant_type    = 'client_credentials'
    }

    try {
        $tokenUri = 'https://login.microsoftonline.com/{0}/oauth2/v2.0/token' -f $script:AuthContext.TenantId
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
    $count = 0

    foreach ($item in @($Assignment)) {
        if ($null -eq $item) { continue }
        $count++
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

#endregion Helpers

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
)

if ($IncludeConditionalAccess) {
    $policyDefinitions += New-PolicyDefinition -Area 'Conditional Access Policy' `
        -Resource 'identity/conditionalAccess/policies' -RequiredRole 'Policy.Read.All' `
        -ApiVersion 'v1.0' -ExpandAssignments $false
}

#endregion Policy definitions

#region Main

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
New-Item -Path $runDirectory -ItemType Directory -Force | Out-Null

$csvName = 'IntuneConfigurationInventory_{0}_{1}.csv' -f $tenantNamePart, $fileStamp
$csvPath = Join-Path -Path $runDirectory -ChildPath $csvName

$inventory = [System.Collections.Generic.List[pscustomobject]]::new()
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
        $configuration = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -in @('assignments', '@odata.context', 'assignments@odata.context')) { continue }
            $configuration[$property.Name] = $property.Value
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
            Version              = [string](Get-ObjectProperty -InputObject $item -Name 'version')
            CreatedDateTime      = ConvertTo-StableDateString -Value (Get-ObjectProperty -InputObject $item -Name 'createdDateTime')
            LastModifiedDateTime = ConvertTo-StableDateString -Value (Get-ObjectProperty -InputObject $item -Name 'lastModifiedDateTime')
            AssignedGroups       = $assignmentDetail.Included
            ExcludedGroups       = $assignmentDetail.Excluded
            AssignmentFilters    = $assignmentDetail.Filters
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

# Optional downstream step. The comparison stays a separate script rather than being
# merged in: it is pure local file processing that you will want to re-run - after a
# taxonomy change, or against an older pair of runs - without paying for another full
# Graph export. A failure here must never fail the export, because the exported data on
# disk is complete and valid regardless.
$changeSetPath = $null
if ($CompareWithPrevious) {
    $resolvedComparePath = $ComparePath
    if ([string]::IsNullOrWhiteSpace($resolvedComparePath)) {
        $scriptFolder = -not [string]::IsNullOrWhiteSpace($PSScriptRoot) ? $PSScriptRoot : (Get-Location).Path
        $resolvedComparePath = Join-Path -Path $scriptFolder -ChildPath 'Compare-IntuneConfigurationInventory.ps1'
    }

    if (-not (Test-Path -Path $resolvedComparePath -PathType Leaf)) {
        Write-Warning ('Comparison skipped - "{0}" was not found. The export itself completed successfully.' -f $resolvedComparePath)
    }
    else {
        try {
            $comparison = @(& $resolvedComparePath -TenantDirectory $tenantRoot)
            if ($comparison.Count -gt 0) {
                $changeSetPath = $comparison[-1].ChangeSetPath
                Write-Verbose ('Change set: {0}' -f $changeSetPath)
            }
        }
        catch [System.Exception] {
            Write-Warning ('Comparison failed, export unaffected: {0}' -f $PSItem.Exception.Message)
        }
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
    TenantRoot     = $tenantRoot
    RunDirectory   = $runDirectory
    CsvPath        = $csvPath
    ManifestPath   = $manifestPath
    ZipPath        = $zipPath
    ChangeSetPath  = $changeSetPath
    PolicyCount    = $inventory.Count
    ExportComplete = $manifest.exportComplete
})

#endregion Main