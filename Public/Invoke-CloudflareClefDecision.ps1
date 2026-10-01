# Send typed decision questions to the Cloudflare Workers AI Clef REST endpoint.
function Invoke-CloudflareClefDecision {
    <#
    .SYNOPSIS
        Runs named typed decisions using Cloudflare Workers AI Clef.
    .DESCRIPTION
        Posts model, state, questions, and optional embedded images to the
        account-scoped Workers AI REST endpoint. The token comes from the
        CLOUDFLARE_API_TOKEN environment variable unless Token is supplied.
    .PARAMETER State
        Text or structured JSON-compatible context to evaluate.
    .PARAMETER Questions
        A named map of API-shaped noul, choice, and score questions.
    .PARAMETER Question
        One or more questions returned by New-CloudflareClefQuestion.
    .PARAMETER AccountId
        The Cloudflare account identifier; defaults to CLOUDFLARE_ACCOUNT_ID.
    .PARAMETER Token
        Optional Cloudflare API token; defaults to CLOUDFLARE_API_TOKEN.
    .PARAMETER Model
        Clef or ClefFlash. Clef is the default model.
    .PARAMETER Image
        One to four embedded image data URIs or raw base64 PNG, JPEG, or WebP values.
    .PARAMETER TimeoutSec
        Request timeout in seconds, from 1 through 600.
    .EXAMPLE
        $questions = New-CloudflareClefQuestion -Name urgent -Type Noul -Instructions 'Is this incident urgent?'
        Invoke-CloudflareClefDecision -State @{ incident = 'Checkout returns 503.' } -Question $questions
    .EXAMPLE
        Invoke-CloudflareClefDecision -State 'Classify this screenshot.' -Questions $questions -Image $imageDataUri -Model ClefFlash
    #>
    [CmdletBinding(DefaultParameterSetName = 'QuestionMap')]
    param (
        # Require structured or textual decision context.
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNull()]
        [object] $State,

        # Accept questions already arranged in the Cloudflare request schema.
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'QuestionMap')]
        [ValidateNotNull()]
        [System.Collections.IDictionary] $Questions,

        # Accept helper-created typed question objects.
        [Parameter(Mandatory, Position = 1, ParameterSetName = 'QuestionObjects')]
        [ValidateNotNullOrEmpty()]
        [object[]] $Question,

        # Permit an explicit account ID or use the documented environment setting.
        [Parameter()]
        [AllowEmptyString()]
        [string] $AccountId = $env:CLOUDFLARE_ACCOUNT_ID,

        # Permit a token parameter for secret stores while supporting environment configuration.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Token = $env:CLOUDFLARE_API_TOKEN,

        # Select either documented model while defaulting to the primary Clef model.
        [Parameter()]
        [ValidateSet('Clef', 'ClefFlash')]
        [string] $Model = 'Clef',

        # Accept only inline embedded image data; remote URLs are not part of the Clef contract.
        [Parameter()]
        [ValidateCount(1, 4)]
        [string[]] $Image,

        # Bound network duration to a practical timeout window.
        [Parameter()]
        [ValidateRange(1, 600)]
        [int] $TimeoutSec = 30
    )

    # Fail early when required Cloudflare account configuration is unavailable.
    if ([string]::IsNullOrWhiteSpace($AccountId)) {
        throw [System.InvalidOperationException]::new('AccountId is required. Pass -AccountId or set CLOUDFLARE_ACCOUNT_ID.')
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        throw [System.InvalidOperationException]::new('A Cloudflare API token is required. Pass -Token or set CLOUDFLARE_API_TOKEN.')
    }

    # Convert helper objects to the API's named question dictionary.
    if ($PSCmdlet.ParameterSetName -eq 'QuestionObjects') {
        $Questions = [ordered]@{}
        foreach ($item in $Question) {
            if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string] $item.Name)) {
                throw [System.ArgumentException]::new('Every Question object must have a non-empty Name.', 'Question')
            }
            if ($Questions.Contains([string] $item.Name)) {
                throw [System.ArgumentException]::new("Question name '$($item.Name)' is duplicated.", 'Question')
            }
            $definition = [ordered]@{ type = ([string] $item.Type).ToLowerInvariant(); instructions = [string] $item.Instructions }
            if ($null -ne $item.Criteria) { $definition.criteria = $item.Criteria }
            $Questions[[string] $item.Name] = $definition
        }
    }

    # Validate the named schema before serialization or network activity.
    Assert-CloudflareClefQuestions -Questions $Questions

    # Validate each inline image's encoding and documented byte limits.
    $imagePayloads = @()
    $totalImageBytes = 0
    foreach ($imageValue in $Image) {
        # Parse an optional MIME-bearing data URI, otherwise infer type from base64 file signatures.
        $mimeType = $null
        $base64 = $imageValue
        if ($imageValue -match '^data:(image/(?:png|jpeg|webp));base64,(.+)$') {
            $mimeType = $Matches[1]
            $base64 = $Matches[2]
        }
        try {
            $imageBytes = [Convert]::FromBase64String($base64)
        }
        catch {
            throw [System.ArgumentException]::new('Image values must be valid embedded base64 data or data:image/png, data:image/jpeg, or data:image/webp URIs.', 'Image')
        }
        if ($imageBytes.Length -eq 0 -or $imageBytes.Length -gt 4MB) {
            throw [System.ArgumentException]::new('Each image must be non-empty and no larger than 4 MiB decoded.', 'Image')
        }
        if ($null -eq $mimeType) {
            if ($imageBytes.Length -ge 8 -and [BitConverter]::ToString($imageBytes, 0, 8) -eq '89-50-4E-47-0D-0A-1A-0A') { $mimeType = 'image/png' }
            elseif ($imageBytes.Length -ge 3 -and [BitConverter]::ToString($imageBytes, 0, 3) -eq 'FF-D8-FF') { $mimeType = 'image/jpeg' }
            elseif ($imageBytes.Length -ge 12 -and [Text.Encoding]::ASCII.GetString($imageBytes, 0, 4) -eq 'RIFF' -and [Text.Encoding]::ASCII.GetString($imageBytes, 8, 4) -eq 'WEBP') { $mimeType = 'image/webp' }
            else { throw [System.ArgumentException]::new('Raw base64 image data must contain a PNG, JPEG, or WebP image.', 'Image') }
        }
        $totalImageBytes += $imageBytes.Length
        if ($totalImageBytes -gt 8MB) {
            throw [System.ArgumentException]::new('The combined decoded image data cannot exceed 8 MiB.', 'Image')
        }
        $imagePayloads += "data:$mimeType;base64,$([Convert]::ToBase64String($imageBytes))"
    }

    # Build the model selector and endpoint from the single validated model value.
    $modelName = if ($Model -eq 'ClefFlash') { 'clef-flash' } else { 'clef' }
    $modelPath = if ($Model -eq 'ClefFlash') { '@cf/cloudflare/clef-flash' } else { '@cf/cloudflare/clef' }
    $escapedAccountId = [uri]::EscapeDataString($AccountId)
    $uri = "https://api.cloudflare.com/client/v4/accounts/$escapedAccountId/ai/run/$modelPath"

    # Create only the fields documented by the Clef request schema.
    $payload = [ordered]@{ model = $modelName; state = $State; questions = $Questions }
    if ($imagePayloads.Count -gt 0) { $payload.images = @($imagePayloads) }
    $requestBody = ConvertTo-Json -InputObject $payload -Depth 100 -Compress

    # Enforce the model page's 13 MiB whole-request limit after JSON encoding.
    if ([Text.Encoding]::UTF8.GetByteCount($requestBody) -gt 13MB) {
        throw [System.ArgumentException]::new('The serialized request body cannot exceed 13 MiB.', 'State')
    }

    # Build bearer authentication in memory without printing or logging the token.
    $headers = @{ Authorization = "Bearer $Token" }

    # Submit one JSON POST and translate HTTP or transport failures into useful safe errors.
    try {
        # Capture the standard Cloudflare REST envelope so callers receive model output directly.
        $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -ContentType 'application/json' -Body $requestBody -TimeoutSec $TimeoutSec -ErrorAction Stop
        if ($null -ne $response -and $null -ne $response.result) {
            return $response.result
        }
        return $response
    }
    catch {
        # Do not surface request data or authorization headers in error messages.
        throw [System.InvalidOperationException]::new((Get-CloudflareClefHttpErrorMessage -ErrorRecord $_), $_.Exception)
    }
}
