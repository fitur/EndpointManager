if ((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1"
}

if ((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName
}

Set-Location "$($SiteCode):\" -ErrorAction Stop

Get-CMPackage -name "Drivers - * - Windows 10 2004 x64" -Fast | ForEach-Object {
    Set-Location "$($SiteCode):\" -ErrorAction Stop
    Remove-CMPackage -Id $_.PackageID -Force

    Set-Location $env:SystemDrive -ErrorAction Stop
    Remove-Item -Path ($_.PkgSourcePath | Split-Path -Parent) -Recurse -Force
} 
