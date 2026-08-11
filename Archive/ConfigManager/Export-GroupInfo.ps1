try {
    # Load CM module
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop
    $SiteCode = Get-PSDrive -PSProvider CMSITE -ErrorAction Stop
    Set-location $SiteCode":" -ErrorAction Stop
}
catch [System.Exception] {
        Write-Warning -Message $_.Exception.Message
}

$CollectionID = "P010019F"
$Array = New-Object -TypeName System.Collections.ArrayList
Get-CMCollectionMember -CollectionId $CollectionID | ForEach-Object {
    if ($null -ne $_.CurrentLogonUser) {
        $User = Get-ADUser -Identity ($_.CurrentLogonUser | Split-Path -Leaf) | Select-Object Name,UserPrincipalName
    } else {
        $User = Get-ADUser -Identity ($_.PrimaryUser | Split-Path -Leaf) | Select-Object Name,UserPrincipalName
    }
    $Array.Add(([PSCustomObject]@{
        Computer = $_.Name
        User = $User.Name
        Mail = $User.UserPrincipalName
    }))
}

 $Array | Export-Csv -Path "C:\temp\$(Get-Date -Format d).csv" -NoTypeInformation -Encoding Unicode -Force