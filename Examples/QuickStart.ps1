# Import the module manifest from this repository folder.
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'PSAICloudflareClef.psd1')

# Show an offline-safe example request definition; invoking it requires Cloudflare credentials and makes a live request.
$state = @{ ticket = 'The latest invoice is incorrect and the customer may cancel.' }
$questions = @(
    New-CloudflareClefQuestion -Name route -Type Choice -Instructions 'Which team should handle the issue?' -Criteria @{ billing = 'Invoices, payments, or refunds'; support = 'Product use or technical issue' }
    New-CloudflareClefQuestion -Name churnRisk -Type Noul -Instructions 'Does this indicate an immediate churn risk?'
    New-CloudflareClefQuestion -Name urgency -Type Score -Instructions 'How urgent is this issue?' -Criteria @('Can wait', 'This week', 'Today')
)

# The following command sends the request only when this example script is run intentionally.
$result = Invoke-CloudflareClefDecision -State $state -Question $questions
$result.answers
