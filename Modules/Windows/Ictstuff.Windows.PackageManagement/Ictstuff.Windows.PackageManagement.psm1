$publicFunctions = Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue
$privateFunctions = Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue

foreach ($function in @($publicFunctions) + @($privateFunctions)) {
    . $function.FullName
}

Export-ModuleMember -Function $publicFunctions.BaseName
