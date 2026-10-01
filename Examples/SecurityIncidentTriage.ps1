# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Provide the alert and related asset, ticket, maintenance, and authorization context.
$state = [ordered]@{
    alert = 'A PowerShell process read LSASS memory using comsvcs.dll on a production server.'
    asset = [ordered]@{ environment = 'production'; tier = 'critical'; owner = 'platform operations' }
    open_tickets = @('INC-1042: investigate unusual PowerShell activity on the production server')
    registered_devices = @('The owner normally uses a managed Windows laptop from the corporate network.')
    scheduled_maintenance = @('No maintenance window is scheduled.')
    standing_authorizations = @('Platform operations may run approved diagnostics during an incident.')
}

# Ask for authorization context, evidence strength, and an immediate response in one request.
$questions = @(
    New-CloudflareClefQuestion -Name unauthorized_activity -Type Noul `
        -Instructions 'Does alert describe unauthorized activity given standing_authorizations and scheduled_maintenance? Yes means an authorization or maintenance window does not explain the activity. No means an approved authorization or maintenance window explains it.'
    New-CloudflareClefQuestion -Name evidence_strength -Type Score `
        -Instructions 'How strong is the evidence that the activity in alert is harmful, given the asset and incident records?' `
        -Criteria @('Weak: an unusual event with a plausible benign explanation.', 'Moderate: suspicious activity with incomplete supporting evidence.', 'Strong: a high impact asset and a clear malicious technique.')
    New-CloudflareClefQuestion -Name response -Type Choice `
        -Instructions 'What immediate response best fits this alert and the available records?' `
        -Criteria @{
            notify_user     = 'Notify the asset owner and continue monitoring.'
            escalate_tier2  = 'Queue the alert for a security analyst.'
            kill_process    = 'Stop the suspicious process while preserving the account.'
            disable_account = 'Disable the suspected account because identity misuse is likely.'
            escalate_urgent = 'Escalate urgently because the production impact is severe or expanding.'
        }
)

# Send a single request containing the incident state and all three questions.
$response = Invoke-CloudflareClefDecision -State $state -Question $questions

# Print the complete response so probability distributions remain available for review.
$response | ConvertTo-Json -Depth 20

# Display a compact summary using only documented typed answer fields.
$summary = @(
    [pscustomobject]@{ Question = 'unauthorized_activity'; Type = 'noul'; Decision = $response.answers.unauthorized_activity.noul }
    [pscustomobject]@{ Question = 'evidence_strength'; Type = 'score'; Decision = $response.answers.evidence_strength.score; Confidence = $response.answers.evidence_strength.confidence; Probabilities = $response.answers.evidence_strength.probabilities }
    [pscustomobject]@{ Question = 'response'; Type = 'choice'; Decision = $response.answers.response.choice; Confidence = $response.answers.response.confidence; Probabilities = $response.answers.response.probabilities }
)
$summary | Format-Table -AutoSize -Wrap
