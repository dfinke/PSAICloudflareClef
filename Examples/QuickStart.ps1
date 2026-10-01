# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Set CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN before running this live example.

# Provide the context once and ask three differently typed questions in one request.
$state = @{
    message = 'The customer is blocked by an outage and may cancel.'
}
$questions = @(
    New-CloudflareClefQuestion -Name churn -Type Noul -Instructions 'Is this an active churn threat?'
    New-CloudflareClefQuestion -Name route -Type Choice `
        -Instructions 'Which team should handle this?' `
        -Criteria @{
            support = 'The issue needs technical support.'
            sales   = 'The issue concerns pricing or renewal.'
        }
    New-CloudflareClefQuestion -Name urgency -Type Score `
        -Instructions 'How urgent is this?' `
        -Criteria @('Can wait', 'This week', 'Today')
)

# Send one live request; set CLOUDFLARE_API_TOKEN before running this example.
$result = Invoke-CloudflareClefDecision -State $state -Question $questions

# Keep the raw answer object available for callers and print a compact readable view.
$result
$summary = @(
    [pscustomobject]@{ Question = 'churn'; Type = 'noul'; Result = $result.answers.churn.noul }
    [pscustomobject]@{ Question = 'route'; Type = 'choice'; Result = $result.answers.route.choice; Confidence = $result.answers.route.confidence; Probabilities = $result.answers.route.probabilities }
    [pscustomobject]@{ Question = 'urgency'; Type = 'score'; Result = $result.answers.urgency.score; Confidence = $result.answers.urgency.confidence; Probabilities = $result.answers.urgency.probabilities }
)
$summary | Format-Table -AutoSize -Wrap
