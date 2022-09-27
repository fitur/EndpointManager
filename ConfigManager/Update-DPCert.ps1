<#

.SYNOPSIS
    PowerShell script to update certificate on all CM distribution points.

.EXAMPLE
    .\Update-DPCert.ps1

.DESCRIPTION
    This PowerShell script is supposed to be manually run whenever a certificate is pending renewal.

.LINK
    https://docs.microsoft.com/en-us/mem/analytics/proactive-remediations

.NOTES
    Version:        1.0
    Creation Date:  September 27, 2022
    Last Updated:   September 27, 2022
    Author:         Peter Olausson
    Contact:        admin@fitur.se
    Web Site:       https://github.com/fitur

#>

# Attempt to load CM module
try {
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
    Set-location $SiteCode":" -ErrorAction Stop
}
catch [System.Exception] {
    Write-Warning -Message $_.Exception.Message
}

# Edit certificate parameters
$CertPath = "\\path\to\certfile.pfx"
$CertPW = "password-in-plain-text" | ConvertTo-SecureString -AsPlainText -Force

# Run import on all distributionpoints which currently use a certificate
Get-CMDistributionPoint | Where-Object {($_.EmbeddedProperties.CertificateFile.Value1) -and ($_.EmbeddedProperties.CertificateFile.Value1 -ne $CertPath)} | ForEach-Object {
    $_ | Set-CMDistributionPoint -CertificatePath $CertPath -CertificatePassword $CertPW -UserDeviceAffinity AllowWithAutomaticApproval -Force -WarningAction SilentlyContinue
} 
