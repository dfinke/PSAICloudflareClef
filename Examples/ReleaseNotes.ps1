# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Select the repository and number of recent commit subjects to review.
[CmdletBinding()]
param(
    # Read commits from this local repository path.
    [string] $RepositoryPath = (Get-Location).Path,

    # Bound the commit list size before it is sent as repeated API requests.
    [ValidateRange(1, 100)]
    [int] $Count = 20
)

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Read abbreviated commit hashes and subjects without changing the repository.
$commitLines = @(git -C $RepositoryPath log -n $Count --format='%h%x09%s')
if ($LASTEXITCODE -ne 0) { throw "Could not read Git history from '$RepositoryPath'. Check that it is a Git repository." }
$commits = foreach ($line in $commitLines) {
    $parts = $line -split "`t", 2
    if ($parts.Count -eq 2) { [pscustomobject]@{ Commit = $parts[0]; Subject = $parts[1] } }
}

# Classify each subject into one of four release-note groups.
$question = New-CloudflareClefQuestion -Name category -Type Choice `
    -Instructions 'Classify this Git commit using only its subject. Choose breaking for an incompatible public change that likely requires users to change scripts or configuration; feature for a user-visible capability; fix for a user-visible defect correction; internal for tests, documentation, refactoring, or maintenance without user-visible behavior change.' `
    -Criteria ([ordered]@{
            breaking = 'An incompatible public change that may require existing users to update scripts or configuration.'
            feature  = 'A new user-visible capability or meaningful improvement.'
            fix      = 'A correction to a user-visible defect.'
            internal = 'Tests, documentation, refactoring, or maintenance without user-visible behavior change.'
        })

# Evaluate each commit independently and retain the returned confidence and probabilities.
$results = foreach ($commit in $commits) {
    $answer = (Invoke-CloudflareClefDecision -State @{ Commit = $commit.Commit; Subject = $commit.Subject } -Question $question).answers.category
    [pscustomobject]@{ Category = $answer.choice; Confidence = [math]::Round([double]$answer.confidence, 2); Probabilities = $answer.probabilities; Commit = $commit.Commit; Subject = $commit.Subject }
}

# Show every category so internal work stays visible during review.
foreach ($category in 'breaking', 'feature', 'fix', 'internal') {
    $items = @($results | Where-Object Category -eq $category)
    if ($items.Count -eq 0) { continue }
    $heading = if ($category -eq 'internal') { 'Internal changes (left out of draft)' } else { $category.ToUpperInvariant() }
    Write-Host "`n$heading" -ForegroundColor Cyan
    $items | Sort-Object Confidence -Descending | Format-Table Confidence, Commit, Subject -Wrap
}

# Produce a draft list from behavior changes for a human to edit before publishing.
Write-Host "`nDraft release notes (review before publishing):" -ForegroundColor Cyan
$results | Where-Object Category -in @('breaking', 'feature', 'fix') | Sort-Object @{ Expression = { @('breaking', 'feature', 'fix').IndexOf($_.Category) } }, @{ Expression = 'Confidence'; Descending = $true } | ForEach-Object { "- [$($_.Category)] $($_.Subject)" }
