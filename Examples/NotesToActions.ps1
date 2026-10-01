# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Accept a notes file path or use the small built-in demonstration set.
[CmdletBinding()]
param(
    # Read one note per non-empty line when a path is supplied.
    [string] $Path
)

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Read supplied notes or provide examples covering tasks, decisions, and context.
if ($Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Notes file not found: $Path" }
    $notes = @(Get-Content -LiteralPath $Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
else {
    $notes = @(
        'Email Sam the updated mockup before the review on Thursday.'
        'We agreed that the first release will support PowerShell only.'
        'The staging environment is refreshed every Monday morning.'
        'I still need to choose whether to keep the tray icon in version one.'
        'Schedule 30 minutes with Priya to review the onboarding flow.'
        'The customer says importing sales files from last quarter takes too long.'
        'The team decided to hold the public demo until the Gallery package is ready.'
        'Check with finance whether the old invoice format is still required.'
    )
}

# Reuse one named choice question for each independent note.
$question = New-CloudflareClefQuestion -Name category -Type Choice `
    -Instructions 'Classify this note by its primary purpose. Choose action for a specific follow-up someone should do, decision for a settled or unresolved choice, or background for context that does not directly call for a task or decision.' `
    -Criteria ([ordered]@{
            action     = 'A concrete task or follow-up for someone to do.'
            decision   = 'A choice or conclusion that has been made, or a choice still to make.'
            background = 'Context, an observation, or an idea with no direct task or decision.'
        })

# Evaluate each note separately because each note is a different state.
$results = foreach ($note in $notes) {
    $answer = (Invoke-CloudflareClefDecision -State @{ Note = $note.Trim() } -Question $question).answers.category
    [pscustomobject]@{ Category = $answer.choice; Confidence = [math]::Round([double]$answer.confidence, 2); Note = $note.Trim() }
}

# Group results in a stable order and show the API confidence with each note.
foreach ($category in 'action', 'decision', 'background') {
    $items = @($results | Where-Object Category -eq $category)
    if ($items.Count -eq 0) { continue }
    Write-Host "`n$($category.ToUpperInvariant())" -ForegroundColor Cyan
    $items | Sort-Object Confidence -Descending | Format-Table Confidence, Note -Wrap
}
