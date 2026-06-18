 [CmdletBinding()]
param (
    # Parameter help description
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    $LogsDirectory = (Join-Path -Path $env:SystemRoot -ChildPath "Logs"),

    # Parameter help description
    [Parameter(Mandatory=$false)]
    [ValidateNotNullOrEmpty()]
    $LogName = "ContentValidation.log"
)
Begin {
    function Write-CMLogEntry {
        param (
            [parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
            [ValidateNotNullOrEmpty()]
            [string]$Value,
            [parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
            [ValidateNotNullOrEmpty()]
            [ValidateSet("1", "2", "3")]
            [string]$Severity,
            [parameter(Mandatory = $false, HelpMessage = "Name of the log file that the entry will written to.")]
            [ValidateNotNullOrEmpty()]
            [string]$FileName = $LogName
        )
        # Determine log file location
        $LogFilePath = Join-Path -Path $LogsDirectory -ChildPath $FileName
		
        # Construct time stamp for log entry
        $Time = -join @((Get-Date -Format "HH:mm:ss.fff"), "+", (Get-WmiObject -Class Win32_TimeZone | Select-Object -ExpandProperty Bias))
		
        # Construct date for log entry
        $Date = (Get-Date -Format "MM-dd-yyyy")
		
        # Construct context for log entry
        $Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
        # Construct final log entry
        $LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""ClientHealthUpdate"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
        # Add value to log file
        try {
            Add-Content -Value $LogText -LiteralPath $LogFilePath -ErrorAction Stop
        }
        catch [System.Exception] {
            Write-Warning -Message "Unable to append log entry to $($LogName) file. Error message: $($_.Exception.Message)"
        }
    }

}
Process {
    # Variables
    [int]$PkgIDCount = 4
    [int]$Validation = 0 # Do not modify

    # Check log existence
    if ((Test-Path "$env:windir\CCM\Logs\CCMSDKProvider.log") -and (Get-WmiObject -Class CCM_SoftwareDistribution -Namespace "root/ccm/policy/machine/actualconfig" | Where-Object { ($_.TS_Type) })) {
        # Create placeholder array
        $PkgID = New-Object -TypeName System.Collections.ArrayList
        # Manually add UpgradePkgId
        Get-WmiObject -Class CCM_SoftwareDistribution -Namespace "root/ccm/policy/machine/actualconfig" | Where-Object { ($_.PKG_Name -notmatch "Driver Pack") -and (!$_.TS_Type) -and ($_.PRG_ProgramName -eq "*") } | ForEach-Object {
            [void]$PkgID.Add($_.PKG_PackageID)
        }
        # Parse log file and lookup downloaded packages
        Get-Content "$env:windir\CCM\Logs\CCMSDKProvider.log" | Select-String -Pattern "Will Pre-download source files because condition" | ForEach-Object -Process {
            # Strip unneccessary log content and add to array
            [void]$PkgID.Add([regex]::match($_, '(\s)(?<PkgID>PS1[A-Z0-9]{5})').Groups['PkgID'].Value)
        }
        if ($PkgID.Count -gt $PkgIDCount) {
            Write-Host "Found $(($PkgID | Sort-Object -Unique | Measure-Object).Count) PkgID(s)."
            Write-CMLogEntry -Value "Found $(($PkgID | Sort-Object -Unique | Measure-Object).Count) PkgID(s)." -Severity 1
        }
        elseif ($PkgID.Count -ge $PkgIDCount) {
            Write-Host "Found $(($PkgID | Sort-Object -Unique | Measure-Object).Count) PkgID(s). Expected more than $PkgIDCount."
            Write-CMLogEntry -Value "Found $(($PkgID | Sort-Object -Unique | Measure-Object).Count) PkgID(s). Expected more than $PkgIDCount." -Severity 2
        }
        else {
            Write-Host "Found insufficient PkgIDs, expected at least $PkgIDCount. Terminating validation script."
            Write-CMLogEntry -Value "Found insufficient PkgIDs, expected at least $PkgIDCount. Terminating validation script." -Severity 3
            exit 1
        }
    }
    else {
        Write-Host "Failed to find log file or TS is not deployed to client."
        Write-CMLogEntry -Value "Failed to find log file or TS is not deployed to client." -Severity 3
        exit 1
    }

    # Run content download path parser for each item in PkgID array
    foreach ($ID in ($PkgID | Sort-Object -Unique)) {
        # Create CM object
        $CMObject = New-Object -ComObject 'UIResource.UIResourceMgr'
        $CMCacheObjects = $CMObject.GetCacheInfo()
        $OSUpgradeContent = $CMCacheObjects.GetCacheElements() | Where-Object { $_.ContentID -eq "$ID" }
        if (![string]::IsNullOrEmpty($OSUpgradeContent)) {
            $ContentVersion = $OSUpgradeContent.ContentVersion
            $HighestContentID = $ContentVersion | Measure-Object -Maximum
            $NewestContent = $OSUpgradeContent | Where-Object { $_.ContentVersion -eq $HighestContentID.Maximum }
            $PackageName = Get-WmiObject -Class CCM_Program -Namespace "root\ccm\clientsdk" | Where-Object { $_.PackageID -eq $ID} | Select-Object -ExpandProperty PackageName
            [int]$ContentSize = $NewestContent.ContentSize
            [int]$ActualSize = ([math]::Round(($NewestContent.Location | Get-ChildItem -Recurse | Measure-Object -Property Length -Sum).Sum / 1Kb))

            #Write-Host "Found content path $($NewestContent.Location) for PkgID $ID."
            Write-CMLogEntry -Value "Found content path $($NewestContent.Location) for PkgID $ID." -Severity 1
            # Validate content directory size
            if ( $ActualSize - $ContentSize -eq 0 ) {
                #Write-Host "Content vaildation for $PackageName ($ID) succeeded."
                Write-CMLogEntry -Value "Content vaildation for $PackageName ($ID) succeeded." -Severity 1
                $Validation = $Validation + 1
            }
            elseif ( ($ActualSize - $ContentSize -replace "-", "") -le 10 ) {
                #Write-Host "Content vaildation for $PackageName ($ID) succeeded. Expected $ContentSize, received $ActualSize."
                Write-CMLogEntry -Value "Content vaildation for $PackageName ($ID) succeeded. Expected $ContentSize, received $ActualSize." -Severity 2
                $Validation = $Validation + 1
            }
            else {
                Write-Host "Failed to verify content in $PackageName ($ID). Expected $ContentSize, received $ActualSize."
                Write-CMLogEntry -Value "Failed to verify content in $PackageName ($ID). Expected $ContentSize, received $ActualSize." -Severity 3
                $Validation = $Validation - 1
            }
        }
        else {
            Write-Host "Failed to identify content for PkgID $ID. Expected content is not yet downloaded."
            Write-CMLogEntry -Value "Failed to identify content for PkgID $ID. Expected content is not yet downloaded." -Severity 3
            $Validation = $Validation - 1
        }
    }

    if ($Validation -ge ($PkgID | Sort-Object -Unique | Measure-Object).Count) {
        Write-Host "--- Content validation succeeded. OS upgrade approved. Log location $LogsDirectory."
        Write-CMLogEntry -Value "--- Content validation succeeded. OS upgrade approved." -Severity 1
        exit 0
    }
    else {
        Write-Host "--- Content validation failed. OS upgrade denied. Log location $LogsDirectory."
        Write-CMLogEntry -Value "--- Content validation failed. OS upgrade denied." -Severity 3
        exit 1
    }
} 
