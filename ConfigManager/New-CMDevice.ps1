[CmdletBinding()]
param (
    [parameter(Mandatory = $true, HelpMessage = "Device serial number")]
	[ValidateNotNullOrEmpty()]
    $SerialNumber,
    [parameter(Mandatory = $true, HelpMessage = "MAC address (xx:xx:xx:xx:xx:xx)")]
	[ValidateNotNullOrEmpty()]
    $MACAddress
)
begin {
    # Load CM module
    Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') 
    $SiteCode = Get-PSDrive -PSProvider CMSITE 
    Set-location $SiteCode":"
}
process {
    try {
        Import-CMComputerInformation -ComputerName $SerialNumber -MacAddress $MACAddress -ErrorAction Stop
    }
    catch [System.Exception] {
        Write-Warning -Message "Unable to import computer object. Error message: $($_.Exception.Message)"
    }

    # List all imported computers
    $Array = New-Object -TypeName System.Collections.ArrayList
    Get-WmiObject -Namespace "root\SMS\site_$($SiteCode)" -ComputerName $SiteCode.SiteServer -Query 'Select * from SMS_R_System where AgentName like "Manual Machine Entry"' | ForEach-Object {
        # Create new temporary PS object
        $temp = New-Object -TypeName PSCustomObject
        $temp | Add-Member -MemberType NoteProperty -Name "Name" -Value $_.Name
        $temp | Add-Member -MemberType NoteProperty -Name "MACAddresses" -Value $($_.MACAddresses | Select-Object -First 1)
        $temp | Add-Member -MemberType NoteProperty -Name "CreationDate" -Value $(Get-Date ("{0}-{1}-{2}" -f $_.CreationDate.Substring(0,4), $_.CreationDate.Substring(4,2), $_.CreationDate.Substring(6,2)) -Format d)
        $Array.Add($temp)
    }
    $Array | Out-GridView
}
