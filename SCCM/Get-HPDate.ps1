$CMCollection = Get-CMCollection -Id PS10037C -CollectionType Device

Get-CMDevice -CollectionID $CMCollection.CollectionID | ForEach-Object -Begin {
    $SNList = New-Object -TypeName System.Collections.ArrayList
} -Process {
    $Query = "select SMS_G_System_PC_BIOS.SerialNumber from SMS_R_System inner join SMS_G_System_PC_BIOS on SMS_G_System_PC_BIOS.ResourceID = SMS_R_System.ResourceId where Name = ""$($_.Name)"""
    $Regex = "(?<start>\w{3})(?<date>\d{3})(?<end>\w{4})"
    $SCCMData = Get-WmiObject -ComputerName $SiteCode.SiteServer -Namespace "root\SMS\site_$($SiteCode)" -Query $Query -ErrorAction Stop

    $Date = $SCCMData.SerialNumber -replace $Regex, '$2'
    [int]$Year = "201{0}" -f $Date.Substring(0, 1)
    [int]$Week = $Date.Substring(1, 2)
    $Jan1 = [DateTime]"$Year-01-01"
    $DaysOffset = ([DayOfWeek]::Thursday - $Jan1.DayOfWeek)
    $FirstThursday = $Jan1.AddDays($DaysOffset)
    $Calendar = ([CultureInfo]::CurrentCulture).Calendar
    $FirstWeek = $Calendar.GetWeekOfYear($FirstThursday, [System.Globalization.CalendarWeekRule]::FirstFourDayWeek, [DayOfWeek]::Monday)
    $WeekNum = $Week
    if ($FirstWeek -le 1) { $WeekNum -= 1 }
    $FullDate = $FirstThursday.AddDays($WeekNum * 7)
    [void]$SNList.Add(($FullDate.ToShortDateString()))
} -End {
    return "{0} - {1} - {2}" -f ($SNList | Measure-Object -Minimum).Minimum, ($SNList | Select-Object -Index ([math]::round(($SNList.Count / 2)))), ($SNList | Measure-Object -Maximum).Maximum
}