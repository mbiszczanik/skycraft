<#
.SYNOPSIS
    Pester 5 tests for the budget helpers of tools/LabCommon.psm1 (issue #411).

.DESCRIPTION
    Az.Billing 2.3.0 sends every Consumption request, Get-AzConsumptionBudget and
    Remove-AzConsumptionBudget included, at api-version 2018-01-31. Current subscriptions refuse
    that version with 422 ("Please use version 2018-12-01-preview or later"), so Lab 1.3's
    cleanup could neither read nor delete its budgets. The lab scripts now go through
    Get-LabArmBudget and Remove-LabArmBudget, which call the Consumption budgets API through
    Invoke-AzRestMethod at 2023-05-01. These tests pin what those helpers send and how they read
    the answer:

      1. A listing sends GET <scope>/providers/Microsoft.Consumption/budgets with api-version
         2023-05-01 and nothing else in the query, for a subscription or a resource group; any
         other scope is refused before anything is sent.
      2. A listing follows nextLink to the last page, and stops with an error on a nextLink it has
         already followed or on a later page that fails.
      3. Each budget comes back with the fields the lab scripts read: Name, Id, Scope, Amount,
         Category, TimeGrain, CurrentSpend and Unit.
      4. A status outside 2xx throws with the status, the error code and the service's message -
         never an empty list - and a 2xx answer that is not a budget list throws too.
      5. A removal sends DELETE <scope>/providers/Microsoft.Consumption/budgets/<name>; 200 and
         204 are success, anything else throws, a 404 included; a name or scope that does not
         fit is refused before anything is sent, and -WhatIf sends nothing.

    No subscription is needed, and none is used: a global function named Invoke-AzRestMethod
    answers in place of the Az.Accounts cmdlet (a function outranks a cmdlet, so it does so with
    Az installed too, and CI has no Az). It records every request and replies from a queue the
    test fills.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-Budget.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #411
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabCommonPath = Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1'
    $script:LabCommon = Import-Module $script:LabCommonPath -Force -PassThru

    $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
    $script:Rg = "$script:Sub/resourceGroups/prod-skycraft-swc-rg"

    # The fake: every request is recorded; the reply is the next queued one.
    $global:SkyCraftBudgetFake = [pscustomobject]@{
        Calls   = [System.Collections.Generic.List[object]]::new()
        Replies = [System.Collections.Generic.Queue[object]]::new()
    }
    function global:Invoke-AzRestMethod {
        [CmdletBinding()]
        param([string]$Path, [string]$Method = 'GET', [string]$Payload)
        $global:SkyCraftBudgetFake.Calls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Payload = $Payload })
        if ($global:SkyCraftBudgetFake.Replies.Count -eq 0) { throw "fake: no reply queued for $Method $Path" }
        $global:SkyCraftBudgetFake.Replies.Dequeue()
    }

    function Reset-BudgetFake {
        param([object[]]$Reply = @())
        $global:SkyCraftBudgetFake.Calls.Clear()
        $global:SkyCraftBudgetFake.Replies.Clear()
        foreach ($item in $Reply) { $global:SkyCraftBudgetFake.Replies.Enqueue($item) }
    }

    function New-ArmReply {
        param([int]$StatusCode = 200, [object]$Body)
        $content = if ($null -eq $Body) { '' } elseif ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        [pscustomobject]@{ StatusCode = $StatusCode; Content = $content }
    }

    # Shaped like a Consumption API budget at 2023-05-01.
    function New-ArmBudget {
        param([string]$Name, [string]$Scope, [double]$Amount = 100, [string]$Unit = 'EUR', [double]$Spend = 12.5)
        [ordered]@{
            id         = "$Scope/providers/Microsoft.Consumption/budgets/$Name"
            name       = $Name
            type       = 'Microsoft.Consumption/budgets'
            eTag       = '"1d0000000000000"'
            properties = [ordered]@{
                timePeriod   = [ordered]@{ startDate = '2026-10-01T00:00:00Z'; endDate = '2027-10-01T00:00:00Z' }
                timeGrain    = 'Monthly'
                amount       = $Amount
                category     = 'Cost'
                currentSpend = [ordered]@{ amount = $Spend; unit = $Unit }
                notifications = @{}
            }
        }
    }

    function Get-QueryPair {
        param([string]$Path)
        $query = ($Path -split '\?', 2)[1]
        @(foreach ($pair in $query -split '&') {
            $k, $v = $pair -split '=', 2
            "$([uri]::UnescapeDataString($k))=$([uri]::UnescapeDataString($v))"
        })
    }
}

AfterAll {
    Remove-Item -Path Function:\Invoke-AzRestMethod -ErrorAction SilentlyContinue
    Remove-Variable -Name SkyCraftBudgetFake -Scope Global -ErrorAction SilentlyContinue
    if ($script:LabCommon) { Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-LabArmBudget - the request it sends' {

    It 'lists <label> with GET and api-version 2023-05-01, and nothing else in the query' -ForEach @(
        @{ label = 'a subscription'; scope = '/subscriptions/00000000-0000-0000-0000-000000000000' }
        @{ label = 'a resource group'; scope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg' }
    ) {
        Reset-BudgetFake -Reply (New-ArmReply -Body @{ value = @() })
        @(Get-LabArmBudget -Scope $scope) | Should -BeNullOrEmpty
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 1
        $call = $global:SkyCraftBudgetFake.Calls[0]
        $call.Method | Should -Be 'GET'
        ($call.Path -split '\?')[0] | Should -Be "$scope/providers/Microsoft.Consumption/budgets"
        (Get-QueryPair -Path $call.Path) -join '&' | Should -Be 'api-version=2023-05-01' -Because 'Az.Billing''s 2018-01-31 is refused with 422 (issue #411)'
    }

    It 'does not double a trailing slash on the scope' {
        Reset-BudgetFake -Reply (New-ArmReply -Body @{ value = @() })
        Get-LabArmBudget -Scope "$script:Sub/" | Out-Null
        ($global:SkyCraftBudgetFake.Calls[0].Path -split '\?')[0] | Should -Be "$script:Sub/providers/Microsoft.Consumption/budgets"
    }

    It 'refuses <label> before sending anything' -ForEach @(
        @{ label = 'a management group scope'; scope = '/providers/Microsoft.Management/managementGroups/mg' }
        @{ label = 'a resource id'; scope = '/subscriptions/0/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sa' }
        @{ label = 'a scope with a query'; scope = '/subscriptions/0?api-version=2018-01-31' }
        @{ label = 'a relative scope'; scope = 'subscriptions/0' }
    ) {
        Reset-BudgetFake
        { Get-LabArmBudget -Scope $scope } | Should -Throw
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 0
    }
}

Describe 'Get-LabArmBudget - what it returns' {

    BeforeAll {
        Reset-BudgetFake -Reply (New-ArmReply -Body @{ value = @(
                    New-ArmBudget -Name 'SkyCraft-Monthly-Budget' -Scope $script:Sub -Amount 50 -Unit 'EUR' -Spend 3.25
                    New-ArmBudget -Name 'SkyCraft-Prod-Monthly' -Scope $script:Rg -Amount 20 -Unit 'USD' -Spend 0
                ) })
        $script:Listed = @(Get-LabArmBudget -Scope $script:Sub)
    }

    It 'returns one object per budget' {
        $script:Listed.Count | Should -Be 2
        $script:Listed.Name | Should -Be @('SkyCraft-Monthly-Budget', 'SkyCraft-Prod-Monthly')
    }

    It 'carries the fields the lab scripts read' {
        $first = $script:Listed[0]
        $first.Id | Should -Be "$script:Sub/providers/Microsoft.Consumption/budgets/SkyCraft-Monthly-Budget"
        $first.Scope | Should -Be $script:Sub
        $first.Amount | Should -Be 50
        $first.Category | Should -Be 'Cost'
        $first.TimeGrain | Should -Be 'Monthly'
        $first.CurrentSpend | Should -Be 3.25
        $first.Unit | Should -Be 'EUR' -Because 'Test-Lab.ps1 prints the amount with the currency of the current spend'
    }

    It 'gives each budget the scope it is set at, taken from its id' {
        $script:Listed[1].Scope | Should -Be $script:Rg
    }
}

Describe 'Get-LabArmBudget - paging' {

    It 'follows nextLink to the last page and returns every page''s budgets' {
        $next = "https://management.azure.com$script:Sub/providers/Microsoft.Consumption/budgets?api-version=2023-05-01&%24skiptoken=page2"
        Reset-BudgetFake -Reply @(
            (New-ArmReply -Body @{ value = @(New-ArmBudget -Name 'b-1' -Scope $script:Sub); nextLink = $next })
            (New-ArmReply -Body @{ value = @(New-ArmBudget -Name 'b-2' -Scope $script:Sub) })
        )
        $listed = @(Get-LabArmBudget -Scope $script:Sub)
        $listed.Name | Should -Be @('b-1', 'b-2')
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 2
        $global:SkyCraftBudgetFake.Calls[1].Path | Should -Be "$script:Sub/providers/Microsoft.Consumption/budgets?api-version=2023-05-01&%24skiptoken=page2" -Because 'Invoke-AzRestMethod -Path takes the part after the host'
    }

    It 'stops with an error when ARM hands back a nextLink it has already followed' {
        $next = "https://management.azure.com$script:Sub/providers/Microsoft.Consumption/budgets?api-version=2023-05-01&%24skiptoken=loop"
        $page = New-ArmReply -Body @{ value = @(); nextLink = $next }
        Reset-BudgetFake -Reply @($page, $page, $page)
        { Get-LabArmBudget -Scope $script:Sub } | Should -Throw -ExpectedMessage 'Get-LabArmBudget: ARM returned the same nextLink twice*'
    }

    It 'throws when a later page fails, rather than return the pages before it' {
        $next = "https://management.azure.com$script:Sub/providers/Microsoft.Consumption/budgets?api-version=2023-05-01&%24skiptoken=page2"
        Reset-BudgetFake -Reply @(
            (New-ArmReply -Body @{ value = @(New-ArmBudget -Name 'b-1' -Scope $script:Sub); nextLink = $next })
            (New-ArmReply -StatusCode 429 -Body @{ error = @{ code = 'TooManyRequests'; message = 'slow down' } })
        )
        $listed = $null
        $thrown = $null
        try { $listed = @(Get-LabArmBudget -Scope $script:Sub) } catch { $thrown = $_ }
        "$thrown" | Should -BeLike '*HTTP 429 (TooManyRequests): slow down*'
        $listed | Should -BeNullOrEmpty -Because 'a partial list would read as "budget absent"'
    }
}

Describe 'Get-LabArmBudget - a failed read is never an empty list' {

    It 'throws on HTTP <status> with the status, the code and the message' -ForEach @(
        @{ status = 422; code = '422'; message = 'This operation is not supported in the version specified in the request. Please use version 2018-12-01-preview or later.' }
        @{ status = 403; code = 'AuthorizationFailed'; message = "The client 'stub' does not have authorization to perform action 'Microsoft.Consumption/budgets/read'" }
        @{ status = 429; code = 'TooManyRequests'; message = 'Number of read requests exceeded the limit' }
        @{ status = 404; code = 'ResourceGroupNotFound'; message = "Resource group 'prod-skycraft-swc-rg' could not be found." }
        @{ status = 500; code = 'InternalServerError'; message = 'boom' }
    ) {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode $status -Body @{ error = @{ code = $code; message = $message } })
        $thrown = $null
        try { Get-LabArmBudget -Scope $script:Rg } catch { $thrown = $_ }
        $thrown | Should -Not -BeNullOrEmpty
        "$thrown" | Should -BeLike "ARM GET $script:Rg/providers/Microsoft.Consumption/budgets returned HTTP $status ($code): *"
        "$thrown" | Should -BeLike "*$message*"
        $thrown.FullyQualifiedErrorId | Should -BeLike "$code*" -Because 'the cleanups tell "not found" from "failed" by the error code'
        $thrown.Exception.Data['StatusCode'] | Should -Be $status
    }

    It 'throws on an error status with no JSON body, naming the status' {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode 502 -Body 'Bad Gateway')
        { Get-LabArmBudget -Scope $script:Sub } | Should -Throw -ExpectedMessage '*HTTP 502 (HTTP502): Bad Gateway*'
    }

    It 'throws on a 2xx answer that is not JSON' {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode 200 -Body '<html>sign in</html>')
        { Get-LabArmBudget -Scope $script:Sub } | Should -Throw -ExpectedMessage '*not JSON*'
    }

    It 'throws on a 2xx answer without a value list' {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode 200 -Body @{ something = 'else' })
        { Get-LabArmBudget -Scope $script:Sub } | Should -Throw -ExpectedMessage "Get-LabArmBudget: ARM answered GET*without a 'value' list*"
    }

    It 'lets an error from Invoke-AzRestMethod itself through (no token, no network)' {
        Reset-BudgetFake
        { Get-LabArmBudget -Scope $script:Sub } | Should -Throw -ExpectedMessage '*no reply queued*'
    }
}

Describe 'Remove-LabArmBudget - the request it sends' {

    It 'DELETEs the budget by name at <label> and accepts HTTP <status>' -ForEach @(
        @{ label = 'the subscription'; scope = '/subscriptions/00000000-0000-0000-0000-000000000000'; status = 200 }
        @{ label = 'a resource group'; scope = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/prod-skycraft-swc-rg'; status = 204 }
    ) {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode $status)
        { Remove-LabArmBudget -Scope $scope -Name 'SkyCraft-Monthly-Budget' } | Should -Not -Throw
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 1
        $call = $global:SkyCraftBudgetFake.Calls[0]
        $call.Method | Should -Be 'DELETE'
        $call.Path | Should -Be "$scope/providers/Microsoft.Consumption/budgets/SkyCraft-Monthly-Budget?api-version=2023-05-01"
    }

    It 'returns nothing on success' {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode 200 -Body (New-ArmBudget -Name 'SkyCraft-Monthly-Budget' -Scope $script:Sub))
        @(Remove-LabArmBudget -Scope $script:Sub -Name 'SkyCraft-Monthly-Budget') | Should -BeNullOrEmpty
    }

    It 'throws on a refused delete, HTTP <status>, with the status, the code and the message' -ForEach @(
        @{ status = 403; code = 'AuthorizationFailed'; message = 'no delete' }
        @{ status = 409; code = 'ScopeLocked'; message = "The scope '/subscriptions/0/resourceGroups/prod-skycraft-swc-rg' cannot perform delete operation because it is locked." }
        @{ status = 422; code = '422'; message = 'Please use version 2018-12-01-preview or later.' }
    ) {
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode $status -Body @{ error = @{ code = $code; message = $message } })
        { Remove-LabArmBudget -Scope $script:Rg -Name 'SkyCraft-Prod-Monthly' } |
            Should -Throw -ExpectedMessage "ARM DELETE $script:Rg/providers/Microsoft.Consumption/budgets/SkyCraft-Prod-Monthly returned HTTP $status ($code): $message"
    }

    It 'throws on a 404, rather than assume the budget is already gone' {
        # The cleanup lists before it deletes, so a 404 here is a race worth reporting.
        Reset-BudgetFake -Reply (New-ArmReply -StatusCode 404 -Body @{ error = @{ code = 'NotFound'; message = 'Budget not found.' } })
        { Remove-LabArmBudget -Scope $script:Sub -Name 'SkyCraft-Monthly-Budget' } | Should -Throw -ExpectedMessage '*HTTP 404 (NotFound)*'
    }

    It 'refuses the name <name> before sending anything' -ForEach @(
        @{ name = '../roleAssignments/x' }
        @{ name = 'a?api-version=2018-01-31' }
        @{ name = 'with space' }
        @{ name = ('b' * 64) }
    ) {
        Reset-BudgetFake
        { Remove-LabArmBudget -Scope $script:Sub -Name $name } | Should -Throw
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 0
    }

    It 'refuses a scope that is neither a subscription nor a resource group, before sending anything' {
        Reset-BudgetFake
        { Remove-LabArmBudget -Scope '/providers/Microsoft.Management/managementGroups/mg' -Name 'b' } | Should -Throw
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 0
    }

    It 'sends nothing with -WhatIf' {
        Reset-BudgetFake
        Remove-LabArmBudget -Scope $script:Sub -Name 'SkyCraft-Monthly-Budget' -WhatIf
        $global:SkyCraftBudgetFake.Calls.Count | Should -Be 0
    }
}
