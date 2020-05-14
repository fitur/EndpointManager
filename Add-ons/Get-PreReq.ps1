# Evaluate power state
if ($(Get-WmiObject -Class Win32_ComputerSystem -Property PCSystemType | Select-Object -ExpandProperty PCSystemType) -ne 1) { 
    if ($(Get-WmiObject -Class BatteryStatus -Namespace root\wmi | Select-Object -ExpandProperty PowerOnline) -eq $true) {
        return $true
    }
    else {
        return $false
    }
}
