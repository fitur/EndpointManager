param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $RepoDir,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $LogsDir,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $UpdateType = "Live"
)
begin {
    # Create variables
    $HPModel = Get-CimInstance -Namespace root\wmi -ClassName MS_SystemInformation -ErrorAction Stop | Select-Object -ExpandProperty SystemProductName
    $OSBuild = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -ExpandProperty Version
    $FullLogPath = Join-Path -Path $LogsDir -ChildPath $env:COMPUTERNAME

    # Switch for UpdateType (background or interactive)
    switch ($UpdateType) {
        "Live" { $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /noninteractive /Offlinemode:"{0}" /BIOSPwdFile:solnapw.bin /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "Background" { $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /Silent /Offlinemode:"{0}" /BIOSPwdFile:solnapw.bin /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }

        "Online" { $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /noninteractive /BIOSPwdFile:solnapw.bin /ReportFolder:"{0}"' -f $FullLogPath }
        "Certify" {
            $Certify = $true
            $CertifyPath = Join-Path -Path $RepoDir -ChildPath $HPModel
            $FullLogPath = Join-Path -Path $CertifyPath -ChildPath $env:COMPUTERNAME
            $ArgumentString = '/Operation:Analyze /Action:Download /Selection:All /noninteractive /softpaqdownloadfolder:"{0}" /ReportFolder:"{1}"' -f $CertifyPath, $FullLogPath
        }

        "DriversOnly" { $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /Category:Drivers,Software /noninteractive /Offlinemode:"{0}" /BIOSPwdFile:solnapw.bin /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "BIOSOnly" { $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /Category:BIOS,Firmware /noninteractive /Offlinemode:"{0}" /BIOSPwdFile:solnapw.bin /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
    }
}
process {
    if ($Certify -eq $true) {
        # Create model root directory if not present
        if (!(Test-Path -Path $CertifyPath)) {
            try {
                New-Item -Path $CertifyPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            }
            catch [System.SystemException] {
                Write-Verbose -Verbose "Error - Could not create repo dir $($CertifyPath)."
            }
        }

        # Run HP Image Assistant
        try {
            Start-Process '.\HPImageAssistant.exe' -ArgumentList $ArgumentString -Wait -ErrorAction Stop
        }
        catch [System.SystemException] {
            Write-Verbose -Verbose "Error - Could not run HPIA."
        }
    } else {
        if (Test-Path -Path $RepoDir) {
            # Run HP Image Assistant
            try {
                Start-Process '.\HPImageAssistant.exe' -ArgumentList $ArgumentString -Wait -ErrorAction Stop
                exit 0;
            }
            catch [System.SystemException] {
                Write-Verbose -Verbose "Error - Could not run HPIA."
                exit 1;
            }
        } else {
            Write-Verbose -Verbose "Error - Directory $($RepoDir) not available."
            exit 2;
        }
    }
}
