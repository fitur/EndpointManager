#Requires -Version 5.1
<#
.SYNOPSIS
    Packages and uploads an Intune Win32 app from a zip-packaged PSADT application.

.DESCRIPTION
    The script accepts a path to a zip file, extracts it to a temporary directory
    alongside the zip file, reads ApplicationInformation.txt, and retrieves the
    .intunewin and .png files. A JSON file in Intune Graph API format (UTF-16 LE)
    is written to the extracted application directory, and the app is uploaded to
    Intune via the IntuneWin32App module using non-interactive client credentials.

    Supported detection rule formats in ApplicationInformation.txt:
      Registry : HKEY_LOCAL_MACHINE\...\KeyPath\ValueName >= 1.0.0
      File     : %ProgramFiles%\App\file.exe >= 1.0.0
      MSI      : {ProductCode-GUID}

    If the PNG icon is missing or unreadable a blank 1x1 pixel PNG is used instead.

    Authentication credentials can be supplied as parameters or via environment
    variables (INTUNE_TENANT_ID, INTUNE_CLIENT_ID, INTUNE_CLIENT_SECRET).

.PARAMETER AppPath
    Full path to the zip file to process.

.PARAMETER TenantID
    Entra ID tenant ID. Falls back to $env:INTUNE_TENANT_ID.

.PARAMETER ClientID
    App registration client ID. Falls back to $env:INTUNE_CLIENT_ID.

.PARAMETER ClientSecret
    App registration client secret. Falls back to $env:INTUNE_CLIENT_SECRET.

.EXAMPLE
    .\New-IntuneWin32AppJson.ps1 -AppPath "C:\AppTest\MyApp_1.0.zip"

.EXAMPLE
    .\New-IntuneWin32AppJson.ps1 -AppPath "C:\AppTest\MyApp_1.0.zip" -TenantID "..." -ClientID "..." -ClientSecret "..."
#>

param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path -Path $_ -PathType Leaf)) {
            throw "AppPath '$_' does not exist or is not a file."
        }
        if ([System.IO.Path]::GetExtension($_) -ne ".zip") {
            throw "AppPath '$_' is not a .zip file."
        }
        return $true
    })]
    [string]$AppPath,

    [Parameter(Mandatory = $false)]
    [string]$TenantID = $env:INTUNE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientID = $env:INTUNE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:INTUNE_CLIENT_SECRET
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve AppPath to absolute path in case a relative path was supplied
$AppPath = (Resolve-Path -Path $AppPath).Path

#region Functions

function Get-AppDescription {
    <#
    .SYNOPSIS
        Fetches the IntuneAppDescriptions.json from SharePoint via Graph API and returns
        the Markdown description for the given app name.
        Matched on Application - Name (exact, then partial).
        Falls back to the display name if no match is found.
    #>
    param (
        [string]$AppName,
        [string]$FallbackName
    )

    $siteId  = "m365x55267076.sharepoint.com,5a8130ca-ae94-4721-a244-6b14a493e8df,261ee28a-f7f4-4c53-871b-6aa5327820e8"
    $itemId  = "01DO5YH6B226WAZ3BBSJEYHABCE4IXIKVU"
    $uri     = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/items/$itemId/content"

    try {
        # Fetch a fresh token using the same client credentials
        $tokenBody = @{
            grant_type    = "client_credentials"
            client_id     = $ClientID
            client_secret = $ClientSecret
            scope         = "https://graph.microsoft.com/.default"
        }
        $token   = (Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token" -Method Post -Body $tokenBody).access_token
        $headers = @{ Authorization = "Bearer $token" }

        $json        = Invoke-RestMethod -Uri $uri -Headers $headers
        $descriptions = $json | ConvertTo-Json -Depth 2 | ConvertFrom-Json -AsHashtable
    }
    catch {
        Write-Warning "Could not fetch app descriptions from SharePoint: $_ - using display name as fallback."
        return $FallbackName
    }

    # Exact match
    if ($descriptions.ContainsKey($AppName)) {
        return $descriptions[$AppName]
    }

    # Partial match
    foreach ($key in $descriptions.Keys) {
        if ($AppName -like "*$key*" -or $key -like "*$AppName*") {
            return $descriptions[$key]
        }
    }

    Write-Warning "No description found for '$AppName' in SharePoint JSON - using display name as fallback."
    return $FallbackName
}


function Get-AppInfoValue {
    <#
    .SYNOPSIS
        Reads a value from ApplicationInformation.txt based on a label.
        Returns $null if the label is not found.
    #>
    param (
        [string]$Content,
        [string]$Label
    )
    if ($Content -match "(?m)^$Label[\s.]*:\s*(.+)$") {
        return $Matches[1].Trim()
    }
    return $null
}

function ConvertTo-MB {
    <#
    .SYNOPSIS
        Converts a disk space string (e.g. "500 MB", "2 GB") to an integer in MB.
        Returns $null if the string cannot be parsed.
    #>
    param (
        [string]$DiskSpaceString
    )
    if ($DiskSpaceString -match "(\d+(?:[.,]\d+)?)\s*(MB|GB|TB)") {
        $value = [double]($Matches[1] -replace ",", ".")
        switch ($Matches[2]) {
            "MB" { return [int]$value }
            "GB" { return [int]($value * 1024) }
            "TB" { return [int]($value * 1024 * 1024) }
        }
    }
    return $null
}

function Expand-AppPackage {
    <#
    .SYNOPSIS
        Extracts a zip file to a temporary directory (AppUnzip) next to the zip file.
        If the directory already exists it is cleared before extraction.
        Returns the path to the temp directory.
    #>
    param (
        [string]$ZipPath
    )
    $parentDir = [System.IO.Path]::GetDirectoryName([System.IO.Path]::GetFullPath($ZipPath))
    $tempDir   = Join-Path -Path $parentDir -ChildPath "AppUnzip"

    if (Test-Path -Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
    New-Item -Path $tempDir -ItemType Directory | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $tempDir
    return $tempDir
}

function Get-PngBase64 {
    <#
    .SYNOPSIS
        Reads a PNG file and returns it as a base64 string.
        If the file is missing or unreadable, returns a base64-encoded blank 1x1 PNG instead.
    #>
    param (
        [System.IO.FileInfo]$PngFile
    )

    # Minimal valid 1x1 transparent PNG (68 bytes)
    $blankPng = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

    if ($null -eq $PngFile) {
        Write-Warning "No PNG file found - using blank icon."
        return $blankPng
    }

    try {
        return [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($PngFile.FullName))
    }
    catch {
        Write-Warning "Could not read PNG file '$($PngFile.FullName)': $_  - using blank icon."
        return $blankPng
    }
}

function Parse-DetectionRule {
    <#
    .SYNOPSIS
        Parses a detection rule string from ApplicationInformation.txt.
        Supports registry, file and MSI product code detection.

        Returns a hashtable with two keys:
          - DetectionRule : used in the "detectionRules" block (portal/UI)
          - Rule          : used in the "rules" block (Graph API import)

        Throws a descriptive error if the string cannot be parsed.

    .NOTES
        Operator mapping:
          >=  -> greaterThanOrEqual  (version comparison)
          >   -> greaterThan         (version comparison)
          <=  -> lessThanOrEqual     (version comparison)
          <   -> lessThan            (version comparison)
          =   -> equal               (version if value looks like x.y.z, otherwise string)
    #>
    param (
        [string]$DetectionString
    )

    $operatorMap = @{
        ">=" = "greaterThanOrEqual"
        "="  = "equal"
        "<=" = "lessThanOrEqual"
        ">"  = "greaterThan"
        "<"  = "lessThan"
    }

    # --- Registry: HKEY_...\KeyPath\ValueName <op> value ---
    if ($DetectionString -match "^(HKEY_.+)\\([^\\]+?)\s*(>=|=|<=|>|<)\s*(.+)$") {
        $keyPath   = $Matches[1]
        $valueName = $Matches[2].Trim()
        $operator  = $Matches[3]
        $detValue  = $Matches[4].Trim()

        # Use "version" for all range operators, and also for "=" when value looks like a version number
        $isVersionValue    = $detValue -match "^\d+(\.\d+){1,3}$"
        $isVersionOperator = $operator -in @(">=", "<=", ">", "<")
        $typeValue         = if ($isVersionOperator -or ($operator -eq "=" -and $isVersionValue)) { "version" } else { "string" }
        $operatorMapped    = $operatorMap[$operator]

        return @{
            DetectionRule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppRegistryDetection"
                "check32BitOn64System" = $false
                "keyPath"              = $keyPath
                "valueName"            = $valueName
                "detectionType"        = $typeValue
                "operator"             = $operatorMapped
                "detectionValue"       = $detValue
            }
            Rule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppRegistryRule"
                "ruleType"             = "detection"
                "check32BitOn64System" = $false
                "keyPath"              = $keyPath
                "valueName"            = $valueName
                "operationType"        = $typeValue
                "operator"             = $operatorMapped
                "comparisonValue"      = $detValue
            }
        }
    }

    # --- File: path\to\file.exe <op> value ---
    if ($DetectionString -match "^(%[^%]+%\\[^<>=]+|[A-Za-z]:\\[^<>=]+)\s*(>=|=|<=|>|<)\s*(.+)$") {
        $filePath  = $Matches[1].Trim()
        $operator  = $Matches[2]
        $detValue  = $Matches[3].Trim()

        $folder    = [System.IO.Path]::GetDirectoryName($filePath)
        $fileName  = [System.IO.Path]::GetFileName($filePath)

        $isVersionValue    = $detValue -match "^\d+(\.\d+){1,3}$"
        $isVersionOperator = $operator -in @(">=", "<=", ">", "<")
        $typeValue         = if ($isVersionOperator -or ($operator -eq "=" -and $isVersionValue)) { "version" } else { "string" }
        $operatorMapped    = $operatorMap[$operator]

        return @{
            DetectionRule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppFileSystemDetection"
                "check32BitOn64System" = $false
                "path"                 = $folder
                "fileOrFolderName"     = $fileName
                "detectionType"        = $typeValue
                "operator"             = $operatorMapped
                "detectionValue"       = $detValue
            }
            Rule = [ordered]@{
                "@odata.type"          = "#microsoft.graph.win32LobAppFileSystemRule"
                "ruleType"             = "detection"
                "check32BitOn64System" = $false
                "path"                 = $folder
                "fileOrFolderName"     = $fileName
                "operationType"        = $typeValue
                "operator"             = $operatorMapped
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

    # Nothing matched - throw with the raw string so the operator can see exactly what was in the file
    throw "Detection rule could not be parsed. Unsupported format or missing operator.`n  Raw value: '$DetectionString'`n  Supported formats:`n    Registry : HKEY_LOCAL_MACHINE\...\KeyPath\ValueName >= 1.0`n    File     : %ProgramFiles%\App\file.exe >= 1.0`n    MSI      : {ProductCode-GUID}"
}

function New-IntuneDetectionRuleObject {
    <#
    .SYNOPSIS
        Builds an IntuneWin32App module detection rule object from a parsed detection rule.
        Selects the correct parameter set automatically based on detection type.
    #>
    param (
        [hashtable]$ParsedRule
    )

    $dr = $ParsedRule.DetectionRule

    switch ($dr.'@odata.type') {

        "#microsoft.graph.win32LobAppRegistryDetection" {
            switch ($dr.detectionType) {
                "version" {
                    return New-IntuneWin32AppDetectionRuleRegistry `
                        -VersionComparison `
                        -KeyPath                   $dr.keyPath `
                        -ValueName                 $dr.valueName `
                        -Check32BitOn64System      $false `
                        -VersionComparisonOperator $dr.operator `
                        -VersionComparisonValue    $dr.detectionValue
                }
                "string" {
                    return New-IntuneWin32AppDetectionRuleRegistry `
                        -StringComparison `
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
                    return New-IntuneWin32AppDetectionRuleFile `
                        -VersionComparison `
                        -Path                      $dr.path `
                        -FileOrFolder              $dr.fileOrFolderName `
                        -Check32BitOn64System      $false `
                        -VersionComparisonOperator $dr.operator `
                        -VersionComparisonValue    $dr.detectionValue
                }
                "string" {
                    return New-IntuneWin32AppDetectionRuleFile `
                        -StringComparison `
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

#endregion Functions

#region Step 1 - Validate credentials

$missingCredentials = @()
if (-not $TenantID)     { $missingCredentials += "TenantID (or env:INTUNE_TENANT_ID)" }
if (-not $ClientID)     { $missingCredentials += "ClientID (or env:INTUNE_CLIENT_ID)" }
if (-not $ClientSecret) { $missingCredentials += "ClientSecret (or env:INTUNE_CLIENT_SECRET)" }

if ($missingCredentials.Count -gt 0) {
    Write-Error "Missing required authentication credentials: $($missingCredentials -join ', ')"
    exit 1
}

#endregion

#region Step 2 - Extract zip

Write-Host "`n=== Step 2: Extraction ===" -ForegroundColor Cyan

try {
    $tempDir = Expand-AppPackage -ZipPath $AppPath
    Write-Host "Extracted to: $tempDir"
}
catch {
    Write-Error "Error during extraction: $_"
    exit 1
}

#endregion

#region Step 3 - Locate extracted directory and files

Write-Host "`n=== Step 3: Files ===" -ForegroundColor Cyan

try {
    $unzippedDir = Get-ChildItem -Path $tempDir -Directory | Select-Object -First 1
    if (-not $unzippedDir) {
        Write-Error "No directory found in $tempDir"
        exit 1
    }
    Write-Host "Extracted directory: $($unzippedDir.FullName)"

    $appInfoFile   = Get-ChildItem -Path $unzippedDir.FullName -Filter "ApplicationInformation.txt" | Select-Object -First 1
    $intunewinFile = Get-ChildItem -Path $unzippedDir.FullName -Filter "*.intunewin" | Select-Object -First 1
    $pngFile       = Get-ChildItem -Path $unzippedDir.FullName -Filter "*.png" | Select-Object -First 1

    if (-not $appInfoFile)   { Write-Error "ApplicationInformation.txt not found in $($unzippedDir.FullName)"; exit 1 }
    if (-not $intunewinFile) { Write-Error "No .intunewin file found in $($unzippedDir.FullName)"; exit 1 }

    Write-Host "ApplicationInformation : $($appInfoFile.Name)"
    Write-Host "Intunewin file         : $($intunewinFile.Name)"
    if ($pngFile) { Write-Host "PNG file               : $($pngFile.Name)" }
    else          { Write-Warning "No PNG file found - a blank icon will be used." }
}
catch {
    Write-Error "Error while reading files: $_"
    exit 1
}

#endregion

#region Step 4 - Read and parse ApplicationInformation.txt

Write-Host "`n=== Step 4: ApplicationInformation.txt ===" -ForegroundColor Cyan

try {
    $appInfo = Get-Content -Path $appInfoFile.FullName -Raw

    $vendor          = Get-AppInfoValue -Content $appInfo -Label "Application - Vendor"
    $appName         = Get-AppInfoValue -Content $appInfo -Label "Application - Name"
    $appVersion      = Get-AppInfoValue -Content $appInfo -Label "Application - Version"
    $installCmd      = Get-AppInfoValue -Content $appInfo -Label "Install command"
    $uninstallCmd    = Get-AppInfoValue -Content $appInfo -Label "Uninstall command"
    $detectionMethod = Get-AppInfoValue -Content $appInfo -Label "DetectionMethod\.\(REG\)"
    $diskSpace       = Get-AppInfoValue -Content $appInfo -Label "Estimated Disk Space"

    $missingFields = @()
    if (-not $vendor)          { $missingFields += "Application - Vendor" }
    if (-not $appName)         { $missingFields += "Application - Name" }
    if (-not $appVersion)      { $missingFields += "Application - Version" }
    if (-not $installCmd)      { $missingFields += "Install command" }
    if (-not $uninstallCmd)    { $missingFields += "Uninstall command" }
    if (-not $detectionMethod) { $missingFields += "DetectionMethod.(REG)" }

    if ($missingFields.Count -gt 0) {
        Write-Error "Missing required fields in ApplicationInformation.txt: $($missingFields -join ', ')"
        exit 1
    }

    Write-Host "Vendor   : $vendor"
    Write-Host "Name     : $appName"
    Write-Host "Version  : $appVersion"
    Write-Host "Install  : $installCmd"
    Write-Host "Uninstall: $uninstallCmd"
    Write-Host "Detection: $detectionMethod"
    Write-Host "Disk     : $(if ($diskSpace) { $diskSpace } else { '(not specified)' })"
}
catch {
    Write-Error "Error while parsing ApplicationInformation.txt: $_"
    exit 1
}

#endregion

#region Step 5 - Build and export JSON

Write-Host "`n=== Step 5: Build JSON ===" -ForegroundColor Cyan

try {
    $today       = Get-Date -Format "yyyy-MM-dd"
    $todayUtc    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.ffffffZ")
    $displayName   = "$vendor $appName $appVersion"
    $appDescription = Get-AppDescription -AppName $appName -FallbackName $displayName
    $diskSpaceMB   = ConvertTo-MB -DiskSpaceString $diskSpace
    $pngBase64   = Get-PngBase64 -PngFile $pngFile

    $parsed = Parse-DetectionRule -DetectionString $detectionMethod
    Write-Host "Detection type : $($parsed.DetectionRule.'@odata.type' -replace '#microsoft.graph.win32LobApp','')"
    Write-Host "Detection dtype: $($parsed.DetectionRule.detectionType ?? $parsed.DetectionRule.productVersionOperator)"

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
        "owner"                   = "Advania"
        "developer"               = ""
        "notes"                   = "Basapplikation $today"
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
        "allowedArchitectures"    = "x64"
        "minimumFreeDiskSpaceInMB"       = $diskSpaceMB
        "minimumMemoryInMB"              = $null
        "minimumNumberOfProcessors"      = $null
        "minimumCpuSpeedInMHz"           = $null
        "msiInformation"                 = $null
        "setupFilePath"                  = "${appName}_${appVersion}.txt"
        "minimumSupportedWindowsRelease" = "Windows11_21H2"
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
        "detectionRules"   = @($parsed.DetectionRule)
        "requirementRules" = @()
        "rules"            = @($parsed.Rule)
        "installExperience" = [ordered]@{
            "runAsAccount"          = "system"
            "maxRunTimeInMinutes"   = 60
            "deviceRestartBehavior" = "basedOnReturnCode"
        }
        "returnCodes" = @(
            [ordered]@{ "returnCode" = 0;    "type" = "success" }
            [ordered]@{ "returnCode" = 1707; "type" = "success" }
            [ordered]@{ "returnCode" = 3010; "type" = "softReboot" }
            [ordered]@{ "returnCode" = 1641; "type" = "softReboot" }
            [ordered]@{ "returnCode" = 1618; "type" = "retry" }
        )
        "categories"  = @()
        "assignments" = @()
    }

    $outputPath = Join-Path -Path $unzippedDir.FullName -ChildPath "$displayName.json"
    [System.IO.File]::WriteAllText($outputPath, ($appJson | ConvertTo-Json -Depth 10), [System.Text.Encoding]::Unicode)
    Write-Host "JSON saved to: $outputPath" -ForegroundColor Green
}
catch {
    Write-Error "Error while generating JSON: $_"
    exit 1
}

#endregion

#region Step 6 - Upload to Intune

Write-Host "`n=== Step 6: Upload to Intune ===" -ForegroundColor Cyan

try {
    if (-not (Get-Module -ListAvailable -Name IntuneWin32App)) {
        Write-Host "Installing IntuneWin32App module..."
        Install-Module -Name IntuneWin32App -Scope CurrentUser -Force
    }
    Import-Module IntuneWin32App

    Connect-MSIntuneGraph -TenantID $TenantID -ClientID $ClientID -ClientSecret $ClientSecret
    Write-Host "Authenticated to Microsoft Graph"
}
catch {
    Write-Error "Authentication failed: $_"
    exit 1
}

try {
    # Build icon - write blank PNG to temp file if no PNG was found
    if ($pngFile) {
        $iconParam = New-IntuneWin32AppIcon -FilePath $pngFile.FullName
    }
    else {
        $blankPngPath = Join-Path -Path $tempDir -ChildPath "blank.png"
        [System.IO.File]::WriteAllBytes($blankPngPath, [System.Convert]::FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        ))
        $iconParam = New-IntuneWin32AppIcon -FilePath $blankPngPath
    }

    # Do not pass -ReturnCode to avoid duplicates - the module always adds its default set
    # (0 success, 1707 success, 3010 softReboot, 1641 hardReboot, 1618 retry).
    # Return code 1641 is patched to softReboot via Graph API after upload.
    $win32App = Add-IntuneWin32App `
        -FilePath             $intunewinFile.FullName `
        -DisplayName          $displayName `
        -Description          $appDescription `
        -Publisher            $vendor `
        -AppVersion           $appVersion `
        -Notes                "Basapplikation $today" `
        -InstallCommandLine   $installCmd `
        -UninstallCommandLine $uninstallCmd `
        -InstallExperience    "system" `
        -RestartBehavior      "basedOnReturnCode" `
        -DetectionRule        (New-IntuneDetectionRuleObject -ParsedRule $parsed) `
        -Icon                 $iconParam `
        -Verbose

    # The module emits multiple pipeline objects; find the one with an 'id' NoteProperty
    $appObject = @($win32App) | Where-Object { $_ -isnot [string] -and $null -ne $_.id } | Select-Object -First 1
    $appId     = if ($appObject) { $appObject.id } else { $null }

    if (-not $appId) {
        Write-Warning "App was uploaded but ID could not be retrieved - skipping return code patch. Verify in Intune portal."
    }
    else {
        Write-Host "App uploaded successfully. Intune App ID: $appId" -ForegroundColor Green

        # Patch return code 1641 from hardReboot (module default) to softReboot via Graph API
        $graphUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$appId"
        $patchBody = @{
            "@odata.type" = "#microsoft.graph.win32LobApp"
            returnCodes   = @(
                @{ returnCode = 0;    type = "success" }
                @{ returnCode = 1707; type = "success" }
                @{ returnCode = 3010; type = "softReboot" }
                @{ returnCode = 1641; type = "softReboot" }
                @{ returnCode = 1618; type = "retry" }
            )
        } | ConvertTo-Json -Depth 5

        # Reuse the authentication header stored by Connect-MSIntuneGraph
        Invoke-RestMethod -Uri $graphUri -Method Patch -Headers @{
            Authorization  = $Global:AuthenticationHeader.Authorization
            "Content-Type" = "application/json"
        } -Body $patchBody | Out-Null
        Write-Host "Return code 1641 patched to softReboot." -ForegroundColor Green
    }
}
catch {
    Write-Error "Upload failed: $_"
    exit 1
}

#endregion

#region Cleanup

if (Test-Path -Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
    Write-Host "`nCleaned up: $tempDir" -ForegroundColor DarkGray
}

#endregion