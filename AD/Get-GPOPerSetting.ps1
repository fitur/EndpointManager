Import-Module GroupPolicy

$UnlinkedGPOList = @()
$LinkedGPOList = @()

# Gather unlinked group policies with specific
Get-GPO -All | ForEach-Object {
	if ($_ | Get-GPOReport -ReportType XML | Where-Object { ($_ | Select-String -Pattern "Screen saver timeout") -and ($_ | Select-String -Pattern "<LinksTo>") }) {
		$UnlinkedGPOList += $_ | Select-Object DisplayName, Owner, CreationTime, ModificationTime
	}
}

# Get linked group policies
Get-GPO -All | ForEach-Object {
	if ($_ | Get-GPOReport -ReportType Xml | Where-Object { $_ | Select-String -Pattern "<SOMPath>xxx.local/Data/Accounts/Computers</SOMPath>" }) {
		$GPOList += ($_ | Select-Object DisplayName, Owner, CreationTime, ModificationTime)
	}
}

# get group policies with specific keyword
Get-GPO -All | ForEach-Object -Begin { $GPOList = New-Object -TypeName System.Collections.ArrayList } {
	if ($_ | Get-GPOReport -ReportType XML | Where-Object { ($_ | Select-String -Pattern "Screen saver timeout") }) {
		[void]$GPOList.Add(( $_ | Select-Object DisplayName, Owner, CreationTime, ModificationTime ))
	}
}

$GPOList | Out-GridView
