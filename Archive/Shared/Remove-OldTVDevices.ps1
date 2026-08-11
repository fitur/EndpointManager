# Provide your TeamViewer API token via the TEAMVIEWER_API_TOKEN environment variable.
# Never hardcode API tokens in scripts that are committed to source control.
$token = $env:TEAMVIEWER_API_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "TeamViewer API token not found. Set the TEAMVIEWER_API_TOKEN environment variable before running this script."
}
$bearer = "Bearer $token"

$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$header.Add("authorization", $bearer)

$devices = (Invoke-RestMethod -Uri "Https://webapi.teamviewer.com/api/v1/devices" -Method Get -Headers $header).devices

$30Days = $(((Get-Date).AddDays(-30)).GetDateTimeFormats()[34]+"Z") # Exempel 2022-04-05T13:46:06Z

ForEach($device in $devices)
{

    if ($device.online_state -eq "Offline")
    {

    $ID = $device.device_id

    $Lastseen = $device.last_seen

            if ($Lastseen -ne $null)
            {

            $LastSeen = ($device.last_seen).Split("T")[0]
            [datetime]$DateLastSeen = $LastSeen

                    if ($DateLastSeen -le $30Days)
                    {

                    Invoke-WebRequest -Uri "Https://webapi.teamviewer.com/api/v1/devices/$ID" -Method Delete -Headers $header
                    Write-Host "Deleted device:"$device.alias -ForegroundColor Yellow

                    }$Lastseen = $null
            }
    }
}