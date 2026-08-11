# Capture the active scheme GUID
$ActiveScheme = cmd /c "powercfg /getactivescheme"
$RegEx = '(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}'
$AsGuid = [regex]::Match($ActiveScheme,$regEx).Value

# Sleep timeout
cmd /c "powercfg /setacvalueindex $AsGuid 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 3600" # Plugged in
cmd /c "powercfg /setdcvalueindex $AsGuid 238c9fa8-0aad-41ed-83f4-97be242c8f20 29f6c1db-86da-48c5-9fdb-f2b67b1f44da 1800" # On battery

# Display idle
cmd /c "powercfg /setacvalueindex $AsGuid 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 3600" # Plugged in
cmd /c "powercfg /setdcvalueindex $AsGuid 7516b95f-f776-4464-8c53-06167f40cc99 3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e 600" # On battery

# Lid close
cmd /c "powercfg /setacvalueindex $AsGuid 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 0" # Plugged in
cmd /c "powercfg /setdcvalueindex $AsGuid 4f971e89-eebd-4455-a8de-9e59040e7347 5ca83367-6e45-459f-a27b-476b1d01c936 1" # On battery

# Apply settings
cmd /c "powercfg /s $AsGuid"
