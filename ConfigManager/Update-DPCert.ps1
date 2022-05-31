$CertPath = "\\path\to\certfile.pfx"
$CertPW = "password-in-plain-text" | ConvertTo-SecureString -AsPlainText -Force

Get-CMDistributionPoint | Where-Object {$_.EmbeddedProperties.CertificateFile.Value1 -ne $CertPath} | ForEach-Object {
    $_ | Set-CMDistributionPoint -CertificatePath $CertPath -CertificatePassword $CertPW -UserDeviceAffinity AllowWithAutomaticApproval -Force -WarningAction SilentlyContinue
}
