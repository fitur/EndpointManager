# Variables
$Rating = 3.5 # Minimum rating
$Address = "Fredsborgsgatan 24, Liljeholmen" -replace " ", "+" # Address of starting point
$Radius = 1000 # Meters radius
$Random = 5 # Number of random objects to add to poll
$PollText = '/poll "Vart käkar vi på fredag?"' # Poll text
$TransportType = "walking" # walking, driving
$GoogleMaps_API_Key = $env:GoogleAPI # Google Maps API key
$LunchHour = 11 # Hour to start lunch
$DayOfWeek = (Get-Date).DayOfWeek.value__ # Set to 5 if not run on friday

# Gather from Google Maps
$Location = (Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/geocode/json?address=$($Address)&key=$($GoogleMaps_API_Key)").Results | Select-Object -First 1
$Coordinates = "{0},{1}" -f (($Location.geometry.location.lat -replace ",", "."), ($Location.geometry.location.lng -replace ",", "."))
$Nearby = (Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$($Coordinates)&radius=$($Radius)&types=restaurant&key=$($GoogleMaps_API_Key)").Results

# Placeholders
$Places = New-Object -TypeName System.Collections.ArrayList

# Add objects into detailed array
if (($Nearby | Measure-Object).Count -gt 0) {
    foreach ($Object in $Nearby) {
        $Places.Add((Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/place/details/json?place_id=$($Object.place_id)&fields=&key=$($GoogleMaps_API_Key)").result) | Out-Null
    }
}

# Remove places without opening_hours
$Places | Where-Object { (!$_.opening_hours.periods[$($DayOfWeek)].open.time) } | ForEach-Object { $Places.Remove($_) | Out-Null }

# Filter detailed array and select $number random objects
$Places | Where-Object {
    ($_.opening_hours.periods[$($DayOfWeek)].open.time).SubString(0, 2) -le $LunchHour -and # Opening hours before $LunchHour
    ($_.opening_hours.periods[$($DayOfWeek)].close.time).SubString(0, 2) -gt $($LunchHour + 2) -and # Opening hours after $LunchHour + 2 hours
    ($_.rating -ge $Rating) # Rating equal to or above $Rating
} | Get-Random -Count $Random | ForEach-Object -Process {
    $_ | Add-Member -MemberType NoteProperty -Name "distance" -Value (Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/distancematrix/json?origins=$($Coordinates)&destinations=$($_.formatted_address -replace " ","+")&mode=$($TransportType)&units=metric&key=$($GoogleMaps_API_Key)")
    $PollText = $PollText + (' "{0} - Rating: {1} - Avstånd: {2} (URL: {3}) - Öppettider: {4} - {5}"' -f $_.Name, $_.Rating, $_.distance.rows.elements.distance.text, $_.Website, ($_.opening_hours.periods[$((Get-Date).DayOfWeek.value__)].open.time).SubString(0, 2), ($_.opening_hours.periods[$((Get-Date).DayOfWeek.value__)].close.time).SubString(0, 2))
}

# Set poll to clipboard to paste into Slack
$PollText | Set-Clipboard