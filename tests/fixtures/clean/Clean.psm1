# Loads every function file under Public, as PDS's loader does: a file that fails
# to load is reported with a non-terminating error.
$publicFunctions = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1')
foreach ($file in $publicFunctions) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.FullName): $_"
    }
}
Export-ModuleMember -Function $publicFunctions.BaseName
