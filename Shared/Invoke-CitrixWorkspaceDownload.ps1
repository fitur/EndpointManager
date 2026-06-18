$URI = "https://www.citrix.com/downloads/workspace-app/windows/workspace-app-for-windows-latest.html"
$WR = Invoke-WebRequest -Uri $URI -UseBasicParsing
$DownloadLink = "https://{0}" -f ($WR.Links | Where-Object {($_.outerHTML -match "CitrixWorkspaceApp.exe")} | Select-Object -ExpandProperty rel).SubString(2)
Invoke-WebRequest -Uri $DownloadLink -OutFile (Join-Path -Path $env:TEMP -ChildPath "CitrixWorkspaceApp.exe") -UseBasicParsing
$Installer = Get-Item -Path (Join-Path -Path $env:TEMP -ChildPath "CitrixWorkspaceApp.exe")
