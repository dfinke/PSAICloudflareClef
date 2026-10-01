# Load private functions before public commands so dependencies are available.
$privatePath = Join-Path $PSScriptRoot 'Private'
foreach ($script in Get-ChildItem -LiteralPath $privatePath -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name) {
    # Dot-source the helper into this module's private scope.
    . $script.FullName
}

# Load public commands after the private helpers.
$publicPath = Join-Path $PSScriptRoot 'Public'
foreach ($script in Get-ChildItem -LiteralPath $publicPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name) {
    # Dot-source the supported module command.
    . $script.FullName
}

# Export only the module's documented public commands.
Export-ModuleMember -Function @('Invoke-CloudflareClefDecision', 'New-CloudflareClefQuestion')
