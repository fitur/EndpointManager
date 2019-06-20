# Import CM module
Import-module ($Env:SMS_ADMIN_UI_PATH.Substring(0,$Env:SMS_ADMIN_UI_PATH.Length-5) + '\ConfigurationManager.psd1') -ErrorAction Stop

# Name of scheduled task
$TaskName = "Advania - Remove Old IIS Logs"

Invoke-Command -ComputerName (Get-PSDrive -PSProvider CMSITE).Root -ArgumentList $TaskName -ScriptBlock {
	param($TaskName)

	# Create and run scheduled task if not already exist
	if (!(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
		$Action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Unrestricted -Command "& { Get-ChildItem -Path (Join-Path -Path $env:SystemDrive -ChildPath ''inetpub\logs\LogFiles'' -Resolve -ErrorAction Stop) -Recurse -File | Where-Object {$_.Extension -eq ''.log'' -and $_.LastWriteTime -lt (Get-Date).AddMonths(-1)} | ForEach-Object {Remove-Item -Path $_.FullName -Force -Verbose} }"' -Verbose
		$Trigger = New-ScheduledTaskTrigger -Daily -At (Get-Date).Date
		$Principal = New-ScheduledTaskPrincipal -UserID 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
		$SChTask = Register-ScheduledTask -Action $Action -Trigger $Trigger -Principal $Principal -TaskName $TaskName -Force
		$SChTask | Start-ScheduledTask
	}
}
