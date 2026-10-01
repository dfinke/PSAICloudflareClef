# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Describe the paging policy as one named yes/no decision.
$question = New-CloudflareClefQuestion -Name pageOnCall -Type Noul `
        -Instructions 'Based on customer checkout impact, should the on-call engineer be paged now? Yes means checkout is unavailable or a substantial share of customers cannot purchase. No means purchases work normally; isolated card declines and unrelated dashboards do not count.'

# Compare clear outages, normal operation, and incidents near the policy boundary.
$states = @(
    'Checkout is returning HTTP 503 errors, and no customers can place orders.'
    'Checkout is slower than usual, but customers are still completing purchases successfully.'
    'The payment provider is declining every transaction. Customers cannot complete purchases.'
    'The payment provider is degraded, but the backup processor is handling all transactions.'
    'About 30 percent of checkout attempts are failing with a payment timeout.'
    'The internal reporting dashboard is down. Checkout and customer purchases are working normally.'
    'The orders database is unavailable, so checkout cannot save or complete purchases.'
    'A single customer payment failed because their card was declined. Other purchases are succeeding.'
    'Customers are unable to buy anything after the latest deployment. The failure has lasted 12 minutes.'
    'A scheduled maintenance check is running. No checkout errors or failed purchases have been reported.'
)

# These example cutoffs are an application policy, not a setting or promise from the API.
$results = foreach ($issue in $states) {
    # Send one request for each distinct incident state.
    $answer = (Invoke-CloudflareClefDecision -State @{ issue = $issue } -Question $question).answers.pageOnCall
    $probability = [double] $answer.noul

    # Leave middle probability values for human review under this illustrative policy.
    $action = if ($probability -ge 0.8) { 'Page' } elseif ($probability -le 0.2) { 'Do not page' } else { 'Review' }

    # Return the incident, raw probability, and application-level action together.
    [pscustomobject]@{ Action = $action; ProbabilityOfPage = [math]::Round($probability, 2); Issue = $issue }
}

# Sort the sample incidents by the returned probability.
$results | Sort-Object ProbabilityOfPage -Descending | Format-Table -AutoSize -Wrap
