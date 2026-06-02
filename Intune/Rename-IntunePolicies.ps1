<#
.SYNOPSIS
    Byter namn på Intune-policyer enligt namnstandarden OS-SCOPE-TYP-KAT-Namn.

.DESCRIPTION
    Kan köras i två lägen:

    LÄGE 1 — Automatisk (default):
      Hämtar policyer via Graph, mappar namn med heuristik, visar dry run.
      Använd -ExportCsv för att spara förslaget till CSV för manuell granskning.

    LÄGE 2 — CSV-styrd:
      Läs in en CSV med kolumnerna Id, CurrentName, NewName, GraphType.
      Skriptet slår upp varje rad i Graph för att verifiera att Id finns,
      visar en tabell och utför sedan namnbytena.
      Aktiveras med -ImportCsv <sökväg>.

    Båda lägena stöder -WhatIf för dry run.

.PARAMETER Prefix
    (Läge 1) Filtrerar på att displayName börjar med detta värde.
    Exempel: "Windows - ". Utelämna för att behandla alla.

.PARAMETER PolicyType
    (Läge 1) Begränsa till vissa policytyper. Default: alla.

.PARAMETER ExportCsv
    (Läge 1) Exporterar namnförslagen till en CSV-fil för manuell granskning.

.PARAMETER CsvPath
    Sökväg för export (Läge 1) eller import (Läge 2).
    Default för export: .\IntuneRename_<datum>.csv

.PARAMETER ImportCsv
    (Läge 2) Sökväg till en behandlad CSV med kolumnerna:
      Id, CurrentName, NewName, GraphType
    Rader där NewName är tomt eller samma som CurrentName hoppas över.

.PARAMETER TenantId
    Tenant-ID för app-baserad autentisering (service principal).

.PARAMETER ClientId
    Client-ID (Application ID) för App Registration.

.PARAMETER ClientSecret
    Client Secret som SecureString. Används tillsammans med TenantId och ClientId.

.EXAMPLE
    # Läge 1 — dry run med export av förslag
    $secret = Read-Host "Secret" -AsSecureString
    .\Rename-IntunePolicies.ps1 -Prefix "Windows - " -ExportCsv -WhatIf `
        -TenantId "..." -ClientId "..." -ClientSecret $secret

.EXAMPLE
    # Läge 2 — utför namnbyte från granskad CSV
    .\Rename-IntunePolicies.ps1 -ImportCsv ".\IntuneRename_20260320.csv" `
        -TenantId "..." -ClientId "..." -ClientSecret $secret

.NOTES
    Kräver Microsoft.Graph-modulen.
    App Registration behöver: DeviceManagementConfiguration.ReadWrite.All
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    # Läge 1
    [Parameter(ParameterSetName = 'Auto')]
    [string]$Prefix = "",

    [Parameter(ParameterSetName = 'Auto')]
    [ValidateSet('Configuration','SettingsCatalog','Compliance','Remediation','PlatformScript','Filter','All')]
    [string[]]$PolicyType = @('All'),

    [Parameter(ParameterSetName = 'Auto')]
    [switch]$ExportCsv,

    [Parameter(ParameterSetName = 'Auto')]
    [string]$CsvPath = "",

    # Läge 2
    [Parameter(ParameterSetName = 'FromCsv', Mandatory)]
    [string]$ImportCsv,

    # Gemensamt
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$ClientSecret,

    [Parameter()]
    [string]$TenantName = ""
)

#region --- Anslutning ---------------------------------------------------------
# Token lagras i script-scope och skickas i Authorization-header på varje anrop.
# Connect-MgGraph används endast som fallback vid interaktiv inloggning.
$script:AuthHeader = $null

function Connect-Graph {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )

    if ($TenantId -and $ClientId -and $ClientSecret) {
        Write-Host "Ansluter till Graph med App Registration (client credentials)..." -ForegroundColor Cyan
        $tokenBody = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = 'https://graph.microsoft.com/.default'
        }
        try {
            $tokenResponse = Invoke-RestMethod `
                -Method Post `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -Body $tokenBody `
                -ContentType 'application/x-www-form-urlencoded' `
                -ErrorAction Stop

            $script:AuthHeader = @{ Authorization = "Bearer $($tokenResponse.access_token)" }
            Write-Host "Token hämtad. Ansluten som App Registration." -ForegroundColor DarkGray
        }
        catch {
            Write-Error "Kunde inte hämta access token: $($_.Exception.Message)"
        }
        return
    }

    # Interaktiv fallback — använder Connect-MgGraph som vanligt
    $required = 'DeviceManagementConfiguration.ReadWrite.All'
    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx -or $ctx.Scopes -notcontains $required) {
        Write-Host "Ansluter interaktivt till Microsoft Graph..." -ForegroundColor Cyan
        Connect-MgGraph -Scopes $required -NoWelcome
    }
    else {
        Write-Host "Redan ansluten till Graph som $($ctx.Account)." -ForegroundColor DarkGray
    }
}

# Wrapper som väljer rätt anropsmetod beroende på om vi har en token eller MgGraph-session
function Invoke-GraphRequest {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body,
        [string]$ContentType = 'application/json'
    )
    if ($script:AuthHeader) {
        $params = @{
            Method  = $Method
            Uri     = $Uri
            Headers = $script:AuthHeader
            ErrorAction = 'Stop'
        }
        if ($Body) {
            $params.Body        = $Body
            $params.ContentType = $ContentType
        }
        return Invoke-RestMethod @params
    }
    else {
        $params = @{
            Method      = $Method
            Uri         = $Uri
            ErrorAction = 'Stop'
        }
        if ($Body) {
            $params.Body        = $Body
            $params.ContentType = $ContentType
        }
        return Invoke-MgGraphRequest @params
    }
}
#endregion

#region --- Tenant-namn -------------------------------------------------------
function Get-TenantName {
    param([string]$Override = "")

    # Använd manuellt angivet namn om det finns
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        $safe = $Override -replace '[\/:*?"<>|]', '' -replace '\s+', '_'
        return $safe
    }

    # Annars hämta från Graph (kräver Organization.Read.All)
    try {
        $org = Invoke-GraphRequest -Method GET -Uri 'https://graph.microsoft.com/v1.0/organization'
        $displayName = $org.value[0].displayName
        $safe = $displayName -replace '[\/:*?"<>|]', '' -replace '\s+', '_'
        return $safe
    }
    catch {
        Write-Warning "Kunde inte hämta tenant-namn automatiskt (saknar Organization.Read.All?)."
        Write-Warning "Använd parametern -TenantName 'Kundnamn' för att ange namnet manuellt."
        return 'UnknownTenant'
    }
}
#endregion

#region --- Namnmappning -------------------------------------------------------
function Get-NewName {
    param(
        [string]$OldName,
        [string]$GraphType
    )

    $name = $OldName.Trim()

    # Splitta ENDAST på bindestreck som har mellanslag på minst en sida.
    # Detta bevarar "Wi-Fi", "(2025-03-13)" och "802.1x" som hela enheter.
    $segments = $name -split '\s+-\s*|\s*-\s+' | Where-Object { $_ -ne '' }

    # --- OS ---
    $osMap = @{
        'Windows' = 'WIN'; 'WIN' = 'WIN'
        'iOS'     = 'IOS'
        'macOS'   = 'MAC'; 'MAC' = 'MAC'
        'Android' = 'AND'; 'AND' = 'AND'
        'Linux'   = 'LNX'; 'LNX' = 'LNX'
        'All'     = 'ALL'
    }
    $os = 'WIN'
    if ($segments.Count -ge 1 -and $osMap.ContainsKey($segments[0])) {
        $os = $osMap[$segments[0]]
        $segments = @($segments | Select-Object -Skip 1)
    }

    # --- SCOPE ---
    $scopeMap = @{ 'Base' = 'B'; 'B' = 'B'; 'Custom' = 'C'; 'C' = 'C' }
    $scope = 'C'
    if ($segments.Count -ge 1 -and $scopeMap.ContainsKey($segments[0])) {
        $scope = $scopeMap[$segments[0]]
        $segments = @($segments | Select-Object -Skip 1)
    }

    $rest = ($segments -join ' ').Trim()

    # --- TYP + KAT (utvärderas tillsammans för rätt klassificering) ---
    # Default-värden, kan skrivas över nedan
    $typ = $null
    $kat = $null

    switch ($GraphType) {
        'Compliance'     { $typ = 'CO' }
        'Remediation'    { $typ = 'RM' }
        'PlatformScript' { $typ = 'SC'; $kat = 'PS' }
        'Filter'         { $typ = 'FI'; $kat = 'DEV' }
    }

    # För Configuration / SettingsCatalog: härled TYP och KAT från innehåll.
    if (-not $typ) {
        switch -Regex ($rest) {
            # --- Endpoint Security ---
            'BitLocker|FileVault'                  { $typ = 'ES'; $kat = 'BTL'; break }
            'Attack Surface|\bASR\b'               { $typ = 'ES'; $kat = 'ASR'; break }
            'Security Baseline'                    { $typ = 'ES'; $kat = 'SB';  break }
            'LAPS|Windows Hello|Account Protection'{ $typ = 'ES'; $kat = 'AP';  break }
            'Firewall'                             { $typ = 'ES'; $kat = 'FW';  break }
            'MDE|Defender for Endpoint|Endpoint Detection|\bEDR\b|Onboarding|Offboarding' { $typ = 'ES'; $kat = 'EDR'; break }
            'Antivirus|Microsoft Defender Antivirus' { $typ = 'ES'; $kat = 'AV'; break }
            # --- Configuration Profiles med specifik kategori ---
            'Wi-?Fi|Wired|802\.1x|\bVPN\b'         { $typ = 'CP'; $kat = 'WFI'; break }
            'PKCS|SCEP|Trusted Root|Root Certificate|Certificate' { $typ = 'CP'; $kat = 'CRT'; break }
            'Health Monitoring'                    { $typ = 'CP'; $kat = 'WHM'; break }
            'OMA-?URI'                             { $typ = 'CP'; $kat = 'OMA'; break }
            # --- Windows Update ---
            'Feature Update'                       { $typ = 'WU'; $kat = 'FU';  break }
            'Quality Update|Hotpatch'              { $typ = 'WU'; $kat = 'QU';  break }
            'Autopatch'                            { $typ = 'WU'; $kat = 'APC'; break }
            default                                { $typ = 'CP'; $kat = 'SC' }
        }
    }

    # --- Rensa redundanta kategori-/bladord ur det beskrivande namnet ---
    # Tar bort ord som redan uttrycks av TYP/KAT så de inte upprepas.
    $cleanupPatterns = @(
        '^ASR\s+'                       # "ASR iManage" -> "iManage"
        '^Compliance\s+'                # "Compliance Device Health" -> "Device Health"
        '^Security Baseline\s+'         # "Security Baseline Microsoft Edge" -> "Microsoft Edge"
        '^Endpoint Security\s+'         # blandnamn, bladnamn ej del av policynamn
        '^Account Protection\s+'
        '^Filter\s+'                    # "Filter Default" -> "Default"
        '\s+Default$'                   # avslutande "Default" tas bort
    )
    foreach ($pat in $cleanupPatterns) {
        $rest = $rest -replace $pat, ''
    }
    $rest = $rest.Trim()

    # Normalisera dubbla mellanslag som kan uppstå efter rensning
    $rest = $rest -replace '\s{2,}', ' '

    # --- Bygg nytt namn ---
    $parts = @($os, $scope, $typ)
    if ($kat) { $parts += $kat }
    $newName = ($parts -join '-')
    if ($rest) { $newName = "$newName-$rest" }

    return $newName
}
#endregion

#region --- Hämtning -----------------------------------------------------------
$script:EndpointMap = @(
    @{ Key='Configuration';   Type='Configuration';   Uri='https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations';      NameField='displayName' }
    @{ Key='SettingsCatalog'; Type='SettingsCatalog'; Uri='https://graph.microsoft.com/beta/deviceManagement/configurationPolicies';      NameField='name' }
    @{ Key='Compliance';      Type='Compliance';      Uri='https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies';   NameField='displayName' }
    @{ Key='Remediation';     Type='Remediation';     Uri='https://graph.microsoft.com/beta/deviceManagement/deviceHealthScripts';        NameField='displayName' }
    @{ Key='PlatformScript';  Type='PlatformScript';  Uri='https://graph.microsoft.com/beta/deviceManagement/deviceManagementScripts';    NameField='displayName' }
    @{ Key='Filter';          Type='Filter';          Uri='https://graph.microsoft.com/beta/deviceManagement/assignmentFilters';          NameField='displayName' }
)

function Get-IntunePolicies {
    param([string[]]$Types)

    $all = @()
    $wantAll = $Types -contains 'All'

    foreach ($ep in $script:EndpointMap) {
        if (-not $wantAll -and $Types -notcontains $ep.Key) { continue }

        Write-Host "Hämtar $($ep.Key)..." -ForegroundColor Cyan
        $uri = $ep.Uri
        do {
            try   { $resp = Invoke-GraphRequest -Method GET -Uri $uri }
            catch { Write-Warning "Kunde inte hämta $($ep.Key): $($_.Exception.Message)"; break }

            foreach ($item in $resp.value) {
                $currentName = $item.($ep.NameField)
                if ([string]::IsNullOrWhiteSpace($currentName)) { continue }
                $all += [pscustomobject]@{
                    Id          = $item.id
                    CurrentName = $currentName
                    GraphType   = $ep.Type
                    Uri         = $ep.Uri
                    NameField   = $ep.NameField
                }
            }
            $uri = $resp.'@odata.nextLink'
        } while ($uri)
    }
    return $all
}
#endregion

#region --- CSV-import ---------------------------------------------------------
function Import-RenameCsv {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        Write-Error "CSV-filen hittades inte: $Path"
        return $null
    }

    $csv = Import-Csv -Path $Path -Encoding UTF8
    $required = @('Id','CurrentName','NewName','GraphType')
    $missing  = $required | Where-Object { $_ -notin $csv[0].PSObject.Properties.Name }
    if ($missing) {
        Write-Error "CSV saknar obligatoriska kolumner: $($missing -join ', ')"
        return $null
    }

    # Filtrera bort rader utan förändring eller tomt NewName
    $valid = $csv | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.NewName) -and
        $_.NewName -ne $_.CurrentName
    }

    if (-not $valid) {
        Write-Warning "Inga rader i CSV:n har ett nytt namn som skiljer sig från det befintliga."
        return $null
    }

    Write-Host "$($valid.Count) rad(er) i CSV:n har ett nytt namn.`n" -ForegroundColor Green

    # Slå upp endpoint-info per GraphType så vi kan PATCH rätt URI
    $epLookup = @{}
    foreach ($ep in $script:EndpointMap) { $epLookup[$ep.Type] = $ep }

    $results = foreach ($row in $valid) {
        $ep = $epLookup[$row.GraphType]
        if (-not $ep) {
            Write-Warning "Okänd GraphType '$($row.GraphType)' på rad '$($row.CurrentName)' — hoppas över."
            continue
        }
        [pscustomobject]@{
            GraphType   = $row.GraphType
            CurrentName = $row.CurrentName
            NewName     = $row.NewName
            Changed     = $true
            Id          = $row.Id
            _Policy     = [pscustomobject]@{
                Id        = $row.Id
                Uri       = $ep.Uri
                NameField = $ep.NameField
            }
        }
    }
    return $results
}
#endregion

#region --- Namnbyte -----------------------------------------------------------
function Set-PolicyName {
    param(
        [pscustomobject]$Policy,
        [string]$NewName
    )
    $patchUri = "$($Policy.Uri)/$($Policy.Id)"

    # Vissa Graph-resurser kräver @odata.type i PATCH-anropet.
    # Vi hämtar det från det befintliga objektet och skickar det tillsammans
    # med namnfältet. Övriga resurser accepterar partiell PATCH.
    $needsOdataType = $Policy.Uri -like '*deviceConfigurations*' -or
                      $Policy.Uri -like '*deviceCompliancePolicies*'

    if ($needsOdataType) {
        try {
            $existing = Invoke-GraphRequest -Method GET -Uri $patchUri
        }
        catch {
            throw "Kunde inte hämta befintligt objekt för PATCH: $($_.Exception.Message)"
        }
        $odataType = $existing.'@odata.type'
        $bodyHt = @{
            '@odata.type'     = $odataType
            $Policy.NameField = $NewName
        }
        $body = $bodyHt | ConvertTo-Json -Compress
    }
    else {
        $body = @{ $Policy.NameField = $NewName } | ConvertTo-Json -Compress
    }

    Invoke-GraphRequest -Method PATCH -Uri $patchUri -Body $body -ContentType 'application/json'
}
#endregion

#region --- Gemensam utskrift och exekvering -----------------------------------
function Invoke-Rename {
    param([pscustomobject[]]$Results)

    # Visa tabell
    $Results |
        Select-Object GraphType, CurrentName, NewName |
        Sort-Object GraphType, CurrentName |
        Format-Table -AutoSize -Wrap

    $toChange = $Results | Where-Object { $_.Changed }
    if (-not $toChange) {
        Write-Host "Inga namn behöver ändras." -ForegroundColor Yellow
        return
    }

    Write-Host "$($toChange.Count) policy(er) får nytt namn.`n" -ForegroundColor Green

    foreach ($r in $toChange) {
        $target = "$($r.GraphType): '$($r.CurrentName)'"
        if ($PSCmdlet.ShouldProcess($target, "Byt namn till '$($r.NewName)'")) {
            try {
                Set-PolicyName -Policy $r._Policy -NewName $r.NewName
                Write-Host "  [OK]   $($r.CurrentName)  ->  $($r.NewName)" -ForegroundColor Green
            }
            catch {
                Write-Host "  [FEL]  $($r.CurrentName) : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`nKlart." -ForegroundColor Cyan
}
#endregion

#region --- Huvudflöde ---------------------------------------------------------
Connect-Graph -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret

# --- LÄGE 2: CSV-styrd ---
if ($PSCmdlet.ParameterSetName -eq 'FromCsv') {
    Write-Host "Läge: CSV-import från $ImportCsv`n" -ForegroundColor Cyan
    $results = Import-RenameCsv -Path $ImportCsv
    if ($results) { Invoke-Rename -Results $results }
    return
}

# --- LÄGE 1: Automatisk ---
Write-Host "Läge: Automatisk hämtning från Graph`n" -ForegroundColor Cyan

$policies = Get-IntunePolicies -Types $PolicyType

if ($Prefix) {
    $policies = $policies | Where-Object { $_.CurrentName -like "$Prefix*" }
}

if (-not $policies) {
    Write-Warning "Inga policyer matchade filtret '$Prefix'."
    return
}

Write-Host "`n$($policies.Count) policy(er) matchade.`n" -ForegroundColor Green

$results = foreach ($p in $policies) {
    $new = Get-NewName -OldName $p.CurrentName -GraphType $p.GraphType
    [pscustomobject]@{
        GraphType   = $p.GraphType
        CurrentName = $p.CurrentName
        NewName     = $new
        Changed     = ($new -ne $p.CurrentName)
        Id          = $p.Id
        _Policy     = $p
    }
}

if ($ExportCsv) {
    # Bygg absolut sökväg baserat på skriptets katalog om ingen sökväg angetts
    if ([string]::IsNullOrWhiteSpace($CsvPath)) {
        $timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
        $tenantName = Get-TenantName -Override $TenantName
        $CsvPath    = Join-Path $PSScriptRoot "IntuneRename_${tenantName}_$timestamp.csv"
    }
    $CsvPath = [System.IO.Path]::GetFullPath($CsvPath)

    # -WhatIf:$false säkerställer att CSV alltid skrivs, även vid dry run
    $results | Select-Object GraphType, CurrentName, NewName, Changed, Id |
        Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8 -WhatIf:$false

    Write-Host ""
    Write-Host "CSV exporterad till:" -ForegroundColor Green
    Write-Host "  $CsvPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Justera NewName-kolumnen i CSV:n (t.ex. C -> B i scope)" -ForegroundColor Yellow
    Write-Host "2. Kör sedan:" -ForegroundColor Yellow
    Write-Host "   .\Rename-IntunePolicies.ps1 -ImportCsv '$CsvPath' ``" -ForegroundColor White
    Write-Host "       -TenantId '...' -ClientId '...' -ClientSecret '...'" -ForegroundColor White
    Write-Host ""
}

Invoke-Rename -Results $results
#endregion