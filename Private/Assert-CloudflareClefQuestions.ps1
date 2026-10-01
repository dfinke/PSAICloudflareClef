# Validate the named question map against Cloudflare Clef's documented input contract.
function Assert-CloudflareClefQuestions {
    <#
    .SYNOPSIS
        Validates named typed questions before a Cloudflare Clef request.
    .DESCRIPTION
        Enforces the documented question count, key syntax, question types,
        instructions, and choice or score criteria shapes and limits.
    .PARAMETER Questions
        The named question dictionary to validate.
    #>
    [CmdletBinding()]
    param (
        # Receive the request's named question map.
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Questions
    )

    # Require Cloudflare's documented range of one to 64 questions.
    if ($Questions.Count -lt 1 -or $Questions.Count -gt 64) {
        throw [System.ArgumentException]::new('Questions must contain between 1 and 64 named questions.', 'Questions')
    }

    # Validate each question name and its typed definition.
    foreach ($name in $Questions.Keys) {
        # Convert the key once so validation and error text use the same value.
        $questionName = [string] $name
        if ($questionName.Length -gt 100 -or $questionName -notmatch '^[A-Za-z0-9_.-]+$') {
            throw [System.ArgumentException]::new("Question ID '$questionName' must use only letters, digits, underscore, period, or hyphen and be at most 100 characters.", 'Questions')
        }

        # Require each definition to be a dictionary.
        $question = $Questions[$name]
        if ($question -isnot [System.Collections.IDictionary]) {
            throw [System.ArgumentException]::new("Question '$questionName' must be a dictionary with type and instructions fields.", 'Questions')
        }

        # Accept only the three System One typed question kinds.
        if (-not $question.Contains('type') -or [string] $question.type -notin @('noul', 'choice', 'score')) {
            throw [System.ArgumentException]::new("Question '$questionName' type must be noul, choice, or score.", 'Questions')
        }

        # Require useful instructions for every question type.
        if (-not $question.Contains('instructions') -or [string]::IsNullOrWhiteSpace([string] $question.instructions)) {
            throw [System.ArgumentException]::new("Question '$questionName' must include non-empty instructions.", 'Questions')
        }

        # Validate choice options as a non-empty named dictionary of at most 255 entries.
        if ($question.type -eq 'choice') {
            if (-not $question.Contains('criteria') -or $question.criteria -isnot [System.Collections.IDictionary] -or $question.criteria.Count -lt 1 -or $question.criteria.Count -gt 255) {
                throw [System.ArgumentException]::new("Choice question '$questionName' requires 1 to 255 named criteria options.", 'Questions')
            }
        }

        # Validate score criteria as an ordered list of two to ten rubric levels.
        if ($question.type -eq 'score') {
            if (-not $question.Contains('criteria') -or $question.criteria -isnot [System.Array] -or $question.criteria.Count -lt 2 -or $question.criteria.Count -gt 10) {
                throw [System.ArgumentException]::new("Score question '$questionName' requires an ordered array of 2 to 10 rubric levels.", 'Questions')
            }
        }
    }
}
