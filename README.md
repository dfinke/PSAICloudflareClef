<p align="center">
  <img src="assets/cloudflare-clef.png" alt="Cloudflare Clef typed decision illustration" width="180">
</p>

# PSAICloudflareClef

A standalone PowerShell module for structured decisions with Cloudflare Workers AI Clef. It sends a state and named `noul`, `choice`, and `score` questions to the official account-scoped REST endpoint and returns Cloudflare's parsed response.

The module is independent. It does not import or modify PSAIPerplexityDecisions, Jev, or any other provider module.

## Install and configure

Clone this repository, then import its manifest:

```powershell
Import-Module .\PSAICloudflareClef.psd1 -Force
```

Set the account ID and API token in your environment, or pass them explicitly to the command:

```powershell
$env:CLOUDFLARE_ACCOUNT_ID = 'your-account-id'
$env:CLOUDFLARE_API_TOKEN = 'your-token'
```

Create a Cloudflare API token using the Workers AI template. If creating a custom token, Cloudflare documents both `Workers AI - Read` and `Workers AI - Edit` permissions for REST API use. The token is sent only in an HTTPS Bearer authorization header; never commit it or print it.

## Quick start

```powershell
Import-Module .\PSAICloudflareClef.psd1 -Force

$state = @{
    incident = 'Checkout has returned HTTP 503 errors for every customer for the last hour.'
    affectedCustomers = 1200
}

$questions = @(
    New-CloudflareClefQuestion -Name urgent -Type Noul `
        -Instructions 'Is this incident urgent?'
    New-CloudflareClefQuestion -Name owner -Type Choice `
        -Instructions 'Which team should handle this incident?' `
        -Criteria @{
            billing   = 'Payments, invoices, and refunds'
            technical = 'Outages, errors, and configuration'
            sales     = 'Plans and upgrades'
        }
    New-CloudflareClefQuestion -Name severity -Type Score `
        -Instructions 'How severe is the customer impact?' `
        -Criteria @('No impact', 'Minor', 'Major', 'Critical')
)

$result = Invoke-CloudflareClefDecision -State $state -Question $questions
$result.answers.urgent.noul
$result.answers.owner.choice
$result.answers.severity.score
```

`New-CloudflareClefQuestion` creates a typed PowerShell object. Alternatively, pass an API-shaped named map to `-Questions`. The `-AccountId` and `-Token` parameters override `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN`. The HTTP timeout defaults to 30 seconds; `-TimeoutSec` accepts 1 through 600.

## Examples

The `Examples` folder adapts the decision workflows from [dfinke/Jev](https://github.com/dfinke/Jev/tree/main/Examples) to this standalone Cloudflare module. Each script imports `PSAICloudflareClef.psd1` with `-Force`. Scripts that invoke Clef make live requests and can incur Workers AI usage; set `CLOUDFLARE_ACCOUNT_ID` and `CLOUDFLARE_API_TOKEN` first.

- `QuickStart.ps1` asks `noul`, `choice`, and `score` questions in one request.
- `RefundTriage.ps1`, `SecurityIncidentTriage.ps1`, and `PageOnCall.ps1` demonstrate support and incident workflows.
- `SemanticLogTriage.ps1` classifies log lines; `NotesToActions.ps1` categorizes notes.
- `PowerShellCommandFinder.ps1` searches local command metadata and suggests a command without running it.
- `ReleaseNotes.ps1` and `StandupReport.ps1` summarize local Git history; the latter also shows the working tree, plan, and blockers.
- `Excel-IT-Queue.ps1` and `DealDesk.ps1` require the `ImportExcel` module. Sample workbooks are in `data/`.

`InstallModule.ps1` installs the module locally. `PublishToGallery.ps1` validates the manifest and publishes only when run with a Gallery key; it supports `-WhatIf` and confirmation.
## Official documentation

- [Clef model and request schema](https://developers.cloudflare.com/workers-ai/models/clef/)
- [Workers AI REST API setup and token permissions](https://developers.cloudflare.com/workers-ai/get-started/rest-api/)
