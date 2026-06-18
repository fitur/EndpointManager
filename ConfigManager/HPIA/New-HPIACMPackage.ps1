begin {
    $HPIADir = "\\<CHANGE ME>\HPIA$"
    $LogsDir = "\\<CHANGE ME>\logs$\HPIA"
    $RepoDir = Join-Path -Path $HPIADir -ChildPath "Repository"
    $BinaryDir = Join-Path -Path $HPIADir -ChildPath "Binary"
    $ModuleDir = Join-Path -Path $HPIADir -ChildPath "Modules"
    $CVAPath = Join-Path -Path $HPIADir -ChildPath "CVA.txt"
    $Models = Import-Csv (Join-Path -Path $HPIADir -ChildPath "Models.csv")
    $OSBuilds = Import-Csv (Join-Path -Path $HPIADir -ChildPath "OSBuilds.csv")
    $Blacklist = Import-Csv (Join-Path -Path $HPIADir -ChildPath "Blacklist.csv")
        
    try {
        Import-Module ($Env:SMS_ADMIN_UI_PATH.Substring(0, $Env:SMS_ADMIN_UI_PATH.Length - 5) + '\ConfigurationManager.psd1') -ErrorAction Stop
        $script:SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
        Set-location $SiteCode":" -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
    }
}
process {
    try {
        if ($null -eq ($CMPackage = Get-CMPackage -Name "HP Image Assistant Binary Package" -Fast -ErrorAction SilentlyContinue)) {
            $CMPackage = New-CMPackage -Name "HP Image Assistant Binary Package" -Manufacturer "HP" -Path $BinaryDir -ErrorAction Stop
        }
    }
    catch [System.SystemException] {
        Write-Warning -Message $_.Exception.Message
    }

    if ($null -ne $CMPackage) {
        # Create CM programs for package
        try {
            New-CMProgram -StandardProgramName "Background Update" -PackageId $CMPackage.PackageID -CommandLine ('powershell.exe -ExecutionPolicy Bypass -Command .\Invoke-HPIAUpdate.ps1 -RepoDir "{0}" -LogsDir "{1}" -UpdateType "Background"' -f $RepoDir, $LogsDir) -RunMode RunWithAdministrativeRights -ProgramRunType WhetherOrNotUserIsLoggedOn -RunType Hidden -ErrorAction Stop
            New-CMProgram -StandardProgramName "Live Update" -PackageId $CMPackage.PackageID -CommandLine ('powershell.exe -ExecutionPolicy Bypass -Command .\Invoke-HPIAUpdate.ps1 -RepoDir "{0}" -LogsDir "{1}" -UpdateType "Live"' -f $RepoDir, $LogsDir) -RunMode RunWithAdministrativeRights -ProgramRunType OnlyWhenUserIsLoggedOn -UserInteraction $true -RunType Normal -ErrorAction Stop
        }
        catch [System.SystemException] {
            Write-Warning -Message $_.Exception.Message
        }

        # Distribute content
        try {
            Start-CMContentDistribution -PackageId $CMPackage.PackageID -CollectionName (Get-CMCollection -Id SMS000US -CollectionType Device | Select-Object -ExpandProperty Name) -ErrorAction Stop
            }
        catch [System.SystemException] {
            Write-Warning -Message $_.Exception.Message
        }
    }
}
