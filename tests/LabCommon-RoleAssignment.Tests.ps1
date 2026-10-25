<#
.SYNOPSIS
    Pester 5 tests for the role assignment helpers of tools/LabCommon.psm1 (issue #397).

.DESCRIPTION
    Every form of Get-AzRoleAssignment, and New-AzRoleAssignment and Remove-AzRoleAssignment, call
    Microsoft Graph to resolve the principals. Where the Az sign-in cannot get a Graph token without
    interaction they fail, although the Azure Resource Manager token works, and a lab script that
    passed -ErrorAction SilentlyContinue read "no assignment" when there was one. The lab scripts
    now go through Get-LabArmRoleAssignment, New-LabArmRoleAssignment and
    Remove-LabArmRoleAssignment, which call the ARM role assignments API through
    Invoke-AzRestMethod. These tests pin what those helpers send and how they read the answer:

      1. A listing sends GET <scope>/providers/Microsoft.Authorization/roleAssignments with
         api-version 2022-04-01, and the principalId or atScope() filter URL-encoded; a principal
         id that is not a GUID is refused before anything is sent.
      2. A listing follows nextLink to the last page, and stops with an error on a nextLink it has
         already followed.
      3. Each assignment comes back with the fields the lab scripts read: RoleAssignmentId, Scope,
         ObjectId / PrincipalId, RoleDefinitionId as the role's GUID, RoleDefinitionName for the
         built-in roles the labs use.
      4. A status outside 2xx throws with the status, ARM's error code and its message - never an
         empty list - and a 2xx answer that is not a role assignment list throws too.
      5. A create sends PUT <scope>/providers/Microsoft.Authorization/roleAssignments/<new GUID>
         with properties.roleDefinitionId as the full id under the scope's subscription,
         principalId, and principalType when it is given.
      6. A removal sends DELETE <id>; 200 and 204 are success, anything else throws.

    No subscription is needed, and none is used: a global function named Invoke-AzRestMethod
    answers in place of the Az.Accounts cmdlet (a function outranks a cmdlet, so it does so with
    Az installed too, and CI has no Az). It records every request and replies from a queue the
    test fills.

.EXAMPLE
    Invoke-Pester -Path .\tests\LabCommon-RoleAssignment.Tests.ps1

.NOTES
    Project: SkyCraft
    Issue: #397
#>

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:LabCommonPath = Join-Path $PSScriptRoot '..' 'tools' 'LabCommon.psm1'
    $script:LabCommon = Import-Module $script:LabCommonPath -Force -PassThru

    $script:Sub = '/subscriptions/00000000-0000-0000-0000-000000000000'
    $script:PrincipalId = '11111111-1111-1111-1111-111111111111'

    # The fake: every request is recorded; the reply is the next queued one.
    $global:SkyCraftArmFake = [pscustomobject]@{
        Calls   = [System.Collections.Generic.List[object]]::new()
        Replies = [System.Collections.Generic.Queue[object]]::new()
    }
    function global:Invoke-AzRestMethod {
        [CmdletBinding()]
        param([string]$Path, [string]$Method = 'GET', [string]$Payload)
        $global:SkyCraftArmFake.Calls.Add([pscustomobject]@{ Method = $Method; Path = $Path; Payload = $Payload })
        if ($global:SkyCraftArmFake.Replies.Count -eq 0) { throw "fake: no reply queued for $Method $Path" }
        $global:SkyCraftArmFake.Replies.Dequeue()
    }

    function Reset-ArmFake {
        param([object[]]$Reply = @())
        $global:SkyCraftArmFake.Calls.Clear()
        $global:SkyCraftArmFake.Replies.Clear()
        foreach ($item in $Reply) { $global:SkyCraftArmFake.Replies.Enqueue($item) }
    }

    function New-ArmReply {
        param([int]$StatusCode = 200, [object]$Body)
        $content = if ($null -eq $Body) { '' } elseif ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 10 -Compress }
        [pscustomobject]@{ StatusCode = $StatusCode; Content = $content }
    }

    function New-ArmAssignment {
        param([string]$Name, [string]$Scope, [string]$PrincipalId, [string]$Role, [string]$PrincipalType = 'User')
        [ordered]@{
            id         = "$Scope/providers/Microsoft.Authorization/roleAssignments/$Name"
            name       = $Name
            type       = 'Microsoft.Authorization/roleAssignments'
            properties = [ordered]@{
                roleDefinitionId = "$script:Sub/providers/Microsoft.Authorization/roleDefinitions/$Role"
                principalId      = $PrincipalId
                principalType    = $PrincipalType
                scope            = $Scope
            }
        }
    }

    function Get-QueryValue {
        param([string]$Path, [string]$Key)
        $query = ($Path -split '\?', 2)[1]
        foreach ($pair in $query -split '&') {
            $k, $v = $pair -split '=', 2
            if ([uri]::UnescapeDataString($k) -eq $Key) { return [uri]::UnescapeDataString($v) }
        }
    }
}

AfterAll {
    Remove-Item -Path Function:\Invoke-AzRestMethod -ErrorAction SilentlyContinue
    Remove-Variable -Name SkyCraftArmFake -Scope Global -ErrorAction SilentlyContinue
    if ($script:LabCommon) { Remove-Module -ModuleInfo $script:LabCommon -Force -ErrorAction SilentlyContinue }
}

Describe 'Get-LabArmRoleAssignment - the request it sends' {

    It 'lists a scope with GET and api-version 2022-04-01, with no filter' {
        Reset-ArmFake -Reply (New-ArmReply -Body @{ value = @() })
        @(Get-LabArmRoleAssignment -Scope $script:Sub) | Should -BeNullOrEmpty
        $call = $global:SkyCraftArmFake.Calls[0]
        $call.Method | Should -Be 'GET'
        ($call.Path -split '\?')[0] | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleAssignments"
        Get-QueryValue -Path $call.Path -Key 'api-version' | Should -Be '2022-04-01'
        Get-QueryValue -Path $call.Path -Key '$filter' | Should -BeNullOrEmpty
    }

    It 'filters by principal id, URL-encoded' {
        Reset-ArmFake -Reply (New-ArmReply -Body @{ value = @() })
        Get-LabArmRoleAssignment -Scope "$script:Sub/" -PrincipalId $script:PrincipalId | Out-Null
        $path = $global:SkyCraftArmFake.Calls[0].Path
        $path | Should -Match '\$filter=principalId%20eq%20%2711111111-1111-1111-1111-111111111111%27'
        $path | Should -Not -Match ' '
        Get-QueryValue -Path $path -Key '$filter' | Should -Be "principalId eq '11111111-1111-1111-1111-111111111111'"
        ($path -split '\?')[0] | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleAssignments" -Because 'a trailing slash on the scope must not double'
    }

    It 'filters to the scope and above with -AtScope' {
        Reset-ArmFake -Reply (New-ArmReply -Body @{ value = @() })
        Get-LabArmRoleAssignment -Scope $script:Sub -AtScope | Out-Null
        Get-QueryValue -Path $global:SkyCraftArmFake.Calls[0].Path -Key '$filter' | Should -Be 'atScope()'
    }

    It 'refuses a principal id that is not a GUID, before sending anything' {
        Reset-ArmFake
        { Get-LabArmRoleAssignment -Scope $script:Sub -PrincipalId "x' or principalId ne 'y" } | Should -Throw
        $global:SkyCraftArmFake.Calls.Count | Should -Be 0
    }
}

Describe 'Get-LabArmRoleAssignment - what it returns' {

    BeforeAll {
        Reset-ArmFake -Reply (New-ArmReply -Body @{ value = @(
                    New-ArmAssignment -Name 'ra-1' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
                    New-ArmAssignment -Name 'ra-2' -Scope "$script:Sub/resourceGroups/dev-skycraft-swc-rg" -PrincipalId '22222222-2222-2222-2222-222222222222' -Role '00000000-0000-0000-0000-00000000beef' -PrincipalType 'Group'
                ) })
        $script:Listed = @(Get-LabArmRoleAssignment -Scope $script:Sub)
    }

    It 'returns one object per assignment' {
        $script:Listed.Count | Should -Be 2
    }

    It 'carries the fields the lab scripts read' {
        $first = $script:Listed[0]
        $first.RoleAssignmentId | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleAssignments/ra-1"
        $first.RoleAssignmentName | Should -Be 'ra-1'
        $first.Scope | Should -Be $script:Sub
        $first.ObjectId | Should -Be $script:PrincipalId
        $first.PrincipalId | Should -Be $script:PrincipalId
        $first.PrincipalType | Should -Be 'User'
        $first.RoleDefinitionId | Should -Be '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' -Because 'callers compare the bare GUID, as Get-AzRoleAssignment returned it'
        $first.RoleDefinitionResourceId | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635"
        $first.RoleDefinitionName | Should -Be 'Owner'
    }

    It 'leaves RoleDefinitionName empty for a role that is not one of the labs'' built-in roles' {
        $script:Listed[1].RoleDefinitionName | Should -Be ''
        $script:Listed[1].ObjectType | Should -Be 'Group'
    }
}

Describe 'Get-LabArmRoleAssignment - paging' {

    It 'follows nextLink to the last page and returns every page''s assignments' {
        $next = "https://management.azure.com$script:Sub/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&%24skiptoken=page2"
        Reset-ArmFake -Reply @(
            (New-ArmReply -Body @{ value = @(New-ArmAssignment -Name 'ra-1' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role 'b24988ac-6180-42a0-ab88-20f7382dd24c'); nextLink = $next })
            (New-ArmReply -Body @{ value = @(New-ArmAssignment -Name 'ra-2' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7') })
        )
        $listed = @(Get-LabArmRoleAssignment -Scope $script:Sub)
        $listed.RoleAssignmentName | Should -Be @('ra-1', 'ra-2')
        $global:SkyCraftArmFake.Calls.Count | Should -Be 2
        $global:SkyCraftArmFake.Calls[1].Path | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&%24skiptoken=page2" -Because 'Invoke-AzRestMethod -Path takes the part after the host'
    }

    It 'stops with an error when ARM hands back a nextLink it has already followed' {
        $next = "https://management.azure.com$script:Sub/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&%24skiptoken=loop"
        $page = New-ArmReply -Body @{ value = @(); nextLink = $next }
        Reset-ArmFake -Reply @($page, $page, $page)
        { Get-LabArmRoleAssignment -Scope $script:Sub } | Should -Throw -ExpectedMessage '*same nextLink*'
    }

    It 'throws when a later page fails, rather than return the pages before it' {
        $next = "https://management.azure.com$script:Sub/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&%24skiptoken=page2"
        Reset-ArmFake -Reply @(
            (New-ArmReply -Body @{ value = @(New-ArmAssignment -Name 'ra-1' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role 'b24988ac-6180-42a0-ab88-20f7382dd24c'); nextLink = $next })
            (New-ArmReply -StatusCode 429 -Body @{ error = @{ code = 'TooManyRequests'; message = 'slow down' } })
        )
        { Get-LabArmRoleAssignment -Scope $script:Sub } | Should -Throw -ExpectedMessage '*429*TooManyRequests*'
    }
}

Describe 'Get-LabArmRoleAssignment - a failed read is never an empty list' {

    It 'throws on HTTP <status> with the status, the code and the message' -ForEach @(
        @{ status = 403; code = 'AuthorizationFailed'; message = "The client 'stub' does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/read'" }
        @{ status = 429; code = 'TooManyRequests'; message = 'Number of read requests exceeded the limit' }
        @{ status = 404; code = 'ResourceNotFound'; message = "The Resource 'Microsoft.Storage/storageAccounts/x' under resource group 'rg' was not found." }
        @{ status = 500; code = 'InternalServerError'; message = 'boom' }
    ) {
        Reset-ArmFake -Reply (New-ArmReply -StatusCode $status -Body @{ error = @{ code = $code; message = $message } })
        $thrown = $null
        try { Get-LabArmRoleAssignment -Scope $script:Sub } catch { $thrown = $_ }
        $thrown | Should -Not -BeNullOrEmpty
        "$thrown" | Should -BeLike "*HTTP $status ($code)*"
        "$thrown" | Should -BeLike "*$message*"
        $thrown.FullyQualifiedErrorId | Should -BeLike "$code*" -Because 'the cleanups tell "not found" from "failed" by the error code'
    }

    It 'throws on an error status with no JSON body, naming the status' {
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 502 -Body 'Bad Gateway')
        { Get-LabArmRoleAssignment -Scope $script:Sub } | Should -Throw -ExpectedMessage '*HTTP 502 (HTTP502): Bad Gateway*'
    }

    It 'throws on a 2xx answer that is not JSON' {
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 200 -Body '<html>sign in</html>')
        { Get-LabArmRoleAssignment -Scope $script:Sub } | Should -Throw -ExpectedMessage '*not JSON*'
    }

    It 'throws on a 2xx answer without a value list' {
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 200 -Body @{ something = 'else' })
        { Get-LabArmRoleAssignment -Scope $script:Sub } | Should -Throw -ExpectedMessage "*without a 'value' list*"
    }

    It 'lets an error from Invoke-AzRestMethod itself through (no token, no network)' {
        Reset-ArmFake
        { Get-LabArmRoleAssignment -Scope $script:Sub } | Should -Throw -ExpectedMessage '*no reply queued*'
    }
}

Describe 'New-LabArmRoleAssignment - the request it sends' {

    It 'PUTs a new GUID name with the full role id, the principal and its type' {
        $created = New-ArmAssignment -Name 'new' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role 'b24988ac-6180-42a0-ab88-20f7382dd24c' -PrincipalType 'ServicePrincipal'
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 201 -Body $created)
        $result = New-LabArmRoleAssignment -Scope $script:Sub -RoleDefinitionId 'b24988ac-6180-42a0-ab88-20f7382dd24c' -PrincipalId $script:PrincipalId -PrincipalType ServicePrincipal

        $call = $global:SkyCraftArmFake.Calls[0]
        $call.Method | Should -Be 'PUT'
        $resource = ($call.Path -split '\?')[0]
        $resource | Should -Match "^$([regex]::Escape($script:Sub))/providers/Microsoft\.Authorization/roleAssignments/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        Get-QueryValue -Path $call.Path -Key 'api-version' | Should -Be '2022-04-01'

        $body = $call.Payload | ConvertFrom-Json
        $body.properties.roleDefinitionId | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"
        $body.properties.principalId | Should -Be $script:PrincipalId
        $body.properties.principalType | Should -Be 'ServicePrincipal'
        @($body.properties.PSObject.Properties.Name) | Should -Be @('roleDefinitionId', 'principalId', 'principalType')

        $result.RoleDefinitionId | Should -Be 'b24988ac-6180-42a0-ab88-20f7382dd24c'
        $result.ObjectId | Should -Be $script:PrincipalId
    }

    It 'takes the role id under the subscription of a resource scope, and sends no principalType when none is given' {
        $scope = "$script:Sub/resourceGroups/dev-skycraft-swc-rg"
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 201 -Body (New-ArmAssignment -Name 'new' -Scope $scope -PrincipalId $script:PrincipalId -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7'))
        New-LabArmRoleAssignment -Scope $scope -RoleDefinitionId 'acdd72a7-3385-48ef-bd42-f606fba81ae7' -PrincipalId $script:PrincipalId | Out-Null
        $body = $global:SkyCraftArmFake.Calls[0].Payload | ConvertFrom-Json
        $body.properties.roleDefinitionId | Should -Be "$script:Sub/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        @($body.properties.PSObject.Properties.Name) | Should -Not -Contain 'principalType'
    }

    It 'keeps a full role definition id as given' {
        $full = "$script:Sub/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 201 -Body (New-ArmAssignment -Name 'new' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role 'acdd72a7-3385-48ef-bd42-f606fba81ae7'))
        New-LabArmRoleAssignment -Scope $script:Sub -RoleDefinitionId $full -PrincipalId $script:PrincipalId -PrincipalType User | Out-Null
        ($global:SkyCraftArmFake.Calls[0].Payload | ConvertFrom-Json).properties.roleDefinitionId | Should -Be $full
    }

    It 'throws on a refused create, with the code a caller retries on' -ForEach @(
        @{ status = 403; code = 'AuthorizationFailed' }
        @{ status = 409; code = 'RoleAssignmentExists' }
        @{ status = 400; code = 'PrincipalNotFound' }
    ) {
        Reset-ArmFake -Reply (New-ArmReply -StatusCode $status -Body @{ error = @{ code = $code; message = 'refused' } })
        { New-LabArmRoleAssignment -Scope $script:Sub -RoleDefinitionId 'b24988ac-6180-42a0-ab88-20f7382dd24c' -PrincipalId $script:PrincipalId } |
            Should -Throw -ExpectedMessage "*HTTP $status ($code): refused*"
    }
}

Describe 'Remove-LabArmRoleAssignment - the request it sends' {

    It 'DELETEs the assignment by its id and accepts HTTP <status>' -ForEach @(
        @{ status = 200 }
        @{ status = 204 }
    ) {
        $id = "$script:Sub/providers/Microsoft.Authorization/roleAssignments/ra-1"
        $reply = if ($status -eq 200) { New-ArmReply -StatusCode 200 -Body (New-ArmAssignment -Name 'ra-1' -Scope $script:Sub -PrincipalId $script:PrincipalId -Role 'b24988ac-6180-42a0-ab88-20f7382dd24c') } else { New-ArmReply -StatusCode 204 }
        Reset-ArmFake -Reply $reply
        { Remove-LabArmRoleAssignment -Id $id } | Should -Not -Throw
        $global:SkyCraftArmFake.Calls[0].Method | Should -Be 'DELETE'
        $global:SkyCraftArmFake.Calls[0].Path | Should -Be "$($id)?api-version=2022-04-01"
    }

    It 'throws on a refused delete' {
        Reset-ArmFake -Reply (New-ArmReply -StatusCode 403 -Body @{ error = @{ code = 'AuthorizationFailed'; message = 'no delete' } })
        { Remove-LabArmRoleAssignment -Id "$script:Sub/providers/Microsoft.Authorization/roleAssignments/ra-1" } |
            Should -Throw -ExpectedMessage '*HTTP 403 (AuthorizationFailed): no delete*'
    }

    It 'refuses an id that is not a role assignment id' {
        Reset-ArmFake
        { Remove-LabArmRoleAssignment -Id "$script:Sub/resourceGroups/dev-skycraft-swc-rg" } | Should -Throw
        $global:SkyCraftArmFake.Calls.Count | Should -Be 0
    }
}

Describe 'Get-LabBuiltInRoleId and Get-LabGraphSignInHint' {

    It 'returns the fixed id of <name>' -ForEach @(
        @{ name = 'Owner'; id = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635' }
        @{ name = 'Contributor'; id = 'b24988ac-6180-42a0-ab88-20f7382dd24c' }
        @{ name = 'Reader'; id = 'acdd72a7-3385-48ef-bd42-f606fba81ae7' }
        @{ name = 'Storage Blob Data Contributor'; id = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe' }
        @{ name = 'Storage Blob Data Owner'; id = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' }
        @{ name = 'Storage Account Backup Contributor'; id = 'e5e2a7ff-d759-4cd2-bb51-3152d37e2eb1' }
    ) {
        Get-LabBuiltInRoleId -Name $name | Should -Be $id
    }

    It 'throws for a role it does not know, rather than guess' {
        { Get-LabBuiltInRoleId -Name 'Owner2' } | Should -Throw -ExpectedMessage '*not one of the built-in roles*'
    }

    It 'names the sign-in that gives <client> Microsoft Graph' -ForEach @(
        @{ client = 'Az'; signIn = 'Connect-AzAccount -AuthScope MicrosoftGraphEndpointResourceId' }
        @{ client = 'MgGraph'; signIn = 'Connect-MgGraph' }
    ) {
        Get-LabGraphSignInHint -Client $client | Should -BeLike "*$signIn*"
    }
}
