$Servername = "ne-as-prn01"
$Array = New-Object -TypeName System.Collections.ArrayList

Get-WinEvent Microsoft-Windows-PrintService/Operational -ComputerName $Servername | Where-Object {($_.Id -eq 307) -and ($_.TimeCreated -gt (Get-Date).AddDays(-31))} | ForEach-Object {
    [void]$Array.Add(($_.Message -split " owned by " -split " on ")[1])
}

$Array | Select-Object -Unique | Measure-Object | Select-Object -ExpandProperty Count 
