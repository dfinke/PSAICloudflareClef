# Convert an HTTP exception into a safe diagnostic message without exposing credentials.
function Get-CloudflareClefHttpErrorMessage {
    <#
    .SYNOPSIS
        Builds a concise HTTP or transport error message.
    .DESCRIPTION
        Includes the HTTP status and Cloudflare response body when available,
        and deliberately excludes request headers and request content.
    .PARAMETER ErrorRecord
        The error record thrown by Invoke-RestMethod.
    #>
    [CmdletBinding()]
    param (
        # Inspect the request failure supplied by the public command.
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    # Start with a generic message for transport failures without an HTTP response.
    $message = 'Cloudflare Clef request failed.'
    $exception = $ErrorRecord.Exception
    $statusCode = $null
    $responseText = $null

    # Read status and content from modern PowerShell HTTP exceptions where exposed.
    if ($null -ne $exception.Response) {
        try {
            $statusCode = [int] $exception.Response.StatusCode
        }
        catch {
            # Keep status absent when the response implementation has no readable code.
        }
        try {
            if ($exception.Response.Content -and $exception.Response.Content.PSObject.Methods['ReadAsStringAsync']) {
                $responseText = $exception.Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            elseif ($exception.Response.GetResponseStream) {
                $reader = [System.IO.StreamReader]::new($exception.Response.GetResponseStream())
                try { $responseText = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
        }
        catch {
            # Keep the diagnostic useful even when response content cannot be read.
        }
    }

    # Read legacy WebException response data when that is the available response form.
    if ($null -eq $statusCode -and $exception -is [System.Net.WebException] -and $null -ne $exception.Response) {
        try {
            $statusCode = [int] $exception.Response.StatusCode
            $reader = [System.IO.StreamReader]::new($exception.Response.GetResponseStream())
            try { $responseText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        }
        catch {
            # Preserve the transport message when a legacy response is unavailable.
        }
    }

    # Prefer sanitized status and API response details over internal exception text.
    if ($null -ne $statusCode) {
        $message = "Cloudflare Clef request failed with HTTP $statusCode."
    }
    elseif (-not [string]::IsNullOrWhiteSpace($exception.Message)) {
        $message = "Cloudflare Clef request failed: $($exception.Message)"
    }
    if (-not [string]::IsNullOrWhiteSpace($responseText)) {
        $message += " Response: $responseText"
    }

    # Return the safe text so the caller can throw a terminating error.
    return $message
}
