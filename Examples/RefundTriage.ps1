# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Keep the customer message and the policy together as decision context.
$state = [ordered]@{
    ticket_message = 'My flight was cancelled. Can I get a refund?'
    refund_policy  = 'Cancelled flights are eligible for a full refund.'
}

# Ask about refund intent, request category, and frustration in one API call.
$questions = @(
    New-CloudflareClefQuestion -Name refund_requested -Type Noul -Instructions 'Does ticket_message request a refund?'
    New-CloudflareClefQuestion -Name request_type -Type Choice `
        -Instructions 'What is the main request in ticket_message?' `
        -Criteria @{
            refund      = 'The customer wants money returned.'
            rebooking   = 'The customer wants a replacement flight.'
            information = 'The customer is asking for information only.'
        }
    New-CloudflareClefQuestion -Name frustration -Type Score `
        -Instructions 'How frustrated does the customer appear in ticket_message?' `
        -Criteria @('Calm and neutral.', 'Concerned but civil.', 'Very angry or using strong language.')
)

# Send the request; set CLOUDFLARE_API_TOKEN before running this example.
$response = Invoke-CloudflareClefDecision -State $state -Question $questions

# Print the complete parsed response, including the probabilities in answers.
$response | ConvertTo-Json -Depth 20

# Display the typed result fields documented for each question kind.
$summary = @(
    [pscustomobject]@{ Question = 'refund_requested'; Type = 'noul'; Decision = $response.answers.refund_requested.noul }
    [pscustomobject]@{ Question = 'request_type'; Type = 'choice'; Decision = $response.answers.request_type.choice; Confidence = $response.answers.request_type.confidence; Probabilities = $response.answers.request_type.probabilities }
    [pscustomobject]@{ Question = 'frustration'; Type = 'score'; Decision = $response.answers.frustration.score; Confidence = $response.answers.frustration.confidence; Probabilities = $response.answers.frustration.probabilities }
)
$summary | Format-Table -AutoSize -Wrap
