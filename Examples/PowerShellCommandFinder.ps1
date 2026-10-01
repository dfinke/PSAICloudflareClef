# Require the modern PowerShell runtime used by these runnable examples.
#requires -Version 7.0

# Describe the task and limit the number of local candidates sent as context.
[CmdletBinding()]
param(
    # State the PowerShell task in plain language.
    [Parameter(Mandatory = $true)]
    [string] $Task,

    # Keep the candidate list within the documented choice option maximum.
    [ValidateRange(3, 25)]
    [int] $CandidateCount = 12
)

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Remove common words so local command metadata search favors task-specific terms.
$stopWords = @('the', 'and', 'for', 'with', 'from', 'that', 'this', 'into', 'using', 'use', 'find', 'get', 'show', 'list', 'all', 'how', 'can', 'want', 'need', 'please', 'powershell')
$terms = @([regex]::Matches($Task.ToLowerInvariant(), '[a-z0-9]{3,}') | ForEach-Object Value | Where-Object { $_ -notin $stopWords } | Sort-Object -Unique)
if ($terms.Count -eq 0) { throw 'Describe what you want to do with a few specific words.' }

# Search locally installed cmdlets and functions without executing candidate commands.
$candidates = foreach ($command in Get-Command -CommandType Cmdlet, Function -ErrorAction SilentlyContinue) {
    $help = Get-Help -Name $command.Name -ErrorAction SilentlyContinue
    $synopsis = [string] $help.Synopsis
    if ([string]::IsNullOrWhiteSpace($synopsis)) {
        $synopsis = [string] $command.Definition
        if ($synopsis.Length -gt 240) { $synopsis = $synopsis.Substring(0, 240) }
    }
    $searchText = "$($command.Name) $synopsis".ToLowerInvariant()
    $matchCount = @($terms | Where-Object { $searchText.Contains($_) }).Count
    if ($matchCount -gt 0) {
        [pscustomobject]@{ Name = $command.Name; CommandType = [string]$command.CommandType; Module = [string]$command.Source; Synopsis = $synopsis; MatchCount = $matchCount }
    }
}

# Rank the local candidates and reject an empty local search before making an API call.
$candidates = @($candidates | Sort-Object -Property @{ Expression = 'MatchCount'; Descending = $true }, Name | Select-Object -First $CandidateCount)
if ($candidates.Count -eq 0) { throw 'No local commands matched. Import the relevant module or use words from local command help.' }

# Present only the candidate names as option identifiers with their local help summaries.
$criteria = [ordered]@{}
foreach ($candidate in $candidates) {
    $criteria[$candidate.Name] = "[$($candidate.CommandType); module: $($candidate.Module)] $($candidate.Synopsis)"
}

# Ask the model to select one candidate; no suggested command is run by this script.
$question = New-CloudflareClefQuestion -Name command -Type Choice `
    -Instructions "Choose the single PowerShell command that best fits this task: $Task. Choose only from the supplied candidates. Prefer a command that directly accomplishes the task; do not infer that the command should be run." `
    -Criteria $criteria
$state = @{
    Task       = $Task
    Candidates = @($candidates | Select-Object Name, CommandType, Module, Synopsis)
}
$response = Invoke-CloudflareClefDecision -State $state -Question $question

# Verify the selected option against the offered local candidates before showing help.
$answer = $response.answers.command
$selected = $candidates | Where-Object Name -eq $answer.choice | Select-Object -First 1
Write-Host "Task: $Task" -ForegroundColor Cyan
if ($null -eq $selected) {
    Write-Warning 'The API choice did not match a supplied candidate.'
    $response
    return
}

# Display details and examples for human review; the command is never invoked.
[pscustomobject]@{ Command = $selected.Name; Confidence = [math]::Round([double]$answer.confidence, 2); Module = $selected.Module; Synopsis = $selected.Synopsis }
Write-Host "`nLocal help examples for $($selected.Name) (review before using):" -ForegroundColor Cyan
Get-Help -Name $selected.Name -Examples | Select-Object -ExpandProperty Examples
