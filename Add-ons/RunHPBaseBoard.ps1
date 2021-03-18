$RepoDir = "\\sccm07\sources\HPIA\Repository"
$CSVPath = (Join-Path -Path ($RepoDir | Split-Path -Parent) -ChildPath "Models.csv")
$CSV = Import-Csv -Path $CSVPath

Get-CimInstance -Namespace root\wmi -ClassName MS_SystemInformation | ForEach-Object {
    if ($_.BaseBoardProduct -notin $CSV.ProdCode) {
        $ModelInfo = [PSCustomObject]@{
            ProdCode = $_.BaseBoardProduct
            Model = $_.SystemProductName
        } | Export-Csv -Path $CSVPath -Force -Append -NoTypeInformation
    }
} 
