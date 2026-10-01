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

## Local installation and Gallery publication

Install the module into the first suitable directory in `PSModulePath`, or pass an explicit destination:

```powershell
.\InstallModule.ps1
.\InstallModule.ps1 -FullPath "$HOME\Documents\PowerShell\Modules\PSAICloudflareClef"
Import-Module PSAICloudflareClef -Force
```

To publish manually, set `NuGetApiKey` in the environment and run `PublishToGallery.ps1`. Use `-WhatIf` to validate the manifest and review the intended action without publishing. The script validates that the manifest names this module and asks for confirmation before publication.

## Models and images

Clef is the default. `-Model ClefFlash` selects `@cf/cloudflare/clef-flash`; the official model page documents both models with the same request fields and limits. Clef-flash is the faster 9B model, while Clef is the 27B model.

For vision requests, pass one to four embedded PNG, JPEG, or WebP data URIs or raw base64 image values through `-Image`. Remote URLs are rejected. Cloudflare documents a maximum of 4 MiB and 16 megapixels per image, 8 MiB decoded across all images, and a 13 MiB whole request body. The module validates embedded format signatures for raw base64, image count, 4 MiB per image, 8 MiB aggregate, and 13 MiB serialized body. Cloudflare enforces the 16 megapixel limit. The model can also read video represented in `State`; the input may be truncated to fit the model context window.

```powershell
# Example only: $imageDataUri should contain an embedded image data URI.
$result = Invoke-CloudflareClefDecision -State 'Is the screenshot showing a payment error?' `
    -Questions @{ paymentError = @{ type = 'noul'; instructions = 'Does the screenshot show a payment error?' } } `
    -Image $imageDataUri
```

## Request and question limits

The request is `POST https://api.cloudflare.com/client/v4/accounts/{ACCOUNT_ID}/ai/run/@cf/cloudflare/clef` with JSON `model: "clef"`, `state`, and named `questions`. The Flash model uses `model: "clef-flash"` and its corresponding model path.

- Questions: 1–64 per request.
- Question IDs: 1–100 characters, using letters, digits, `_`, `.`, or `-`.
- Types: `noul` (yes/no probability), `choice` (named options), `score` (ordered rubric).
- Choice: 1–255 named criteria options; score: 2–10 ordered rubric levels (compatible with the Jev helper patterns).
- Images: up to four embedded PNG/JPEG/WebP images; no remote URLs.
- Context window: 65,536 tokens; long text state is truncated by the service.

The command validates request structure before HTTP. Cloudflare HTTP and transport failures are terminating errors. HTTP errors include status and response details when available without including authorization headers or request content.

## Development

Run offline Pester tests from the repository root:

```powershell
Invoke-Pester .\Tests
```

All HTTP calls in tests are mocked. No test makes a live Cloudflare request.

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
