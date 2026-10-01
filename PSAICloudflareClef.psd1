@{
    # Identify the independent Cloudflare Clef PowerShell module.
    RootModule        = 'PSAICloudflareClef.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '9ee2a4be-01aa-49da-a945-ae7c00ec468e'
    Author            = 'David Finke'
    CompanyName       = 'Community'
    Copyright         = '(c) 2026. All rights reserved.'
    Description       = 'PowerShell commands for typed decisions with Cloudflare Workers AI Clef.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-CloudflareClefDecision', 'New-CloudflareClefQuestion')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Cloudflare', 'WorkersAI', 'Clef', 'Decisions', 'PowerShell')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = 'https://github.com/dfinke/PSAICloudflareClef'
            ReleaseNotes = 'Initial standalone Cloudflare Clef module.'
        }
    }
}
