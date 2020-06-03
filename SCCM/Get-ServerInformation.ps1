$ComputerName = "TIMMLMSCCM002.timra.se"
$InfoArray = New-Object System.Collections.ArrayList

$OSInfo = Get-WmiObject Win32_OperatingSystem -ComputerName $ComputerName
$CPUInfo = Get-WmiObject Win32_Processor -ComputerName $ComputerName
$DiskInfo = Get-WmiObject Win32_LogicalDisk -ComputerName $ComputerName

# Hämta diskinformation
$DiskInfo | Where-Object {$_.MediaType -eq 12} | Select-Object -Property Name, VolumeName, Size | ForEach-Object -Process {
    $temp = [PSCustomObject]@{
        Type = "Disk"
        Name = "$($_.VolumeName) ($($_.Name))"
        Size = "$([math]::round($_.Size /1Gb, 1)) Gb"
    }
    [void]$InfoArray.Add($temp)
}

# Hämta OS-information
$OSInfo | ForEach-Object {
    $temp = [PSCustomObject]@{
        Type = "OS"
        Name = $OSInfo.Caption
    }
    [void]$InfoArray.Add($temp)
}

# Hämta minnesinformation
$OSInfo | ForEach-Object {
    $temp = [PSCustomObject]@{
        Type = "Memory"
        Size = "$([System.Math]::Round($OSInfo.TotalVisibleMemorySize / 1Mb, 1)) Gb"
    }
    [void]$InfoArray.Add($temp)
}

# Hämta processorinformation
$temp = [PSCustomObject]@{
    Type = "CPU"
    Name = "$($CPUInfo | Select-Object -First 1 -ExpandProperty Name) ($($CPUInfo | Measure-Object | Select-Object -ExpandProperty Count) kärnor)"
}
[void]$InfoArray.Add($temp)
