# Variables
$Rating = 3.5 # Minimum rating
$Address = "Fredsborgsgatan 24, Liljeholmen" -replace " ","+" # Address of starting point
$Radius = 1000 # Meters
$Random = 5 # Random objects
$PollText = '/poll "Vart käkar vi idag?"' # Poll text
$TransportType = "walking" # walking, driving
$GoogleMaps_API_Key = "AIzaSyDj7Uy8ApUV6wVZGCKdQ8gH1rUfOCSq_XE"

# Gather from Google Maps
$Location = (Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/geocode/json?address=$($Address)&key=$($GoogleMaps_API_Key)").results | Select-Object -First 1
$Coordinates = "{0},{1}" -f (($Location.geometry.location.lat -replace ",","."), ($Location.geometry.location.lng -replace ",","."))
$Nearby = (Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$($Coordinates)&radius=$($Radius)&types=restaurant&opennow&key=$($GoogleMaps_API_Key)").Results

# Placeholders
$Places = New-Object -TypeName System.Collections.ArrayList

# Add objects into detailed array
if (($Nearby | Measure-Object).Count -gt 0) {
    foreach ($Object in $Nearby) {
        $Places.Add((Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/place/details/json?place_id=$($Object.place_id)&fields=&key=$($GoogleMaps_API_Key)").result) | Out-Null
    }
}

# Filter detailed array and select $number random objects
$Places | Where-Object {
    ($_.opening_hours.periods[$((Get-Date).DayOfWeek.value__)].open.time).SubString(0,2) -le (Get-Date).AddMinutes(30).Hour -and
    ($_.opening_hours.periods[$((Get-Date).DayOfWeek.value__)].close.time).SubString(0,2) -gt (Get-Date).AddMinutes(30).Hour -and
    ($_.rating -ge $Rating)
} | Get-Random -Count $Random | ForEach-Object -Process {
    $_ | Add-Member -MemberType NoteProperty -Name "distance" -Value (Invoke-RestMethod -Method Get -Uri "https://maps.googleapis.com/maps/api/distancematrix/json?origins=$($Coordinates)&destinations=$($_.formatted_address -replace " ","+")&mode=$($TransportType)&units=metric&key=$($GoogleMaps_API_Key)")
    $PollText = $PollText + (' "{0} - Rating: {1} - Avstånd: {2} (URL: {3})"' -f $_.Name, $_.Rating, $_.distance.rows.elements.distance.text, $_.Website)
}

# Set poll to clipboard
$PollText | Set-Clipboard
