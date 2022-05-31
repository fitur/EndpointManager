# Hämta boundary-information
Get-CMBoundary | ForEach-Object -Begin {$CMBoundaries = New-Object -TypeName System.Collections.ArrayList} -Process {
    $temp = [PSCustomObject]@{
        Name = $_.Value
        Description = $_.DisplayName
        Type = $_.BoundaryType
        SiteCode = $_ | Select-Object -ExpandProperty DefaultSiteCode
        SiteSystem = $_ | Select-Object -ExpandProperty SiteSystems
        Groups = $_.GroupCount
    }
    [void]$CMBoundaries.Add($temp)
} 
