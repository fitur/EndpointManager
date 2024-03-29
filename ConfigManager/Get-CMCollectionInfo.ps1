# Load CM module
Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') 
$SiteCode = Get-PSDrive -PSProvider CMSITE 
Set-location $SiteCode":"

# Create empty array list
$Collections = New-Object -TypeName System.Collections.ArrayList

Get-CMCollection | Where-Object {$_.CollectionID -notlike "SMS*"} | ForEach-Object {

    # Create new temporary PS object
    $temp = New-Object -TypeName PSCustomObject

    # Evaluate collection Name, ID, etc.
    $temp | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.Name
    $temp | Add-Member -MemberType NoteProperty -Name "CollectionID" -Value $_.CollectionID
    $temp | Add-Member -MemberType NoteProperty -Name "Comment" -Value $_.Comment
    $temp | Add-Member -MemberType NoteProperty -Name "LastRefreshTime" -Value $_.LastRefreshTime
    $temp | Add-Member -MemberType NoteProperty -Name "MemberCount" -Value $_.MemberCount
    $temp | Add-Member -MemberType NoteProperty -Name "LimitToCollectionName" -Value "$($_.LimitToCollectionName) ($($_.LimitToCollectionID))"
    $temp | Add-Member -MemberType NoteProperty -Name "CollectionRules" -Value ($_.CollectionRules | Measure-Object).Count
    $temp | Add-Member -MemberType NoteProperty -Name "ObjectPath" -Value (Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -Query "select ObjectPath from SMS_Collection where CollectionID = '$($_.CollectionID)'" -ComputerName $SiteCode.SiteServer | Select-Object -ExpandProperty ObjectPath)

    # Evaluate device or user collection
    switch ($_.CollectionType) {
        1 {
            $temp | Add-Member -MemberType NoteProperty -Name "CollectionType" -Value "User Collection"
        }
        2 {
            $temp | Add-Member -MemberType NoteProperty -Name "CollectionType" -Value "Device Collection"
        }
    }

    # Evaluate refresh types
    switch ($_.RefreshType) {
        1 {
            $temp | Add-Member -MemberType NoteProperty -Name "RefreshType" -Value "Manual"
        }
        2 {
            $temp | Add-Member -MemberType NoteProperty -Name "RefreshType" -Value "Periodic"
        }
        4 {
            $temp | Add-Member -MemberType NoteProperty -Name "RefreshType" -Value "Incremental"
        }
        6 {
            $temp | Add-Member -MemberType NoteProperty -Name "RefreshType" -Value "Both"
        }
    }
    
    # Evaluate refresh schedule
    if ($_.RefreshSchedule.HourSpan -ne 0) {
        $temp | Add-Member -MemberType NoteProperty -Name "RefreshSchedule" -Value "$($_.RefreshSchedule.HourSpan)h"
    } elseif ($_.RefreshSchedule.DaySpan -ne 0) {
        $temp | Add-Member -MemberType NoteProperty -Name "RefreshSchedule" -Value "$($_.RefreshSchedule.DaySpan)d"
    } else {
        $temp | Add-Member -MemberType NoteProperty -Name "RefreshSchedule" -Value "0"
    }

    # Add PS object to array
    $Collections.Add($temp) | Out-Null
}

$Collections | Out-GridView -Title "$($SiteCode.Description) | All Custom Collections | Total ($($Collections | Measure-Object | Select-Object -ExpandProperty Count)) Incremental ($($Collections | Where-Object {($_.RefreshType -eq "Both") -or ($_.RefreshType -eq "Incremental")} | Measure-Object | Select-Object -ExpandProperty Count)) Manual ($($Collections | Where-Object {$_.RefreshType -eq "Manual"} | Measure-Object | Select-Object -ExpandProperty Count)) Empty ($($Collections | Where-Object {$_.MemberCount -lt 1} | Measure-Object | Select-Object -ExpandProperty Count))"

# Set update schedule on all specific collections
$Collections | Where-Object {($_.CollectionID -notlike "SMS*") -and ($_.ObjectPath -match "Application")} | ForEach-Object {
    Set-CMCollection -CollectionId $_.CollectionId -RefreshType Periodic -RefreshSchedule (New-CMSchedule -Start (Get-Date -Format d) -DurationInterval 0 -RecurInterval Hours -RecurCount 4 -DurationCount 0) -WhatIf
}
