$LogName = "Microsoft-Windows-PrintService/Operational"
$LogPath = "\\ne\system\SCCM\Logs\PrintAudit"

Get-WinEvent -ListLog $LogName -OutVariable PrinterLogSettings | Select-Object -Property LogName, IsClassicLog, IsEnabled
if ($PrinterLogSettings.IsEnabled -ne $true) {
    $PrinterLogSettings.set_IsEnabled($true)
    $PrinterLogSettings.SaveChanges()
}

$LogPathAbsolute = New-Item -Path (Join-Path -Path $LogPath -ChildPath $env:COMPUTERNAME) -ItemType Directory -Force -ErrorAction SilentlyContinue

Get-WinEvent -FilterHashTable @{LogName=$LogName; ID=307; StartTime=(Get-Date -OutVariable Now).AddDays(-1)} |
Select-Object -Property TimeCreated,
@{label='UserName';expression={$_.properties[2].value}},
@{label='ComputerName';expression={$_.properties[3].value}},
@{label='PrinterName';expression={$_.properties[4].value}},
@{label='PrintSize';expression={$_.properties[6].value}},
@{label='Pages';expression={$_.properties[7].value}} |
Export-Csv -Path (Join-Path -Path $LogPathAbsolute -ChildPath ("Printing Audit - {0} - $($($Now).ToString('yyyy-MM-dd')).csv" -f $env:COMPUTERNAME)) -NoTypeInformation 
