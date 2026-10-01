# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Accept log lines from the command line or use the short built-in sample.
[CmdletBinding()]
param(
    # Provide one or more log lines to classify.
    [string[]] $LogLine = @(
        'INFO web service started successfully on port 8080.'
        'WARN DNS lookup timed out while connecting to api.internal.'
        'ERROR invalid JSON in the deployment configuration.'
        'ALERT unauthorized login followed by a privilege escalation attempt.'
    )
)

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Ask about security risk and likely root-cause category together for each log line.
$questions = @(
    New-CloudflareClefQuestion -Name critical_security_risk -Type Noul `
        -Instructions 'Is this log line evidence of a critical security risk or attack? Yes means breach, unauthorized access, credential attack, or privilege escalation. No means a normal operational message or non-security application failure.'
    New-CloudflareClefQuestion -Name root_cause -Type Choice `
        -Instructions 'What is the most likely root-cause category for this log line?' `
        -Criteria @{
            auth    = 'Authentication, credentials, identity, authorization, or access failure.'
            network = 'Network, DNS, connection, socket, timeout, or transport failure.'
            syntax  = 'Syntax, parsing, malformed configuration, or invalid format failure.'
            unknown = 'No clear root-cause category is supported by the line.'
        }
)

# Evaluate each log line as its own state while using the same named questions.
$results = foreach ($line in $LogLine) {
    $response = Invoke-CloudflareClefDecision -State @{ log_line = $line } -Question $questions
    $security = $response.answers.critical_security_risk
    $cause = $response.answers.root_cause
    $risk = [math]::Round([double]$security.noul, 3)
    $indicator = if ($risk -ge 0.8) { 'High' } elseif ($risk -ge 0.5) { 'Review' } else { 'Low' }
    [pscustomobject]@{
        Indicator           = $indicator
        LogLine             = $line
        CriticalRisk        = $risk
        RootCause           = [string] $cause.choice
        RootCauseConfidence = [math]::Round([double]$cause.confidence, 3)
        RootCauseProbabilities = $cause.probabilities
    }
}

# Sort the table by security probability for quick review.
$results | Sort-Object CriticalRisk -Descending | Format-Table Indicator, CriticalRisk, RootCause, RootCauseConfidence, LogLine -Wrap -AutoSize
