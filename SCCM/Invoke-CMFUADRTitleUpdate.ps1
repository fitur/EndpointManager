[CmdletBinding()]
param (
    [Parameter(mandatory=$false)]
    [string]
    $ADRName =  "ADR - Client - Feature Update - Windows 10*"
)
begin {
    # Import CM environment
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    } 
    
    # Set URI and open webrequest
    $URI = "https://en.wikipedia.org/wiki/Windows_10_version_history"
    $WebRequest = Invoke-WebRequest -Uri $URI

    # Create array
    $W10Versions = New-Object -TypeName System.Collections.ArrayList

    # Scrape Wikipedia for W10 versions
    ($WebRequest.ParsedHtml.getElementsByClassName("wikitable plainrowheaders")[0].outerText.Split([Environment]::NewLine) | Select-String -Pattern "^(\d{2}\S{2}\s)") | Sort-Object -Descending | ForEach-Object {[void]$W10Versions.Add(([string]$_).substring(0,4))}
}
process {
    if ($W10Versions.Count -gt 8) {
        try {
            Get-CMAutoDeploymentRule -Name $ADRName -Fast | ForEach-Object {
                $Version = $W10Versions -match $_.Name.Substring($_.Name.Length-2) | Select-Object -First 1
                $_ | Set-CMAutoDeploymentRule -CustomSeverity None -DateReleasedOrRevised Last1Month -Required ">0" -Superseded $false  -Title "%$Version%","-Consumer" -UpdateClassification "Upgrades" -Force
            }
        }
        catch [System.Exception] {
            Write-Warning -Message $_.Exception.Message
        }
    }    
}
