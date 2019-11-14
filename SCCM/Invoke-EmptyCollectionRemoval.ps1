Get-CMCollection -CollectionType Device | Where-Object { ($_.MemberCount -lt 10) -and ($_.IsReferenceCollection -eq $false) -and ($_.IsBuiltIn -eq $false) -and ($_.LastChangeTime -lt (Get-Date).AddMonths(-10)) } | ForEach-Object -Begin { $RetiredCollections = New-Object -TypeName System.Collections.ArrayList } -Process {
    Write-Host "Evaluating collection: $($_.Name)"

    $TempCollection = $_
    if ([string]::IsNullOrEmpty((Get-CMDeployment | Where-Object { $_.CollectionID -eq $TempCollection.CollectionID }))) {
        
        # Export CM collection
        try {
            Export-CMCollection -CollectionId $_.CollectionID -ExportFilePath "\\sccm07\e$\Backup\Collections\Device Collections\AutoExport\$($_.Name).mof" -ExportComment "$(Get-Date -Format d): Collection Cleanup ($($_.CollectionType)); " -Force -ErrorAction SilentlyContinue
        }
        catch [System.Exception] {
            Write-Warning "Failed to export collection: $($_.Name)"
        }

        # Remove CM collection
        try {
            Remove-CMCollection -Id $_.CollectionID -Force -ErrorAction SilentlyContinue
        }
        catch [System.Exception] {
            Write-Warning "Failed to remove collection: $($_.Name)"
        }

        # Add data to array
        [void]$RetiredCollections.Add([PSCustomObject]@{
                Name           = $TempCollection.Name
                CollectionID   = $TempCollection.CollectionID
                LastChangeTime = $TempCollection.LastChangeTime
        })
    }

    # Remove temporary variable
    Remove-Variable TempCollection -Force -ErrorAction SilentlyContinue
} -End { $RetiredCollections | Export-Csv -Path "filesystem::\\sccm07\e$\Backup\Collections\Device Collections\AutoExport\AE-$(New-Guid).csv" -NoTypeInformation -Encoding UTF8 -Force }