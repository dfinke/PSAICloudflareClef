# Require PowerShell 7 and ImportExcel for workbook input and output.
#requires -Version 7.0
#requires -Modules ImportExcel

# Read an editable deal workbook and write a separate recommendation workbook.
[CmdletBinding()]
param(
    # Set this to a workbook containing a Deal sheet with Field and Value columns.
    [string] $Path = (Join-Path $PSScriptRoot '..' 'data' 'DealDesk.xlsx'),

    # Choose a new output path for the recommendation and calculated options.
    [string] $OutputPath
)

# Import the Cloudflare Clef module from this repository.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Confirm the input workbook exists before reading it.
if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Deal workbook not found: $Path" }
$sourcePath = (Resolve-Path -LiteralPath $Path).Path

# Choose a timestamped review workbook when the caller did not provide an output path.
if (-not $OutputPath) {
    $directory = Split-Path -Path $sourcePath -Parent
    $name = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $OutputPath = Join-Path $directory "$name-review-$stamp.xlsx"
}
$reviewPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)

# Prevent overwriting the source or an existing workbook.
if ([string]::Equals($sourcePath, $reviewPath, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath must differ from the deal workbook.' }
if (Test-Path -LiteralPath $reviewPath) { throw "Review workbook already exists: $reviewPath. Choose a new OutputPath." }

# Read the field/value rows into a case-insensitive PowerShell map.
$deal = @{}
foreach ($row in Import-Excel -Path $sourcePath -WorksheetName Deal) {
    $fieldName = [string] $row.Field
    if ([string]::IsNullOrWhiteSpace($fieldName)) { continue }
    if ($deal.ContainsKey($fieldName)) { throw "Duplicate deal field: $fieldName" }
    $deal[$fieldName] = $row.Value
}

# Require the input fields used to calculate the options and describe the buyer context.
$required = @('Customer', 'Product', 'Units', 'AnnualListPricePerUnit', 'AnnualCostPerUnit', 'CurrentDiscountPct', 'RequestedDiscountPct', 'MinimumGrossMarginPct', 'TermMonths', 'TargetAnnualBudget', 'BuyerNotes', 'SalesGoal')
foreach ($name in $required) {
    if (-not $deal.ContainsKey($name) -or [string]::IsNullOrWhiteSpace([string]$deal[$name])) { throw "Deal sheet is missing a value for $name." }
}

# Convert numeric inputs and reject values that cannot support the calculations.
try {
    $units = [int]$deal.Units
    $listPrice = [decimal]$deal.AnnualListPricePerUnit
    $unitCost = [decimal]$deal.AnnualCostPerUnit
    $currentDiscount = [decimal]$deal.CurrentDiscountPct
    $requestedDiscount = [decimal]$deal.RequestedDiscountPct
    $minimumMargin = [decimal]$deal.MinimumGrossMarginPct
    $termMonths = [int]$deal.TermMonths
    $budget = [decimal]$deal.TargetAnnualBudget
}
catch { throw "Deal sheet contains an invalid number: $_" }
if ($units -le 0 -or $listPrice -le 0 -or $unitCost -lt 0 -or $termMonths -le 0 -or $budget -le 0) { throw 'Units, list price, term, and budget must be positive; unit cost cannot be negative.' }
if ($currentDiscount -lt 0 -or $currentDiscount -ge 100 -or $requestedDiscount -lt 0 -or $requestedDiscount -ge 100 -or $minimumMargin -lt 0 -or $minimumMargin -ge 100) { throw 'Discounts and minimum margin must be percentages from 0 up to (but not including) 100.' }

# Calculate the same five candidate moves in PowerShell so the API selects among measured facts.
$moves = @(
    [pscustomobject]@{ Code = 'hold'; Move = 'Hold the current offer'; Units = $units; DiscountPct = $currentDiscount; TermMonths = $termMonths; Trade = 'No new concession; explain the value of the current offer.' }
    [pscustomobject]@{ Code = 'direct'; Move = 'Meet the requested discount'; Units = $units; DiscountPct = $requestedDiscount; TermMonths = $termMonths; Trade = 'Give the requested discount without asking for a commitment.' }
    [pscustomobject]@{ Code = 'term'; Move = 'Trade discount for a longer term'; Units = $units; DiscountPct = $requestedDiscount; TermMonths = [math]::Max(24, $termMonths + 12); Trade = 'Offer the requested discount in return for a longer commitment.' }
    [pscustomobject]@{ Code = 'volume'; Move = 'Trade discount for more units'; Units = [int][math]::Ceiling($units * 1.25); DiscountPct = $requestedDiscount; TermMonths = $termMonths; Trade = 'Offer the requested discount if the buyer increases quantity by 25%.' }
    [pscustomobject]@{ Code = 'scope'; Move = 'Reduce scope to fit the budget'; Units = [int][math]::Max(1, [math]::Floor($units * 0.75)); DiscountPct = $currentDiscount; TermMonths = $termMonths; Trade = 'Keep the current discount and offer 25% fewer units.' }
)
$options = foreach ($move in $moves) {
    $annualRevenue = [decimal]$move.Units * $listPrice * (1 - [decimal]$move.DiscountPct / 100)
    $annualCost = [decimal]$move.Units * $unitCost
    $annualProfit = $annualRevenue - $annualCost
    $marginPct = if ($annualRevenue -gt 0) { 100 * $annualProfit / $annualRevenue } else { 0 }
    [pscustomobject][ordered]@{
        Code = $move.Code; Move = $move.Move; Units = $move.Units; DiscountPct = $move.DiscountPct
        TermMonths = $move.TermMonths; AnnualRevenue = [math]::Round($annualRevenue, 2)
        AnnualGrossProfit = [math]::Round($annualProfit, 2); GrossMarginPct = [math]::Round($marginPct, 2)
        MeetsMarginFloor = $marginPct -ge $minimumMargin; MeetsBuyerBudget = $annualRevenue -le $budget; Trade = $move.Trade
    }
}

# Offer only moves that meet the calculated budget and margin constraints, plus a human-review option.
$eligible = @($options | Where-Object { $_.MeetsMarginFloor -and $_.MeetsBuyerBudget })
$criteria = [ordered]@{}
foreach ($option in $eligible) {
    $criteria[$option.Code] = "$($option.Move). $($option.Trade) Annual revenue $($option.AnnualRevenue); gross profit $($option.AnnualGrossProfit); margin $($option.GrossMarginPct)%"
}
$criteria['review'] = 'Pause for human review when none of the available moves fits the buyer context or sales goal.'

# Ask Cloudflare Clef to choose among feasible moves using buyer context and sales goals.
$question = New-CloudflareClefQuestion -Name move -Type Choice `
    -Instructions 'Choose the best next negotiation move for this deal from the supplied options. Use the buyer notes and sales goal. Prefer a move the buyer could realistically accept while preserving seller value. Budget and margin figures are calculated facts. Do not assume a longer term or more units is acceptable unless the buyer context supports it. Choose review if the supplied moves do not fit. Do not invent a different move.' `
    -Criteria $criteria
$state = @{
    Customer = [string]$deal.Customer; Product = [string]$deal.Product
    BuyerNotes = [string]$deal.BuyerNotes; SalesGoal = [string]$deal.SalesGoal
    TargetAnnualBudget = $budget; CurrentTermMonths = $termMonths; Options = $eligible
}
$response = Invoke-CloudflareClefDecision -State $state -Question $question

# Validate the selected identifier and join it back to the calculated option.
$chosenCode = [string]$response.answers.move.choice
if ($chosenCode -notin @($criteria.Keys)) { throw "Cloudflare Clef returned a move that was not offered: $chosenCode" }
$chosen = $options | Where-Object Code -eq $chosenCode | Select-Object -First 1
$recommendation = [pscustomobject][ordered]@{
    Customer = [string]$deal.Customer; Product = [string]$deal.Product
    RecommendedMove = if ($chosen) { $chosen.Move } else { 'Pause for human review' }
    Confidence = [math]::Round([double]$response.answers.move.confidence, 2)
    Trade = if ($chosen) { $chosen.Trade } else { 'Review the deal and buyer constraints before quoting.' }
    BuyerNotes = [string]$deal.BuyerNotes; SalesGoal = [string]$deal.SalesGoal
    MinimumGrossMarginPct = $minimumMargin; TargetAnnualBudget = $budget
}

# Save the recommendation and every calculated option in separate workbook sheets.
$recommendationRows = foreach ($property in $recommendation.PSObject.Properties) { [pscustomobject]@{ Field = $property.Name; Value = $property.Value } }
$reviewOptions = @($options | Select-Object *, @{ Name = 'Recommended'; Expression = { $_.Code -eq $chosenCode } })
$recommendationRows | Export-Excel -Path $reviewPath -WorksheetName Recommendation -AutoSize -BoldTopRow -FreezeTopRow -TableName DealRecommendation
$reviewOptions | Export-Excel -Path $reviewPath -WorksheetName Options -AutoSize -BoldTopRow -FreezeTopRow -TableName DealOptions

# Display the recommendation, output path, and option comparison for review.
Write-Host "Recommended move: $($recommendation.RecommendedMove) (confidence $($recommendation.Confidence))" -ForegroundColor Cyan
Write-Host "Review workbook: $reviewPath" -ForegroundColor Cyan
$reviewOptions | Format-Table Move, Units, DiscountPct, TermMonths, AnnualRevenue, GrossMarginPct, MeetsBuyerBudget, MeetsMarginFloor, Recommended -AutoSize
[pscustomobject]@{ Path = $reviewPath; Recommendation = $recommendation; Options = $reviewOptions }
