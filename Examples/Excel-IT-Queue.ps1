# Require PowerShell 7 and ImportExcel to read the sample workbook.
#requires -Version 7.0
#requires -Modules ImportExcel

# Accept a workbook path, defaulting to the example ticket queue included with this repository.
[CmdletBinding()]
param(
    # Point to a workbook with an IT Queue worksheet and ticket context columns.
    [string] $Path = (Join-Path $PSScriptRoot '..' 'data' 'IT-Operations-Queue.xlsx')
)

# Import this standalone provider module from the repository root.
Import-Module (Join-Path $PSScriptRoot '..' 'PSAICloudflareClef.psd1') -Force

# Read the request records from the supplied workbook.
$tickets = @(Import-Excel -Path $Path -WorksheetName 'IT Queue')
if ($tickets.Count -eq 0) { throw "No tickets were found in '$Path'." }

# Ask Clef whether waiting on each request could disrupt a time-sensitive process.
$question = New-CloudflareClefQuestion -Name investigateToday -Type Noul `
    -Instructions 'Should IT investigate this request today because waiting could disrupt a time-sensitive business process? Consider the service, users affected, deadline, and request description.'

# Evaluate each ticket independently and keep its original workbook details for review.
$results = foreach ($ticket in $tickets) {
    $state = [ordered]@{}
    foreach ($property in $ticket.PSObject.Properties) { $state[$property.Name] = $property.Value }
    $probability = [double](Invoke-CloudflareClefDecision -State $state -Question $question).answers.investigateToday.noul
    [pscustomobject]@{
        Ticket = $ticket.Ticket
        Service = $ticket.Service
        UsersAffected = $ticket.UsersAffected
        Deadline = $ticket.Deadline
        InvestigateTodayProbability = [math]::Round($probability, 3)
    }
}

# Rank the queue by the model's probability so an operator can review the top candidates.
$results | Sort-Object InvestigateTodayProbability -Descending | Format-Table Ticket, Service, UsersAffected, Deadline, InvestigateTodayProbability -AutoSize -Wrap
