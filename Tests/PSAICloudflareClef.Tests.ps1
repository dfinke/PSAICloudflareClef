# Import the module and define request fixtures while replacing the HTTP boundary with a mock.
BeforeAll {
    # Resolve the module manifest from this repository's test folder.
    $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'PSAICloudflareClef.psd1'

    # Import the module under test into the Pester session.
    Import-Module $modulePath -Force

    # Use fake credentials that are only inspected by the mock.
    $testToken = 'offline-test-token'
    $testAccount = 'account-123'

    # Define representative context and all three documented typed question kinds.
    $testState = @{ incident = 'Checkout returns 503.' }
    $testQuestions = [ordered]@{
        urgent = @{ type = 'noul'; instructions = 'Is this urgent?' }
        owner = @{ type = 'choice'; instructions = 'Which team owns this?'; criteria = @{ support = 'Customer issue'; billing = 'Invoice issue' } }
        severity = @{ type = 'score'; instructions = 'How severe is the impact?'; criteria = @('Minor', 'Major', 'Critical') }
    }
}

# Exercise request building, helper conversion, input validation, and safe failures entirely offline.
Describe 'Invoke-CloudflareClefDecision' {
    # Provide a representative parsed API response for all tests unless a case replaces it.
    BeforeEach {
        Mock Invoke-RestMethod -ModuleName PSAICloudflareClef {
            [pscustomobject]@{ success = $true; result = [pscustomobject]@{ model = 'clef' }; answers = [pscustomobject]@{ urgent = [pscustomobject]@{ noul = 0.93 }; owner = [pscustomobject]@{ choice = 'support' }; severity = [pscustomobject]@{ score = 1.7 } } }
        }
    }

    # Verify the URL, authorization, timeout, JSON request fields, and typed questions.
    It 'posts the Clef payload and returns the parsed response' {
        $response = Invoke-CloudflareClefDecision -State $testState -Questions $testQuestions -AccountId $testAccount -Token $testToken -TimeoutSec 45
        $response.answers.urgent.noul | Should -Be 0.93
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 1 -ParameterFilter {
            $Uri -eq 'https://api.cloudflare.com/client/v4/accounts/account-123/ai/run/@cf/cloudflare/clef' -and
            $Method -eq 'Post' -and $Headers.Authorization -eq 'Bearer offline-test-token' -and
            $ContentType -eq 'application/json' -and $TimeoutSec -eq 45 -and
            (($Body | ConvertFrom-Json).model -eq 'clef') -and
            (($Body | ConvertFrom-Json).questions.owner.type -eq 'choice') -and
            (($Body | ConvertFrom-Json).questions.severity.criteria[2] -eq 'Critical')
        }
    }

    # Verify that helper objects become exactly the named API question shape.
    It 'converts helper-created typed questions' {
        $questions = @(
            New-CloudflareClefQuestion -Name urgent -Type Noul -Instructions 'Should this be escalated?'
            New-CloudflareClefQuestion -Name category -Type Choice -Instructions 'Which category?' -Criteria @{ bug = 'A software issue'; request = 'A feature request' }
            New-CloudflareClefQuestion -Name severity -Type Score -Instructions 'How severe?' -Criteria @('Low', 'High')
        )
        $null = Invoke-CloudflareClefDecision -State $testState -Question $questions -AccountId $testAccount -Token $testToken
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 1 -ParameterFilter {
            $payload = $Body | ConvertFrom-Json
            $payload.questions.urgent.type -eq 'noul' -and $payload.questions.urgent.instructions -eq 'Should this be escalated?' -and
            $payload.questions.category.type -eq 'choice' -and $payload.questions.category.criteria.bug -eq 'A software issue' -and
            $payload.questions.severity.type -eq 'score' -and $payload.questions.severity.criteria[1] -eq 'High'
        }
    }

    # Verify the Flash selection changes both the URL path and model field.
    It 'supports the documented Clef Flash model option' {
        $null = Invoke-CloudflareClefDecision -State $testState -Questions @{ urgent = @{ type = 'noul'; instructions = 'Urgent?' } } -AccountId $testAccount -Token $testToken -Model ClefFlash
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 1 -ParameterFilter {
            $Uri -like '*/@cf/cloudflare/clef-flash' -and (($Body | ConvertFrom-Json).model -eq 'clef-flash')
        }
    }

    # Reject malformed question IDs, unsupported types, and excess counts before HTTP.
    It 'rejects invalid question identifiers before HTTP' {
        { Invoke-CloudflareClefDecision -State $testState -Questions @{ 'bad id' = @{ type = 'noul'; instructions = 'Valid?' } } -AccountId $testAccount -Token $testToken } | Should -Throw '*Question ID*'
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 0
    }

    # Reject invalid criteria containers to prevent sending malformed typed answers.
    It 'rejects invalid choice and score criteria before HTTP' {
        { Invoke-CloudflareClefDecision -State $testState -Questions @{ choose = @{ type = 'choice'; instructions = 'Pick'; criteria = @('one') } } -AccountId $testAccount -Token $testToken } | Should -Throw '*Choice question*'
        { Invoke-CloudflareClefDecision -State $testState -Questions @{ rate = @{ type = 'score'; instructions = 'Rate'; criteria = @('only one') } } -AccountId $testAccount -Token $testToken } | Should -Throw '*Score question*'
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 0
    }

    # Verify an embedded PNG data URI is retained in the request JSON.
    It 'includes valid embedded images and rejects remote image URLs' {
        $pngData = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lN8AAAAASUVORK5CYII='
        $dataUri = "data:image/png;base64,$pngData"
        $null = Invoke-CloudflareClefDecision -State 'What is visible?' -Questions @{ scene = @{ type = 'noul'; instructions = 'Is a person visible?' } } -AccountId $testAccount -Token $testToken -Image $dataUri
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 1 -ParameterFilter { (($Body | ConvertFrom-Json).images[0] -like 'data:image/png;base64,*') }
        { Invoke-CloudflareClefDecision -State 'Check this' -Questions @{ q = @{ type = 'noul'; instructions = 'Yes?' } } -AccountId $testAccount -Token $testToken -Image 'https://example.com/image.png' } | Should -Throw '*embedded base64*'
    }

    # Confirm that missing credentials stop before any mocked HTTP call.
    It 'requires a token and account ID before HTTP' {
        { Invoke-CloudflareClefDecision -State $testState -Questions $testQuestions -AccountId '' -Token $testToken } | Should -Throw '*AccountId is required*'
        { Invoke-CloudflareClefDecision -State $testState -Questions $testQuestions -AccountId $testAccount -Token '' } | Should -Throw '*API token is required*'
        Should -Invoke Invoke-RestMethod -ModuleName PSAICloudflareClef -Times 0
    }

    # Simulate a 400 response and verify its status and body reach callers safely.
    It 'includes useful HTTP status and response details' {
        Mock Invoke-RestMethod -ModuleName PSAICloudflareClef {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)
            $response.Content = [System.Net.Http.StringContent]::new('{"error":"invalid request"}')
            $exception = [System.Net.Http.HttpRequestException]::new('Bad request')
            $exception | Add-Member -MemberType NoteProperty -Name Response -Value $response -Force
            throw $exception
        }
        { Invoke-CloudflareClefDecision -State $testState -Questions $testQuestions -AccountId $testAccount -Token $testToken } | Should -Throw '*HTTP 400*invalid request*'
    }
}
