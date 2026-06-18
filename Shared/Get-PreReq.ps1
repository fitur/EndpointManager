# Evaluate power state
if ($(Get-WmiObject -Class Win32_ComputerSystem -Property PCSystemType | Select-Object -ExpandProperty PCSystemType) -ne 1) { 
    if ($(Get-WmiObject -Class BatteryStatus -Namespace root\wmi | Select-Object -ExpandProperty PowerOnline) -eq $true) {
        return $true
    }
    else {
        return $false
    }
}

# Evaluate user Activity
$Template = @'
 USERNAME              SESSIONNAME        ID  STATE   IDLE TIME  LOGON TIME
>{USER*:abc}                 console             1  {STATE:Active}    {IDLE:1+00:27}  24-08-2015 22:22
 {USER*:test}                                      2  {STATE:Disc}      {IDLE:none}  25-08-2015 08:26
'@

$ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo 
$ProcessInfo.FileName = "query.exe"
$ProcessInfo.RedirectStandardError = $true 
$ProcessInfo.RedirectStandardOutput = $true 
$ProcessInfo.UseShellExecute = $False 
$ProcessInfo.Arguments = "user"
$ProcessInfo.CreateNoWindow = $False
$Process = New-Object System.Diagnostics.Process 
$Process.StartInfo = $ProcessInfo
$Process.Start() | Out-Null
$Process.WaitForExit()
$Query = $Process.StandardOutput.ReadToEnd()

try {
    $Users = $Query | ConvertFrom-String -TemplateContent $Template -ErrorAction Stop
}
catch [System.Exception] {
    $null
}

$AUsers = $Users | Where-Object {$_.State -eq "Active"}
$DUsers = $Users | Where-Object {$_.State -eq "Disc"}

if ($null -eq $Users) {
    return 0
}
elseif (($AUsers | Measure-Object).Count -gt 0) {
    return 1
}
elseif ((($DUsers | Measure-Object).Count -gt 0) -and (($AUsers | Measure-Object).Count -lt 1)) {
    return 2
}

# Evaluate exit code
$tsenv = New-Object -ComObject Microsoft.SMS.TSEnvironment
$LogPath = $tsenv.Value("_SMSTSLogPath")

try {
    $BIOSUpdateLogPath = Get-ChildItem -Path $LogPath -Filter "Invoke-*BIOSUpdate.log" -ErrorAction Stop
}
catch [System.Exception] {
    Write-Host "Could not find BIOS update log at $LogPath"
}
if ((Get-Content $BIOSUpdateLogPath.FullName | Select-String "Flash utility exit code:" | Select-Object -Last 1) -match "(?<exitcode>\d{3,4})(\])") {
    return $Matches.exitcode
}
else {
    return 0
}
