<#
.SYNOPSIS
    Compares two Export-IntuneConfigurationInventory runs and emits a change set grouped
    into one documentation page per category and platform.

.DESCRIPTION
    The diff itself must be deterministic - an AI model reading two exports and being asked
    "what changed" will miss records and invent others. This script decides what changed;
    the agent only describes it and opens the JSON files that actually differ.

    Matching is on RecordKey (PolicyArea|Id). Change detection uses three independent
    signals, because they cover different things:

      ConfigurationHash    - the policy body. Assignments are NOT part of it.
      Assignment columns   - AssignedGroups / ExcludedGroups / AssignmentFilters.
                             A policy that only gets re-targeted has an unchanged hash,
                             so comparing the hash alone silently misses re-targeting.
      Metadata columns     - DisplayName, Description, Version, TemplateName, Platform.

    For changed policies a field-level JSON diff is produced, so the agent receives
    "setting X went from A to B" rather than two 280 KB files.

    PLATFORM RESOLUTION. The exporter's Platform column is empty for several areas because
    Graph does not expose one (remediations, platform scripts, Autopilot, update rings,
    assignment filters). Platform is therefore resolved in four steps, first hit wins:

      1. The Platform column, normalised (windows10 -> Windows, ios -> iOS/iPadOS, ...).
      2. PolicyType, which carries the Graph odata type for most areas
         (windows10CompliancePolicy, macOSGeneralDeviceConfiguration, ...).
      3. The area's implicit platform - a macOS shell script is macOS by definition.
      4. A peek into the sidecar JSON for areas that carry a singular 'platform' or
         'platformType' property. Only done for areas whose files are small.

    Anything still unresolved lands under Cross-platform rather than being dropped.

    Windows 365 / Cloud PC is deliberately NOT a separate platform: Graph classifies Cloud
    PC policies as Windows, and separating them would depend on a naming convention that
    silently misfiles anything not following it.

    A policy that targets several platforms is listed under each of them, flagged with
    sharedAcrossPlatforms so the agent can note that editing it affects more than one page.

    SAFETY: an area that was skipped in either run cannot support a deletion claim - the
    objects may well still exist, we just could not read them. Such areas are reported
    under unreliableAreas and their removals are marked uncertain rather than removed.

.PARAMETER TenantDirectory
    The per-tenant folder containing dated run folders, e.g. .../Data/Wistrand-Advokatbyra

.PARAMETER BaselineRun
    Run folder name to compare from. Defaults to the second most recent.

.PARAMETER CurrentRun
    Run folder name to compare to. Defaults to the most recent.

.PARAMETER OutputPath
    Where to write the change set JSON. Defaults to a _changeset file in the current run folder.

.PARAMETER NoPlatformSplit
    Produce one page per category instead of one per category and platform. Useful for
    small tenants where per-platform pages would be mostly empty.

.PARAMETER MaxValueLength
    Values longer than this are truncated in the field diff. Script bodies and base64
    payloads would otherwise dominate the output; the agent can open the file if needed.

.EXAMPLE
    .\Compare-IntuneConfigurationInventory.ps1 -TenantDirectory '.\Data\Wistrand-Advokatbyra'

.EXAMPLE
    # Every tenant under a root - pass the root itself, tenant folders are detected
    .\Compare-IntuneConfigurationInventory.ps1 -TenantDirectory '.\Data'

.EXAMPLE
    # A specific pair of runs rather than the latest two
    .\Compare-IntuneConfigurationInventory.ps1 -TenantDirectory '.\Data\Wistrand-Advokatbyra' `
        -BaselineRun '2026-07-31 11-25' -CurrentRun '2026-08-05 12-16'

.NOTES
    Version:        1.2.0
    Creation Date:  2026-08-03
    Last Updated:   2026-08-05
    Author:         Peter Olausson
    Contact:        fitur@duck.com

    Reads only from disk - no Graph calls, no credentials. Kept separate from the export
    script deliberately: the comparison is worth re-running after a taxonomy change, or
    against an older pair of runs, without paying for another full Graph export.

    CHANGELOG

        1.2.0 - 2026-08-05
            Accepts either a tenant folder or the root above it, detecting tenant folders by
            looking for run folders one level down. Endpoint Security intents expose no
            platform property at all, so their platform is now derived from the definitionId
            prefix of their settings. Added the mobile application management platform
            aliases, which had left app-scoped assignment filters under Cross-platform.

        1.1.0 - 2026-08-05
            Pages are now split per platform as well as per category. Platform is resolved in
            four steps - the Platform column, then PolicyType, then the area's implicit
            platform, then a peek into the sidecar file - because Graph exposes no platform at
            all for remediations, platform scripts, Autopilot profiles or update rings.
            Windows 365 is deliberately not a separate platform: Graph classifies Cloud PC
            policies as Windows, and separating them would depend on a naming convention that
            silently misfiles anything not following it.

            Fixed during the same work: functions returning arrays now use the comma operator
            on every return path, since PowerShell unrolls a returned array and .Count on the
            resulting $null throws under StrictMode. The call sites were then wrapping those
            already-protected returns in @() a second time, nesting the array inside a
            one-element array so every -in comparison silently failed and produced zero pages.

        1.0.0 - 2026-08-03
            First version. Matches records on RecordKey and detects change through three
            independent signals: ConfigurationHash for the policy body, the assignment columns
            separately - assignments are not part of the hash, so comparing it alone misses
            re-targeting entirely - and the metadata columns. Produces a field-level JSON diff
            for changed policies, matching array elements by identity where one exists so a
            reordered array does not read as "everything changed". Areas skipped in either run
            are reported as uncertain rather than removed, since absence is not evidence of
            deletion when the area could not be read.
#>

#Requires -Version 7.4

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $PSItem -PathType Container })]
    [string]$TenantDirectory,

    [string]$BaselineRun,
    [string]$CurrentRun,
    [string]$OutputPath,

    [switch]$NoPlatformSplit,

    [ValidateRange(50, 10000)]
    [int]$MaxValueLength = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Multi-tenant root detection

# Accept either a tenant folder (containing dated run folders) or the root above it
# (containing tenant folders). Explicit loops rather than nested Where-Object: $PSItem
# inside a nested filter refers to the inner pipeline, which is an easy way to write a
# filter that silently matches nothing.
function Test-ContainsRunFolder {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory)][string]$Path)

    foreach ($child in @(Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue)) {
        $manifests = @(Get-ChildItem -Path $child.FullName -Filter '_manifest_*.json' -File -ErrorAction SilentlyContinue)
        if ($manifests.Count -gt 0) { return $true }
    }
    return $false
}

if (-not (Test-ContainsRunFolder -Path $TenantDirectory)) {
    $tenantFolders = [System.Collections.Generic.List[object]]::new()
    foreach ($child in @(Get-ChildItem -Path $TenantDirectory -Directory -ErrorAction SilentlyContinue)) {
        if (Test-ContainsRunFolder -Path $child.FullName) { $tenantFolders.Add($child) }
    }

    if ($tenantFolders.Count -gt 0) {
        Write-Verbose ('"{0}" holds {1} tenant folder(s) - processing each in turn.' -f
            $TenantDirectory, $tenantFolders.Count)

        # BaselineRun/CurrentRun/OutputPath are per-tenant and deliberately not forwarded.
        $forwarded = @{ MaxValueLength = $MaxValueLength }
        if ($NoPlatformSplit.IsPresent) { $forwarded['NoPlatformSplit'] = $true }

        foreach ($tenant in $tenantFolders) {
            & $PSCommandPath -TenantDirectory $tenant.FullName @forwarded
        }
        return
    }
}

#endregion Multi-tenant root detection

#region Taxonomy

# Category grouping. Order controls page order in the change set.
$categoryDefinitions = @(
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

    [pscustomobject]@{ Order = 6; Key = 'enrollment'; Title = 'Enrollment & Autopilot'
        Areas = @('Autopilot Deployment Profile', 'Enrollment Configuration') }

    [pscustomobject]@{ Order = 7; Key = 'updates'; Title = 'Windows Update Rings'
        Areas = @('Windows Feature Update Profile', 'Windows Quality Update Profile',
                  'Windows Driver Update Profile') }

    [pscustomobject]@{ Order = 8; Key = 'filters'; Title = 'Assignment Filters'
        Areas = @('Assignment Filter') }

    [pscustomobject]@{ Order = 9; Key = 'conditionalaccess'; Title = 'Conditional Access'
        Areas = @('Conditional Access Policy') }
)

# Canonical platforms. Order controls page order within a category.
$platformDefinitions = @(
    [pscustomobject]@{ Order = 1; Name = 'Windows'; Slug = 'windows' }
    [pscustomobject]@{ Order = 2; Name = 'macOS'; Slug = 'macos' }
    [pscustomobject]@{ Order = 3; Name = 'iOS/iPadOS'; Slug = 'ios' }
    [pscustomobject]@{ Order = 4; Name = 'Android'; Slug = 'android' }
    [pscustomobject]@{ Order = 5; Name = 'Linux'; Slug = 'linux' }
    [pscustomobject]@{ Order = 6; Name = 'Cross-platform'; Slug = 'cross-platform' }
)

# Lowercase lookup for whatever Graph put in the Platform column.
$platformAliases = @{
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
$typePatterns = @(
    [pscustomobject]@{ Pattern = '^macos'; Platform = 'macOS' }
    [pscustomobject]@{ Pattern = '^(ios|ipad)'; Platform = 'iOS/iPadOS' }
    [pscustomobject]@{ Pattern = '^(android|aosp)'; Platform = 'Android' }
    [pscustomobject]@{ Pattern = '^(windows|win32|defender|sharedpc|editionupgrade)'; Platform = 'Windows' }
    [pscustomobject]@{ Pattern = 'macos'; Platform = 'macOS' }
    [pscustomobject]@{ Pattern = 'windows'; Platform = 'Windows' }
    [pscustomobject]@{ Pattern = 'android'; Platform = 'Android' }
)

# The platform an area implies when Graph exposes none.
$areaPlatformDefaults = @{
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
$sidecarPeekAreas = @('Assignment Filter', 'Enrollment Configuration', 'Endpoint Security (Intent)')

#endregion Taxonomy

#region Helpers

function Get-ObjectProperty {
    # StrictMode Latest throws on missing properties, and exports from different script
    # versions may legitimately lack a column.
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
        [Parameter(Mandatory)][System.Collections.Generic.List[object]]$Changes,
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
        lastModifiedDateTime  = [string]$Row.LastModifiedDateTime
        configurationFile     = ('{0}/{1}' -f $RunFolder, ([string]$Row.ConfigurationFile))
    }
}

#endregion Helpers

#region Main

# Run folders are named yyyy-MM-dd HH-mm, so lexical order is chronological.
$runFolders = @(Get-ChildItem -Path $TenantDirectory -Directory | Sort-Object -Property Name)
if ($runFolders.Count -eq 0) {
    throw ('No run folders found under "{0}".' -f $TenantDirectory)
}

$currentFolder = [string]::IsNullOrWhiteSpace($CurrentRun) ? $runFolders[-1].Name : $CurrentRun
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

# Platform is resolved once per record and cached on RecordKey. The current run wins when
# a policy exists in both, so a policy that changed platform is filed under its new one.
$platformCache = @{}
$resolveArgs = @{
    Aliases = $platformAliases; TypePattern = $typePatterns
    AreaDefault = $areaPlatformDefaults; PeekArea = $sidecarPeekAreas
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

$assignmentFields = @('AssignedGroups', 'ExcludedGroups', 'AssignmentFilters')
$metadataFields = @('DisplayName', 'Description', 'Version', 'TemplateName', 'Platform')

$pages = [System.Collections.Generic.List[object]]::new()
$totals = [ordered]@{ baseline = 0; added = 0; removed = 0; uncertain = 0; modified = 0; unchanged = 0 }
$platformTotals = [ordered]@{}

# Without a split every category is emitted as a single pseudo-platform page.
$ignorePlatform = $NoPlatformSplit.IsPresent
$platformScope = $platformDefinitions
if ($ignorePlatform) {
    $platformScope = @([pscustomobject]@{ Order = 0; Name = '*'; Slug = 'all' })
}
Write-Verbose ('Grouping {0} categor(ies) across {1} platform(s)' -f
    $categoryDefinitions.Count, $platformScope.Count)

foreach ($category in $categoryDefinitions) {

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
                    $added.Add((New-RecordSummary -Row $row -RunFolder $currentFolder -Platforms $platforms))
                    continue
                }

                $old = $baseline.Records[$row.RecordKey]

                # Three independent signals - see the note in .DESCRIPTION about assignments
                # living outside ConfigurationHash.
                $configChanged = ([string]$old.ConfigurationHash -ne [string]$row.ConfigurationHash)

                $assignmentChanges = [System.Collections.Generic.List[object]]::new()
                foreach ($field in $assignmentFields) {
                    if ([string]$old.$field -ne [string]$row.$field) {
                        $assignmentChanges.Add([pscustomobject][ordered]@{
                            field = $field; oldValue = [string]$old.$field; newValue = [string]$row.$field
                        })
                    }
                }

                $metadataChanges = [System.Collections.Generic.List[object]]::new()
                foreach ($field in $metadataFields) {
                    if ([string]$old.$field -ne [string]$row.$field) {
                        $metadataChanges.Add([pscustomobject][ordered]@{
                            field = $field; oldValue = [string]$old.$field; newValue = [string]$row.$field
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

#endregion Main