# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Gather recent commits, working tree status, today's plan, and blockers.
[CmdletBinding()]
param(
    # Select a local Git repository to summarize.
    [string] $RepositoryPath = (Get-Location).Path,

    # Choose how far back to read commits.
    [ValidateRange(1, 30)]
    [int] $Days = 1,

    # Bound the maximum number of commit subjects considered.
    [ValidateRange(1, 100)]
    [int] $CommitLimit = 30,

    # Add optional work planned for today.
    [string[]] $Today = @(),

    # Add optional blockers for the standup.
    [string[]] $Blockers = @()
)

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Read recent commit subjects from Git without changing local repository state.
$commitLines = @(git -C $RepositoryPath log -n $CommitLimit "--since=$Days days ago" '--format=%h%x09%s')
if ($LASTEXITCODE -ne 0) { throw "Could not read Git history from '$RepositoryPath'. Check that it is a Git repository." }
$commits = foreach ($line in $commitLines) {
    $parts = $line -split "`t", 2
    if ($parts.Count -eq 2) { [pscustomobject]@{ Commit = $parts[0]; Subject = $parts[1] } }
}

# Read the current short working tree status for context in the report.
$workingTree = @(git -C $RepositoryPath status --short)
if ($LASTEXITCODE -ne 0) { throw "Could not read working-tree status from '$RepositoryPath'." }

# Classify each commit by its likely standup outcome.
$question = New-CloudflareClefQuestion -Name updateType -Type Choice `
    -Instructions 'Classify the outcome described by this Git commit subject for a team standup. Choose delivery for a user-visible feature or behavior change, reliability for a bug fix or quality improvement, exploration for investigation or prototype, and internal for documentation, tests, refactoring, or build maintenance.' `
    -Criteria ([ordered]@{
            delivery    = 'A user-visible feature or behavior change.'
            reliability = 'A bug fix or quality improvement.'
            exploration = 'An investigation, experiment, or prototype.'
            internal    = 'Documentation, tests, refactoring, or build maintenance.'
        })

# Evaluate commit subjects individually because each one is a distinct state.
$updates = foreach ($commit in $commits) {
    $answer = (Invoke-CloudflareClefDecision -State @{ Commit = $commit.Commit; Subject = $commit.Subject } -Question $question).answers.updateType
    [pscustomobject]@{ Type = $answer.choice; Confidence = [math]::Round([double]$answer.confidence, 2); Commit = $commit.Commit; Subject = $commit.Subject }
}

# Print yesterday's work grouped by the selected outcome.
Write-Host "YESTERDAY (last $Days day(s))" -ForegroundColor Cyan
if (@($updates).Count -eq 0) { Write-Host 'No commits found in this period.' }
else {
    foreach ($type in 'delivery', 'reliability', 'exploration', 'internal') {
        $items = @($updates | Where-Object Type -eq $type)
        if ($items.Count -eq 0) { continue }
        Write-Host "`n$($type.ToUpperInvariant())"
        $items | Sort-Object Confidence -Descending | Format-Table Confidence, Commit, Subject -Wrap
    }
}

# Show the repository status separately from model-classified commit subjects.
Write-Host "`nWORKING TREE (possible work in progress)" -ForegroundColor Cyan
if ($workingTree.Count -eq 0) { Write-Host 'Clean.' } else { $workingTree }

# Include user-provided plan and blocker details without sending them to the API.
Write-Host "`nTODAY (supplied by you)" -ForegroundColor Cyan
if ($Today.Count -eq 0) { Write-Host 'No plan supplied.' } else { $Today | ForEach-Object { "- $_" } }
Write-Host "`nBLOCKERS (supplied by you)" -ForegroundColor Cyan
if ($Blockers.Count -eq 0) { Write-Host 'None supplied.' } else { $Blockers | ForEach-Object { "- $_" } }
