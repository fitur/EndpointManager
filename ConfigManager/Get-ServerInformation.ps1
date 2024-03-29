$ComputerName = "TIMMLMSCCM002.timra.se"
$InfoArray = New-Object System.Collections.ArrayList

$OSInfo = Get-WmiObject Win32_OperatingSystem -ComputerName $ComputerName
$CPUInfo = Get-WmiObject Win32_Processor -ComputerName $ComputerName
$DiskInfo = Get-WmiObject Win32_LogicalDisk -ComputerName $ComputerName

# Hämta diskinformation
$DiskInfo | Where-Object {$_.MediaType -eq 12} | Select-Object -Property Name, VolumeName, Size, FreeSpace | ForEach-Object -Process {
    $temp = [PSCustomObject]@{
        Type = "Disk"
        Name = "$($_.VolumeName) ($($_.Name))"
        Size = "$([math]::round($_.Size /1Gb, 1)) Gb"
        Free = "$([math]::round($_.FreeSpace /1Gb, 1)) Gb"
        Percent = "$([math]::round(($_.FreeSpace / $_.Size *100), 1))%"
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
    Name = "$($CPUInfo | Select-Object -First 1 -ExpandProperty Name) ($($CPUInfo | Measure-Object -Sum NumberOfCores | Select-Object -ExpandProperty Sum) kärnor)"
}
[void]$InfoArray.Add($temp)
