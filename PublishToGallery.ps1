# Publish this module to a registered PowerShell Gallery repository when run manually.
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    # Read the gallery key from the environment by default; do not print it.
    [string] $NuGetApiKey = $env:NuGetApiKey,

    # Select a registered PowerShell repository such as PSGallery or a test gallery.
    [ValidateNotNullOrEmpty()]
    [string] $Repository = 'PSGallery'
)


# Validate the manifest from this repository and stop on packaging errors.
$manifestPath = Join-Path $PSScriptRoot 'PSAICloudflareClef.psd1'
$manifest = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop

# Ensure this script publishes the intended standalone Cloudflare Clef module.
if ($manifest.Name -ne 'PSAICloudflareClef') {
    throw "Expected PSAICloudflareClef.psd1 to describe the PSAICloudflareClef module, but found '$($manifest.Name)'."
}

# Explain the manual action and honor -WhatIf or -Confirm before publishing.
if ($PSCmdlet.ShouldProcess("$($manifest.Name) $($manifest.Version) to $Repository", 'Publish PowerShell module')) {
    # Require the Gallery key only after ShouldProcess approves the real publication.
    if ([string]::IsNullOrWhiteSpace($NuGetApiKey)) {
        throw 'Set $env:NuGetApiKey or pass -NuGetApiKey before publishing.'
    }

    # Publish the module from this repository without echoing the API key.
    Publish-Module `
        -Path $PSScriptRoot `
        -Repository $Repository `
        -NuGetApiKey $NuGetApiKey `
        -ErrorAction Stop
}
