# Create a PowerShell-friendly typed question object for the Clef request.
function New-CloudflareClefQuestion {
    <#
    .SYNOPSIS
        Creates a named Noul, Choice, or Score question for Cloudflare Clef.
    .DESCRIPTION
        The returned object can be supplied to Invoke-CloudflareClefDecision
        through its Question parameter. The Name becomes a request-map key.
    .PARAMETER Name
        The response and request identifier for this question.
    .PARAMETER Type
        The typed question kind: Noul, Choice, or Score.
    .PARAMETER Instructions
        The question's natural-language instructions.
    .PARAMETER Criteria
        A named option map for Choice, or an ordered rubric array for Score.
    .EXAMPLE
        New-CloudflareClefQuestion -Name route -Type Choice -Instructions 'Which team owns this?' -Criteria @{ support = 'Customer issue'; billing = 'Invoice issue' }
    #>
    [CmdletBinding()]
    param (
        # Require an API question identifier.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        # Constrain the question to one of the documented typed answers.
        [Parameter(Mandatory)]
        [ValidateSet('Noul', 'Choice', 'Score')]
        [string] $Type,

        # Require an instruction string that tells Clef what to decide.
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Instructions,

        # Accept the criteria container required by Choice and Score questions.
        [Parameter()]
        [AllowNull()]
        [object] $Criteria
    )

    # Build a wire-compatible question map and reuse the common full validation.
    $definition = [ordered]@{ type = $Type.ToLowerInvariant(); instructions = $Instructions }
    if ($null -ne $Criteria) { $definition.criteria = $Criteria }
    $candidate = @{ $Name = $definition }
    Assert-CloudflareClefQuestions -Questions $candidate

    # Return a typed object that preserves the caller's criteria object.
    return [pscustomobject][ordered]@{ Name = $Name; Type = $Type; Instructions = $Instructions; Criteria = $Criteria }
}
