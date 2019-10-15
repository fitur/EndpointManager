# Functions 
function Get-MSIInfo {
    [CmdletBinding()]
    param (
        # Parameter help description
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( { Test-Path -Path $_ } )]
        [System.IO.FileInfo]$File,
 
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateSet("ProductCode", "ProductVersion", "ProductName", "Manufacturer", "ProductLanguage", "FullVersion")]
        [string]$Property
    )
    
    process {
        try {
            # Read property from MSI database
            $WindowsInstaller = New-Object -ComObject WindowsInstaller.Installer
            $MSIDatabase = $WindowsInstaller.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $WindowsInstaller, @($File.FullName, 0))
            $Query = "SELECT Value FROM Property WHERE Property = '$($Property)'"
            $View = $MSIDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $MSIDatabase, ($Query))
            $View.GetType().InvokeMember("Execute", "InvokeMethod", $null, $View, $null)
            $Record = $View.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $View, $null)
            $Value = $Record.GetType().InvokeMember("StringData", "GetProperty", $null, $Record, 1)
     
            # Commit database and close view
            $MSIDatabase.GetType().InvokeMember("Commit", "InvokeMethod", $null, $MSIDatabase, $null)
            $View.GetType().InvokeMember("Close", "InvokeMethod", $null, $View, $null)           
            $MSIDatabase = $null
            $View = $null
     
            # Return the value
            return $Value
        } 
        catch {
            Write-Warning -Message $_.Exception.Message ; break
        }
    }
    end {
        # Run garbage collection and release ComObject
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WindowsInstaller) | Out-Null
        [System.GC]::Collect()
    }
}

function Get-LatestChromeVersion {
    param (
        [string]$OS = 'win64',
        [string]$Channel = 'stable',
        [string]$VersionURI = 'https://omahaproxy.appspot.com/all.json'
    )
    
    process {
        $Content = (Invoke-RestMethod -Uri $VersionURI -Method Get -ErrorAction Stop) | Where-Object { ($_.os -eq $OS) } | Select-Object -ExpandProperty versions | Where-Object { $_.channel -eq $Channel }
    }

    end {
        return $Content
    }
}

function Get-LatestChrome {
    [CmdletBinding()]
    param (
        # Path to download file
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript( { Test-Path -Path $_ } )]
        [string]$Destination = $env:TEMP,
        [string]$DownloadURI = 'https://dl.google.com/tag/s/dl/chrome/install/googlechromestandaloneenterprise64.msi',
        $LatestChromeVersion = (Get-LatestChromeVersion)
    )
    
    begin {
        try {
            # Create placeholder for download path including file name
            [System.IO.FileInfo]$DownloadPath = ('{0}\{1}' -f $(Get-Item -Path $Destination | Select-Object -ExpandProperty FullName), $($DownloadURI | Split-Path -Leaf))
        }
        catch [System.Exception] {
            Write-Warning  -Message $_.Exception.Message
        }
    }
    
    process {
        try {
            if ((Invoke-WebRequest -Uri $DownloadURI -OutFile $DownloadPath -PassThru -ErrorAction Stop | Select-Object -ExpandProperty StatusDescription) -eq "OK") {
                $ChromeInfo = [PSCustomObject]@{
                    Name         = [string](Get-MSIInfo -File $(Get-Item -Path $DownloadPath -ErrorAction Stop) -Property ProductName | Select-Object -First 1)
                    Manufacturer = [string](Get-MSIInfo -File $(Get-Item -Path $DownloadPath -ErrorAction Stop) -Property Manufacturer | Select-Object -First 1)
                    ProductCode = [string](Get-MSIInfo -File $(Get-Item -Path $DownloadPath -ErrorAction Stop) -Property ProductCode | Select-Object -First 1)
                    File         = (Get-Item -Path $DownloadPath -ErrorAction Stop)
                    Version      = $LatestChromeVersion.version
                    ReleaseDate  = (Get-Date ([System.DateTime]::ParseExact(($LatestChromeVersion.current_reldate), "dd/MM/yy", $null)) -Format d -ErrorAction Stop)
                }
            }
        }
        catch [System.Exception] {
            Write-Warning  -Message $_.Exception.Message
        }
    }
    
    end {
        return $ChromeInfo
    }
}

function Invoke-BuildChrome {
    [CmdletBinding()]
    param (
    # Source path of PSADT reference
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript( { Test-Path -Path $_ } )]
    [string]$SourcePath,

    # Where to put finished PSADT project
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [ValidateScript( { Test-Path -Path $_ } )]
    [string]$DestinationPath,

    # Get latest Chrome version information to avoid mismatch in MSI
    $LatestChromeVersion = (Get-LatestChromeVersion)
)

    begin {
        $ProjectInfo = Get-LatestChrome -ErrorAction SilentlyContinue
    }
    
    process {
        # Create project directory in destination path
        try {
            $TemporaryDestinationPath = New-Item -Path (Get-Item -Path $DestinationPath -ErrorAction Stop) -Name ("{0} {1}" -f $ProjectInfo.Name, $ProjectInfo.Version) -ItemType Directory -Force
        }
        catch [System.Exception] {
            Write-Warning  -Message $_.Exception.Message
        }

        # Copy PSADT template to destination path
        try {
            $TemporarySourcePath = (Get-ChildItem -Path $SourcePath | Where-Object {$_.Name -eq $ProjectInfo.Name}).FullName
            Copy-Item -Path "$TemporarySourcePath\*" -Destination $TemporaryDestinationPath -Recurse -Verbose
        }
        catch [System.Exception] {
            Write-Warning  -Message $_.Exception.Message
        }
        
    }
    
    end {
        
    }
}
# Script


Invoke-BuildChrome -SourcePath "C:\Users\peola001\Downloads\WPPaketering\Source" -DestinationPath "C:\Users\peola001\Downloads\WPPaketering\Packages"
