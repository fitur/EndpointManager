$URI = "https://endpoints.office.com/endpoints/worldwide?clientrequestid=b10c5ed1-bad1-445f-b386-b919946339a7"
$Content = Invoke-RestMethod -Uri $URI -Method Get

$GpoName = "(DEV)-Windows10-IE11-ZoneAssignmentList"
$GPO = Get-GPO -Name $GpoName
$XMLBackup = "C:\Kim\{C34F5145-A456-42C7-9DA0-920A8927B228}\gpreport.xml"

[xml]$XML = Get-Content -Path $XMLBackup


$Content | Where-Object { $_.required -eq $true } | ForEach-Object {
    foreach ($URL in $_.urls) {
        if ($URL -notin ($XML.GPO.Computer.ExtensionData.Extension.Policy.ListBox.Value.Element.Name)) {
            $temp = $XML.GPO.Computer.ExtensionData.Extension.Policy.ListBox.Value.Element[0].Clone()
            $temp.Name = $URL
            $temp.Data = [string]2
            $XML.GPO.Computer.ExtensionData.Extension.Policy.ListBox.Value.AppendChild($temp)
        }
        else {
            Write-Output "$URL already in list"
        }
    }
}

$XML.Save($XMLBackup)