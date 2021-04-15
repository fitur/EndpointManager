param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $RepoDir,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    $LogsDir,
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $UpdateType = "Live",
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    $PWBin = (Get-ChildItem -Filter *.bin | Select-Object -ExpandProperty FullName)
)
begin {
    # Create variables
    $HPModel = Get-CimInstance -Namespace root\wmi -ClassName MS_SystemInformation -ErrorAction Stop | Select-Object -ExpandProperty SystemProductName
    $OSBuild = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop | Select-Object -ExpandProperty Version
    $FullLogPath = Join-Path -Path $LogsDir -ChildPath $env:COMPUTERNAME

    # Create HPIA argument string
    if ($null -eq $PWBin) {
        $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All'
    }
    else {
        $ArgumentString = '/Operation:Analyze /Action:Install /Selection:All /BIOSPwdFile:"{0}"' -f $PWBin
    }

    # Switch for UpdateType (background or interactive)
    switch ($UpdateType) {
        "Live" { $ArgumentString = ($ArgumentString + ' /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath) }
        "Background" { $ArgumentString = ' /Silent /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "Online" { $ArgumentString = ' /noninteractive /ReportFolder:"{0}"' -f $FullLogPath }
        "DriversOnly" { $ArgumentString = ' /Category:Drivers,Software /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
        "BIOSOnly" { $ArgumentString = ' /Category:BIOS,Firmware /noninteractive /Offlinemode:"{0}" /ReportFolder:"{1}"' -f $RepoDir, $FullLogPath }
    }
}
process {
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
