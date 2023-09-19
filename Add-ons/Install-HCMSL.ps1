try {
    Import-Module -Name HPCMSL -ErrorAction Stop
}
catch {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $URL = "https://www.hp.com/us-en/solutions/client-management-solutions/download.html"
    $WebRequest = Invoke-WebRequest -Uri $URL -UseBasicParsing
    $Link = $WebRequest.Links | Where-Object {$_.href -match "hp-cmsl"}
    Invoke-WebRequest -Uri $Link.href -OutFile (Join-Path -Path $env:TEMP -ChildPath ($Link.href | Split-Path -Leaf))
    Start-Process -FilePath (Join-Path -Path $env:TEMP -ChildPath ($Link.href | Split-Path -Leaf)) -ArgumentList "/VERYSILENT /NORESTART" -Wait
    Import-Module -Name HPCMSL -ErrorAction Stop
}

Set-HPBIOSSettingValue -Name "Secure Boot" -Value "Enable"
